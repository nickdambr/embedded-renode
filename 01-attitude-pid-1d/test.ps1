<#
    Headless regression test.

    Drives Renode over its telnet monitor with no GUI and replays the two demo
    scenarios, each on a freshly created machine, asserting on the firmware's
    own telemetry:

      1. bring-up    : the gyro answers WHO_AM_I = 0xD4 over I2C
      2. open loop   : a +30 deg/s disturbance is measured exactly, and the
                       controller pushes the PWM hard the other way
      3. closed loop : with the plant model live, the same disturbance decays
                       back to zero and the command returns to neutral

    Exit code 0 on success, 1 if any assertion fails.
#>
[CmdletBinding()]
param(
    [int]$Port = 3579
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot

# ---------------------------------------------------------------- helpers ----

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
    throw "Renode not found. Install it (winget install --id Renode.Renode -e) or set RENODE_PATH."
}

$script:failures = 0

function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        Write-Host "  PASS  $Name"
    } else {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor Red }
        $script:failures++
    }
}

# Telemetry lines look like:
#   t=+1.20 s  rate=-2.52 dps  angle=-0.23 deg  duty=+2.4 %  ccr=102
function Get-Telemetry {
    param([string[]]$LogLines)
    $rx = 't=([+-][\d.]+) s\s+rate=([+-][\d.]+) dps\s+angle=([+-][\d.]+) deg\s+duty=([+-][\d.]+) %\s+ccr=(\d+)'
    $samples = @()
    foreach ($line in $LogLines) {
        $m = [regex]::Match($line, $rx)
        if ($m.Success) {
            $samples += [pscustomobject]@{
                T     = [double]$m.Groups[1].Value
                Rate  = [double]$m.Groups[2].Value
                Angle = [double]$m.Groups[3].Value
                Duty  = [double]$m.Groups[4].Value
                Ccr   = [int]$m.Groups[5].Value
            }
        }
    }
    return $samples
}

# Boots one Renode instance, feeds it the scenario, and returns the log it wrote.
function Invoke-RenodeScenario {
    param([string[]]$Commands, [string]$LogPath)

    $renode = Find-Renode
    Get-Process -Name 'renode' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300

    $proc = Start-Process -FilePath $renode `
        -ArgumentList @('--disable-xwt', '--plain', '-P', "$Port") `
        -PassThru -WindowStyle Hidden

    try {
        $client = $null
        $deadline = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $deadline) {
            try {
                $client = New-Object System.Net.Sockets.TcpClient
                $client.Connect('127.0.0.1', $Port)
                break
            } catch {
                $client = $null
                Start-Sleep -Milliseconds 300
            }
        }
        if (-not $client) { throw "Renode monitor did not open port $Port" }

        $stream = $client.GetStream()
        $enc = [System.Text.Encoding]::ASCII
        Start-Sleep -Milliseconds 800

        foreach ($cmd in $Commands) {
            $bytes = $enc.GetBytes("$cmd`n")
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()

            # Give the slow commands (C# compile, ELF load, simulated time) room.
            $wait = 1200
            if ($cmd -match '^(include|machine Load|sysbus LoadELF)') { $wait = 8000 }
            if ($cmd -match '^emulation RunFor') { $wait = 25000 }
            Start-Sleep -Milliseconds $wait

            $buf = New-Object byte[] 65536
            while ($stream.DataAvailable) {
                [void]$stream.Read($buf, 0, $buf.Length)
                Start-Sleep -Milliseconds 100
            }
        }
        $client.Close()
    } finally {
        try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
    }

    if (-not (Test-Path $LogPath)) { throw "Renode produced no log at $LogPath" }
    return Get-Content $LogPath
}

# ------------------------------------------------------------------- test ----

$elf = Join-Path $projectRoot 'build\firmware.elf'
if (-not (Test-Path $elf)) { throw "build\firmware.elf not found - run .\build.ps1 first." }

$buildDir = Join-Path $projectRoot 'build'
$toForwardSlashes = { param($p) $p -replace '\\', '/' }

$renodeDir = & $toForwardSlashes (Join-Path $projectRoot 'renode')
$elfFwd = & $toForwardSlashes $elf

$openLog = Join-Path $buildDir 'test-open-loop.log'
$closedLog = Join-Path $buildDir 'test-closed-loop.log'
foreach ($stale in @($openLog, $closedLog)) {
    if (Test-Path $stale) { Remove-Item -LiteralPath $stale -Force }
}

# Every scenario starts from the same freshly built machine.
function Get-BootCommands {
    param([string]$LogPath)
    return @(
        "logFile @$(& $toForwardSlashes $LogPath) true",
        'mach create "attitude"',
        "include @$renodeDir/gyro1d.cs",
        "machine LoadPlatformDescription @$renodeDir/attitude.repl",
        "sysbus LoadELF @$elfFwd",
        'showAnalyzer sysbus.usart2 Antmicro.Renode.Analyzers.LoggingUartAnalyzer'
    )
}

Write-Host 'Scenario 1/2: open loop, disturbance held by hand...'
$openLogLines = Invoke-RenodeScenario -LogPath $openLog -Commands (
    (Get-BootCommands -LogPath $openLog) + @(
        'emulation RunFor "0.3"',
        'sysbus.i2c1.gyro AngularRateZ 30',
        'emulation RunFor "0.5"'
    ))

Write-Host 'Scenario 2/2: closed loop, plant model answers the PWM...'
$closedLogLines = Invoke-RenodeScenario -LogPath $closedLog -Commands (
    (Get-BootCommands -LogPath $closedLog) + @(
        'sysbus.i2c1.gyro PlantEnabled true',
        'emulation RunFor "0.3"',
        'sysbus.i2c1.gyro AngularRateZ 30',
        'emulation RunFor "4"'
    ))

$openSamples = Get-Telemetry -LogLines $openLogLines
$closedSamples = Get-Telemetry -LogLines $closedLogLines

Write-Host ''
Write-Host 'bring-up'
Assert-That 'gyro answers WHO_AM_I = 0xD4 over I2C' `
    ([bool]($openLogLines -match 'WHO_AM_I=0xD4 ok'))
Assert-That 'PWM channel armed at neutral (CCR1 = 100)' `
    ([bool]($openLogLines -match 'CCR1=100'))
Assert-That 'the control loop produced telemetry' `
    ($openSamples.Count -gt 5) "got $($openSamples.Count) samples"

# The disturbance is injected at t = 0.3 s and held to the end of the run.
$open = $openSamples | Where-Object { $_.T -ge 0.35 }

Write-Host ''
Write-Host 'open loop: disturbance held at +30 deg/s'
$rateErr = ($open | ForEach-Object { [math]::Abs($_.Rate - 30.0) } | Measure-Object -Maximum).Maximum
Assert-That 'measured rate matches the injected +30.00 deg/s' `
    ($open.Count -gt 0 -and $rateErr -lt 0.05) "max error $rateErr dps"
Assert-That 'the controller commands negative torque against the rotation' `
    ($open.Count -gt 0 -and ($open | Where-Object { $_.Duty -ge 0 }).Count -eq 0)
Assert-That 'CCR1 tracks the duty below neutral' `
    ($open.Count -gt 0 -and ($open | Where-Object { $_.Ccr -ge 100 }).Count -eq 0)

# By t = 3.5 s the kick at t = 0.3 s must be fully rejected.
$tail = $closedSamples | Where-Object { $_.T -ge 3.5 }
$peakRate = ($closedSamples | ForEach-Object { $_.Rate } | Measure-Object -Maximum).Maximum
$maxTailRate = ($tail | ForEach-Object { [math]::Abs($_.Rate) } | Measure-Object -Maximum).Maximum
$maxTailAngle = ($tail | ForEach-Object { [math]::Abs($_.Angle) } | Measure-Object -Maximum).Maximum
$maxTailDuty = ($tail | ForEach-Object { [math]::Abs($_.Duty) } | Measure-Object -Maximum).Maximum

Write-Host ''
Write-Host 'closed loop: the plant answers the PWM, the disturbance must decay'
Assert-That 'the kick was actually felt (peak rate > 20 deg/s)' `
    ($closedSamples.Count -gt 0 -and $peakRate -gt 20.0) "peak $peakRate dps"
Assert-That 'the loop ran past t = 3.5 s' `
    ($tail.Count -gt 0) "got $($tail.Count) tail samples"
Assert-That 'body rate decayed back to zero (|rate| < 1 deg/s)' `
    ($tail.Count -gt 0 -and $maxTailRate -lt 1.0) "max |rate| $maxTailRate dps"
Assert-That 'attitude recovered to the setpoint (|angle| < 1 deg)' `
    ($tail.Count -gt 0 -and $maxTailAngle -lt 1.0) "max |angle| $maxTailAngle deg"
Assert-That 'torque command returned to neutral (|duty| < 5 %)' `
    ($tail.Count -gt 0 -and $maxTailDuty -lt 5.0) "max |duty| $maxTailDuty %"

Write-Host ''
if ($script:failures -gt 0) {
    Write-Host "$($script:failures) assertion(s) failed." -ForegroundColor Red
    Write-Host "Logs: $openLog / $closedLog" -ForegroundColor Red
    exit 1
}

Write-Host 'All checks passed.' -ForegroundColor Green
exit 0
