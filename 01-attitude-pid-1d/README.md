# 01 — Single-axis attitude regulation (PID → PWM)

Bare-metal C firmware for an ARM Cortex-M4 that holds one rotational axis at a
commanded attitude — the roll channel of a spinning stage, or a satellite
pointing one face at a target. A MEMS gyroscope on I2C measures the body rate,
the firmware dead-reckons the attitude from it, and a discrete PID drives a PWM
channel as a bidirectional torque command (a thruster pair, or a reaction wheel).

Everything runs on emulated hardware in [Renode](https://renode.io): no board
required. The emulation also carries a rigid-body model of the vehicle, so the
loop can actually be closed — inject a disturbance and watch it decay.

```
   ┌──────────┐   I2C1    ┌─────────────┐
   │  Gyro1D  │──────────►│  STM32F405  │
   │  gyro    │  rate     │  firmware   │
   └────▲─────┘           └──────┬──────┘
        │                        │ TIM4 CH1 (CCR1)
        │  angular rate          │ torque command
        │                        ▼
        └────────── rigid-body plant ◄── PWM duty
                    ω̇ = K·duty − c·ω
```

## Control design

The gyro is the only sensor on the axis, so the attitude is dead-reckoned:

```
angle ← angle + rate · dt                     dt = 10 ms  (100 Hz, off SysTick)
error  = setpoint − angle                     setpoint = 0°
u      = Kp·error + ∫Ki·error·dt − Kd·rate     clamped to ±100 %
```

Two details that matter, both in [src/pid.c](src/pid.c):

- **Derivative on measurement.** The D term uses the measured body rate, not the
  derivative of the error. The gyro hands us `d(angle)/dt` directly — no noisy
  numerical differentiation — and a setpoint step cannot produce a derivative
  kick.
- **Integral clamping.** The integrator is bounded independently of the output,
  so a saturated actuator cannot wind it up into a long overshoot on recovery.

The command maps to the timer as `CCR1 = 100 + duty`, with `ARR = 200`:
`CCR1 = 100` is zero torque, `0` and `200` are the two rails.

## Layout

| Path | What it is |
| --- | --- |
| [src/main.c](src/main.c) | Bring-up self-test, then the 100 Hz control loop |
| [src/pid.c](src/pid.c) | The discrete PID (anti-windup, derivative on measurement) |
| [src/gyro.c](src/gyro.c) | L3GD20-compatible gyro driver, raw counts → deg/s |
| [src/i2c.c](src/i2c.c) | Polled I2C1 master, every wait bounded by a timeout |
| [src/pwm.c](src/pwm.c) | TIM4 CH1 as a bidirectional torque command |
| [src/uart.c](src/uart.c) | Polled USART2 and integer-only formatting (no `printf`) |
| [src/startup.c](src/startup.c) | Vector table and C runtime bring-up, no assembly |
| [renode/gyro1d.cs](renode/gyro1d.cs) | The emulated gyroscope **and** the vehicle physics |
| [renode/attitude.repl](renode/attitude.repl) | STM32F405 platform + the gyro on I2C1 |
| [test.ps1](test.ps1) | Headless regression test, asserts on the firmware's telemetry |

No vendor HAL, no CubeMX, no libc: the register map in
[src/stm32f4_regs.h](src/stm32f4_regs.h) is hand-written, and the firmware links
with `-nostdlib`. It is about 3.7 KB of flash.

## Build and run

Prerequisites — the Arm bare-metal toolchain and Renode:

```powershell
winget install --id Arm.GnuArmEmbeddedToolchain -e
winget install --id Renode.Renode -e
```

Both scripts find their tools on `PATH`, in the usual install locations, or via
`$env:GCC_ARM_BIN` / `$env:RENODE_PATH`.

```powershell
.\build.ps1      # -> build\firmware.elf
.\run.ps1        # -> Renode, with the USART2 window open
.\test.ps1       # -> headless: replays both scenarios and checks the results
```

## The demo

In the Renode monitor, `start` the machine. Telemetry arrives at 10 Hz:

```
=== 1D attitude control : PID -> PWM ===
usart2 : ok
gyro   : WHO_AM_I=0xD4 ok
tim4   : PWM ch1 armed, CCR1=100 (neutral)
loop   : 100 Hz, setpoint 0 deg
```

### Open loop — you are the physics

Rotate the vehicle by hand and watch the controller fight back:

```
(attitude) sysbus.i2c1.gyro AngularRateZ 30      # +30 deg/s disturbance
```

```
t=+0.30 s  rate=+30.00 dps  angle=+0.30 deg  duty=-37.2 %  ccr=63
t=+0.40 s  rate=+30.00 dps  angle=+3.30 deg  duty=-49.3 %  ccr=51
t=+0.50 s  rate=+30.00 dps  angle=+6.30 deg  duty=-61.7 %  ccr=38
t=+0.70 s  rate=+30.00 dps  angle=+12.30 deg  duty=-87.2 %  ccr=13
```

The measured rate is exactly the injected one, the attitude ramps at 3° per
telemetry line, and the command runs harder and harder negative as the error
grows. Nothing stops the rotation, because in this mode nothing in the
simulation responds to the PWM — setting the rate back to `0` freezes the
attitude wherever it got to. The register the controller actually writes can be
read straight off the bus:

```
(attitude) sysbus ReadDoubleWord 0x40000834      # TIM4_CCR1
```

### Closed loop — the vehicle answers

Enable the plant model and the loop becomes real: the PWM duty produces torque,
the torque changes the body rate, and the gyro reads that rate back.

```
(attitude) sysbus.i2c1.gyro PlantEnabled true
(attitude) sysbus.i2c1.gyro AngularRateZ 30      # kick it
```

```
t=+0.20 s  rate=+29.85 dps  angle=+0.30 deg  duty=-37.0 %  ccr=63
t=+0.40 s  rate= +5.03 dps  angle=+3.40 deg  duty=-20.0 %  ccr=80
t=+0.60 s  rate= -5.44 dps  angle=+3.11 deg  duty= -6.8 %  ccr=93
t=+1.00 s  rate= -5.10 dps  angle=+0.49 deg  duty= +2.6 %  ccr=103
t=+1.50 s  rate= -0.21 dps  angle=-0.59 deg  duty= +1.2 %  ccr=101
t=+1.80 s  rate= +0.39 dps  angle=-0.51 deg  duty= +0.3 %  ccr=100
```

A textbook step response: the rate is arrested in ~0.4 s, the attitude peaks at
+3.5°, comes back through zero with a small undershoot, and the command settles
at neutral. The plant gains are tunable from the monitor
(`TorqueGain`, `Damping`), as are the PID gains at the top of
[src/main.c](src/main.c).

## The emulated gyroscope

[renode/gyro1d.cs](renode/gyro1d.cs) is a ~200-line C# peripheral that Renode
compiles at runtime. It presents an L3GD20-compatible register map
(`WHO_AM_I = 0xD4` at `0x0F`, control registers at `0x20`/`0x23`, `OUT_Z` at
`0x2C`/`0x2D`) at I2C address `0x6B`, and its `AngularRateZ` property is what the
monitor pokes to inject a disturbance. When `PlantEnabled` is set, it also
integrates the rigid-body model, reading the duty cycle back from `TIM4_CCR1`
over the system bus.

It is a custom model rather than one of Renode's stock ST sensors for a concrete
reason. Renode's `STM32F4_I2C` controller never calls `FinishTransmission()` on
the attached slave, and `I2CPeripheralBase.Read()` ignores the requested byte
count and always returns one byte. Together those leave the stock sensors
(`LSM330_Gyroscope`, `LSM9DS1_IMU`) with their register pointer stuck after the
first read: every later transaction is parsed as a register *write*. `Gyro1D`
keeps no parser state across transactions, so an ordinary polled I2C driver
works against it.

## Where the emulator differs from silicon

Per the repo convention, the firmware targets the emulator's actual behaviour
and the deviations are written down:

- **SysTick runs at 72 MHz**, not the 168 MHz of a real STM32F405 — that is what
  `platforms/cpus/stm32f4.repl` declares (`systickFrequency: 72000000`), and
  `CPU_HZ` in [src/stm32f4_regs.h](src/stm32f4_regs.h) matches it.
- **One register per I2C transaction.** The controller model pulls a single byte
  from the slave per addressing phase, so `gyro_read_rate_z()` issues two
  transactions (low byte, then high byte) instead of one burst read.
- **`CCR1 = 0` disables the compare channel** in Renode's `STM32_Timer`, so the
  duty is clamped one count short of the negative rail.
- **No `OC1PE`.** The model has no preload register; `CCR1` writes take effect
  immediately. On real silicon that bit would be set.
