<#
    Live 3D view of the attitude loop, with no dependencies to install.

    Renode has no 3D viewer, but the firmware already publishes everything the
    view needs on USART2. This script wires that up:

        firmware --UART--> Renode --TCP--> viz.ps1 --SSE--> browser (canvas 3D)
                                              ^
                                              +-- monitor commands from the page

    It boots Renode headless, connects USART2 to a socket terminal, serves
    index.html on http://localhost:8080, streams every telemetry line to the
    page, and forwards the page's buttons back to the Renode monitor.

    Ctrl+C to stop; Renode is torn down with it.
#>
[CmdletBinding()]
param(
    [int]$HttpPort = 8080,
    [int]$UartPort = 3456,
    [int]$MonitorPort = 1234,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent

. (Join-Path $projectRoot 'renode-monitor.ps1')

$elf = Join-Path $projectRoot 'build\firmware.elf'
if (-not (Test-Path $elf)) { throw "build\firmware.elf not found - run .\build.ps1 first." }

$indexHtml = Join-Path $PSScriptRoot 'index.html'
if (-not (Test-Path $indexHtml)) { throw "viz\index.html is missing." }

$toFwd = { param($p) $p -replace '\\', '/' }
$renodeDir = & $toFwd (Join-Path $projectRoot 'renode')
$elfFwd = & $toFwd $elf

$session = $null
$uart = $null
$listener = $null
$sse = New-Object System.Collections.ArrayList

try {
    Write-Host 'booting the machine...'
    $session = Start-RenodeMonitor -Port $MonitorPort

    [void](Send-RenodeCommand $session 'mach create "attitude"')
    [void](Send-RenodeCommand $session "include @$renodeDir/gyro1d.cs" 7000)
    [void](Send-RenodeCommand $session "machine LoadPlatformDescription @$renodeDir/attitude.repl" 4000)
    [void](Send-RenodeCommand $session "sysbus LoadELF @$elfFwd" 5000)

    # USART2 out of the emulator and onto a socket this script can read.
    [void](Send-RenodeCommand $session "emulation CreateServerSocketTerminal $UartPort ""viz"" false")
    [void](Send-RenodeCommand $session 'connector Connect sysbus.usart2 viz')
    [void](Send-RenodeCommand $session 'start' 1500)

    # --------------------------------------------------------- UART stream ----
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        try {
            $uart = New-Object System.Net.Sockets.TcpClient
            $uart.Connect('127.0.0.1', $UartPort)
            break
        } catch {
            $uart = $null
            Start-Sleep -Milliseconds 250
        }
    }
    if (-not $uart) { throw "Could not attach to the UART socket on port $UartPort" }
    $uartStream = $uart.GetStream()

    # --------------------------------------------------------- HTTP server ----
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$HttpPort/")
    $listener.Start()

    Write-Host ''
    Write-Host "  view    : http://localhost:$HttpPort" -ForegroundColor Green
    Write-Host '  stop    : Ctrl+C'
    Write-Host ''

    if (-not $NoBrowser) { Start-Process "http://localhost:$HttpPort" }

    $ascii = [System.Text.Encoding]::ASCII
    $html = [System.IO.File]::ReadAllBytes($indexHtml)
    $ctxTask = $listener.GetContextAsync()
    $pending = ''
    $buf = New-Object byte[] 8192

    while ($true) {
        if ($session.Process.HasExited) { throw 'Renode exited unexpectedly.' }

        # --- serve HTTP ---
        if ($ctxTask.IsCompleted) {
            $ctx = $ctxTask.Result
            $req = $ctx.Request
            $res = $ctx.Response
            $path = $req.Url.AbsolutePath

            if ($path -eq '/events') {
                $res.StatusCode = 200
                $res.ContentType = 'text/event-stream'
                $res.Headers.Add('Cache-Control', 'no-cache')
                $res.SendChunked = $true
                [void]$sse.Add($res)
                # left open on purpose: this is the live stream
            } elseif ($path -eq '/cmd') {
                $c = $req.QueryString['c']
                if ($c) {
                    Write-Host "  > $c"
                    [void](Send-RenodeCommand $session $c 60)
                }
                $res.StatusCode = 204
                $res.Close()
            } else {
                $res.StatusCode = 200
                $res.ContentType = 'text/html; charset=utf-8'
                $res.ContentLength64 = $html.Length
                $res.OutputStream.Write($html, 0, $html.Length)
                $res.Close()
            }
            $ctxTask = $listener.GetContextAsync()
        }

        # --- pump the UART into the page ---
        while ($uartStream.DataAvailable) {
            $n = $uartStream.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $pending += $ascii.GetString($buf, 0, $n)
            while ($pending.Contains("`n")) {
                $idx = $pending.IndexOf("`n")
                $line = $pending.Substring(0, $idx).TrimEnd("`r")
                $pending = $pending.Substring($idx + 1)
                if ($line.Trim()) {
                    $payload = $ascii.GetBytes("data: $line`n`n")
                    foreach ($client in @($sse)) {
                        try {
                            $client.OutputStream.Write($payload, 0, $payload.Length)
                            $client.OutputStream.Flush()
                        } catch {
                            [void]$sse.Remove($client)
                            try { $client.Close() } catch { }
                        }
                    }
                }
            }
        }

        Start-Sleep -Milliseconds 20
    }
} finally {
    Write-Host ''
    Write-Host 'shutting down...'
    foreach ($client in @($sse)) { try { $client.Close() } catch { } }
    if ($listener) { try { $listener.Stop() } catch { } }
    if ($uart) { try { $uart.Close() } catch { } }
    Stop-RenodeMonitor $session
}
