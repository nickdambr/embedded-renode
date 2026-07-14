<#
    Launches Renode with the attitude-control machine and opens the USART2
    analyzer. Build first with .\build.ps1.

    Renode is located in this order:
      1. $env:RENODE_PATH  (full path to renode.exe)
      2. renode / Renode on PATH
      3. well-known install locations (MSI install, portable unzip)
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot

function Find-Renode {
    if ($env:RENODE_PATH) {
        if (Test-Path $env:RENODE_PATH) { return $env:RENODE_PATH }
        throw "RENODE_PATH is set to '$env:RENODE_PATH' but that file does not exist."
    }

    $onPath = Get-Command 'renode' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $candidates = @(
        "$env:ProgramFiles\Renode\bin\Renode.exe",
        "$env:ProgramFiles\Renode\Renode.exe",
        "$env:USERPROFILE\tools\renode\*\renode.exe"
    )

    foreach ($candidate in $candidates) {
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

$elf = Join-Path $projectRoot 'build\firmware.elf'
if (-not (Test-Path $elf)) {
    throw "build\firmware.elf not found - run .\build.ps1 first."
}

$renode = Find-Renode
$script = Join-Path $projectRoot 'renode\attitude.resc'

Write-Host "renode : $renode"
Write-Host "script : $script"
Write-Host ''

& $renode $script
