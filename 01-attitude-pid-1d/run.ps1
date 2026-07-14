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

. (Join-Path $projectRoot 'renode-monitor.ps1')

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
