<#
    Builds firmware.elf with arm-none-eabi-gcc. No make, no cmake: a handful of
    translation units and one link step.

    The toolchain is located in this order:
      1. $env:GCC_ARM_BIN            (explicit override)
      2. arm-none-eabi-gcc on PATH
      3. well-known install locations (ARM installer, portable unzip)
#>
[CmdletBinding()]
param(
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot

function Find-ArmGcc {
    if ($env:GCC_ARM_BIN) {
        $candidate = Join-Path $env:GCC_ARM_BIN 'arm-none-eabi-gcc.exe'
        if (Test-Path $candidate) { return $candidate }
        throw "GCC_ARM_BIN is set to '$env:GCC_ARM_BIN' but arm-none-eabi-gcc.exe is not there."
    }

    $onPath = Get-Command 'arm-none-eabi-gcc' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $searchRoots = @(
        "$env:USERPROFILE\tools\armgcc\bin",
        "${env:ProgramFiles(x86)}\Arm GNU Toolchain arm-none-eabi\*\bin",
        "$env:ProgramFiles\Arm GNU Toolchain arm-none-eabi\*\bin",
        "${env:ProgramFiles(x86)}\GNU Arm Embedded Toolchain\*\bin"
    )

    foreach ($root in $searchRoots) {
        $hit = Get-ChildItem -Path $root -Filter 'arm-none-eabi-gcc.exe' -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }

    throw @"
arm-none-eabi-gcc not found.

Install the Arm GNU toolchain, then re-run:
    winget install --id Arm.GnuArmEmbeddedToolchain -e
or unpack the portable archive and point GCC_ARM_BIN at its bin/ folder.
"@
}

$gcc = Find-ArmGcc
$gccDir = Split-Path $gcc -Parent
$size = Join-Path $gccDir 'arm-none-eabi-size.exe'
$objcopy = Join-Path $gccDir 'arm-none-eabi-objcopy.exe'

$buildDir = Join-Path $projectRoot 'build'
if ($Clean -and (Test-Path $buildDir)) {
    Remove-Item $buildDir -Recurse -Force
}
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
}

$sources = Get-ChildItem -Path (Join-Path $projectRoot 'src') -Filter '*.c' | Sort-Object Name
$linkerScript = Join-Path $projectRoot 'ld\stm32f405.ld'
$elf = Join-Path $buildDir 'firmware.elf'
$map = Join-Path $buildDir 'firmware.map'

$cflags = @(
    '-mcpu=cortex-m4', '-mthumb', '-mfloat-abi=soft',
    '-std=c11', '-Og', '-g3',
    '-ffreestanding', '-ffunction-sections', '-fdata-sections',
    '-Wall', '-Wextra', '-Werror', '-Wshadow', '-Wconversion'
)

$ldflags = @(
    '-nostdlib', '-Wl,--gc-sections',
    "-T$linkerScript", "-Wl,-Map=$map"
)

Write-Host "toolchain : $gcc"
Write-Host "sources   : $($sources.Name -join ', ')"

& $gcc @cflags @ldflags -o $elf @($sources.FullName) -lgcc
if ($LASTEXITCODE -ne 0) {
    throw "compilation failed (exit $LASTEXITCODE)"
}

if (Test-Path $objcopy) {
    & $objcopy -O binary $elf (Join-Path $buildDir 'firmware.bin')
}

Write-Host ''
& $size $elf
Write-Host ''
Write-Host "built     : $elf"
