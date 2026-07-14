<#
    Shared helpers for driving Renode from PowerShell: locating the binary, and
    talking to a headless instance over its telnet monitor.

    Dot-source it:  . "$PSScriptRoot\renode-monitor.ps1"
#>

function Find-Renode {
    if ($env:RENODE_PATH) {
        if (Test-Path $env:RENODE_PATH) { return $env:RENODE_PATH }
        throw "RENODE_PATH is set to '$env:RENODE_PATH' but that file does not exist."
    }

    $onPath = Get-Command 'renode' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    foreach ($candidate in @(
            "$env:ProgramFiles\Renode\bin\Renode.exe",
            "$env:ProgramFiles\Renode\Renode.exe",
            "$env:USERPROFILE\tools\renode\*\renode.exe")) {
        $hit = Get-Item -Path $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }

    throw @"
Renode not found.

Install it, then re-run:
    winget install --id Renode.Renode -e
or unpack the portable archive and point RENODE_PATH at renode.exe.
"@
}

<#
    Removes the %TEMP%\renode-<pid> directories left behind by instances that
    were killed rather than asked to quit.

    They are not harmless litter. On start-up Renode's TemporaryFilesManager
    walks them and calls Process.HasExited on each PID in the name. Once the OS
    recycles one of those PIDs onto a process we are not allowed to open (a
    service host, say), that call throws a Win32 "access denied" which nothing
    catches, and Renode dies before it ever runs the script - surfacing here as
    a connection reset on the first monitor command.
#>
function Clear-RenodeTempDirectories {
    Get-ChildItem -Path $env:TEMP -Directory -Filter 'renode-*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
}

<#
    Boots a headless Renode and returns a session once its monitor is genuinely
    ready to accept commands.

    The wait for the banner is the whole point. Renode's telnet port starts
    accepting connections before the monitor behind it is up, and it drops those
    early sockets: connecting on the first successful TcpClient.Connect() is a
    race that shows up as "connection forcibly closed by the remote host" on the
    first write. So we connect, wait for Renode to greet us, and only then hand
    the session back — retrying the whole dance if it does not.
#>
function Start-RenodeMonitor {
    param(
        [int]$Port = 1234,
        [int]$TimeoutSec = 90
    )

    Get-Process -Name 'renode' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 400
    Clear-RenodeTempDirectories

    $renode = Find-Renode
    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()

    $proc = Start-Process -FilePath $renode `
        -ArgumentList @('--disable-xwt', '--plain', '-P', "$Port") `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($proc.HasExited) {
            $why = (Get-Content -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue) -join "`n"
            throw "Renode exited during start-up (code $($proc.ExitCode)).`n$why"
        }

        $client = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect('127.0.0.1', $Port)
        } catch {
            if ($client) { try { $client.Close() } catch { } }
            Start-Sleep -Milliseconds 300
            continue
        }

        $stream = $client.GetStream()
        $banner = ''
        $buf = New-Object byte[] 4096
        $greet = (Get-Date).AddSeconds(8)
        try {
            while ((Get-Date) -lt $greet) {
                if ($stream.DataAvailable) {
                    $n = $stream.Read($buf, 0, $buf.Length)
                    if ($n -gt 0) {
                        $banner += [System.Text.Encoding]::ASCII.GetString($buf, 0, $n)
                    }
                    if ($banner -match 'Renode, version') { break }
                }
                Start-Sleep -Milliseconds 100
            }
        } catch {
            $banner = ''
        }

        if ($banner -match 'Renode, version') {
            return [pscustomobject]@{
                Process = $proc
                Client  = $client
                Stream  = $stream
                StdOut  = $stdout
                StdErr  = $stderr
            }
        }

        # Too early: Renode is not talking yet. Drop this socket and try again.
        try { $client.Close() } catch { }
        Start-Sleep -Milliseconds 500
    }

    try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
    throw "Renode's monitor on port $Port never became ready within ${TimeoutSec}s."
}

# Sends one monitor command and returns whatever Renode printed back.
function Send-RenodeCommand {
    param(
        [Parameter(Mandatory)] $Session,
        [Parameter(Mandatory)] [string]$Command,
        [int]$SettleMs = 700
    )

    if ($Session.Process.HasExited) {
        $why = (Get-Content -LiteralPath $Session.StdOut, $Session.StdErr -ErrorAction SilentlyContinue) -join "`n"
        throw "Renode is no longer running.`n$why"
    }

    $bytes = [System.Text.Encoding]::ASCII.GetBytes("$Command`n")
    $Session.Stream.Write($bytes, 0, $bytes.Length)
    $Session.Stream.Flush()
    Start-Sleep -Milliseconds $SettleMs

    $reply = ''
    $buf = New-Object byte[] 65536
    while ($Session.Stream.DataAvailable) {
        $n = $Session.Stream.Read($buf, 0, $buf.Length)
        if ($n -le 0) { break }
        $reply += [System.Text.Encoding]::ASCII.GetString($buf, 0, $n)
        Start-Sleep -Milliseconds 60
    }
    return $reply
}

function Stop-RenodeMonitor {
    param($Session)

    if (-not $Session) { return }

    # Ask Renode to quit rather than killing it: a graceful exit removes its own
    # temp directory, and it is exactly the orphaned ones that poison the next
    # start-up (see Clear-RenodeTempDirectories).
    try {
        if (-not $Session.Process.HasExited) {
            $bye = [System.Text.Encoding]::ASCII.GetBytes("quit`n")
            $Session.Stream.Write($bye, 0, $bye.Length)
            $Session.Stream.Flush()
            [void]$Session.Process.WaitForExit(8000)
        }
    } catch { }

    try { $Session.Client.Close() } catch { }
    try { if (-not $Session.Process.HasExited) { $Session.Process.Kill() } } catch { }

    foreach ($tmp in @($Session.StdOut, $Session.StdErr)) {
        if ($tmp -and (Test-Path $tmp)) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    Clear-RenodeTempDirectories
}
