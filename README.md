# Embedded

Bare-metal firmware for ARM Cortex-M targets, developed and tested entirely
against emulated hardware in [Renode](https://renode.io). Each project is
self-contained: firmware, emulated platform, build script, and a headless test
that asserts on what the firmware actually does.

No vendor HAL, no CubeMX, no libc — hand-written register maps, `-nostdlib`,
warnings as errors.

| Project | What it does |
| --- | --- |
| [01-attitude-pid-1d](01-attitude-pid-1d/) | Single-axis attitude regulation: an I2C gyroscope, a discrete PID, and a PWM torque command. Includes a rigid-body plant model in the emulator, so the loop closes and an injected disturbance decays. |

Each project builds and runs on its own:

```powershell
cd 01-attitude-pid-1d
.\build.ps1
.\run.ps1
.\test.ps1
```

Prerequisites are the Arm bare-metal toolchain and Renode:

```powershell
winget install --id Arm.GnuArmEmbeddedToolchain -e
winget install --id Renode.Renode -e
```
