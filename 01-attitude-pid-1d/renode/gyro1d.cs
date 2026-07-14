//
// Gyro1D - single-axis MEMS gyroscope with an L3GD20-compatible register map,
// plus an optional rigid-body plant model of the vehicle it is bolted to.
//
// Why a custom model instead of a stock Renode sensor:
//   Renode's STM32F4_I2C controller never calls FinishTransmission() on the
//   attached slave, and I2CPeripheralBase.Read() ignores the requested count
//   and always returns a single byte. Together those two facts leave the stock
//   ST sensors (LSM330_Gyroscope, LSM9DS1_IMU) with their register pointer
//   stuck after the first read: every later transaction is interpreted as a
//   register *write* instead of a pointer update. This model keeps no
//   cross-transaction parser state, so a textbook polled I2C driver works.
//
// Plant model (enabled with PlantEnabled true):
//   The firmware drives TIM4 CH1 as a bidirectional thruster/reaction wheel:
//   CCR1 = 100 is zero torque, 0 and 200 are full negative/positive torque.
//   Every time the firmware samples the gyro we advance the rigid-body state
//   with the virtual time elapsed since the previous sample:
//
//       omega_dot = TorqueGain * duty - Damping * omega        [deg/s^2]
//
//   so a disturbance injected with "AngularRateZ 30" decays under closed-loop
//   control instead of persisting forever.
//
using System;
using Antmicro.Renode.Core;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.I2C;

namespace Antmicro.Renode.Peripherals.Sensors
{
    public class Gyro1D : II2CPeripheral
    {
        public Gyro1D(IMachine machine)
        {
            this.machine = machine;
            Reset();
        }

        public void Reset()
        {
            pointer = 0;
            ctrl1 = DefaultCtrl1;
            ctrl4 = 0;
            AngularRateZ = 0;
            PlantEnabled = false;
            TorqueGain = 400;
            Damping = 0.5m;
            lastSampleUs = 0;
            primed = false;
        }

        // Angular rate about the controlled axis, in deg/s.
        // Set it from the monitor to inject a disturbance:  gyro AngularRateZ 30
        public decimal AngularRateZ { get; set; }

        // When true, the gyro rate is produced by integrating the rigid-body
        // model driven by the PWM duty cycle, instead of being held at whatever
        // value was last written.
        public bool PlantEnabled { get; set; }

        // Angular acceleration at 100% duty, deg/s^2.
        public decimal TorqueGain { get; set; }

        // Viscous damping coefficient, 1/s.
        public decimal Damping { get; set; }

        public void Write(byte[] data)
        {
            if(data.Length == 0)
            {
                return;
            }

            // First byte of every transaction is the register pointer. The MSB is
            // the ST auto-increment flag; we mask it off and ignore it, because the
            // STM32F4_I2C controller pulls one byte per transaction anyway.
            pointer = (byte)(data[0] & 0x7F);

            for(var i = 1; i < data.Length; i++)
            {
                WriteRegister((byte)(pointer + i - 1), data[i]);
            }
        }

        public byte[] Read(int count = 1)
        {
            UpdatePlant();

            var length = count < 1 ? 1 : count;
            var result = new byte[length];
            for(var i = 0; i < length; i++)
            {
                result[i] = ReadRegister((byte)(pointer + i));
            }
            return result;
        }

        public void FinishTransmission()
        {
            // Deliberately stateless: the register pointer survives, exactly like
            // real silicon, and the next transaction rewrites it anyway.
        }

        private void WriteRegister(byte register, byte value)
        {
            switch(register)
            {
                case CtrlReg1:
                    ctrl1 = value;
                    break;
                case CtrlReg4:
                    ctrl4 = value;
                    break;
                default:
                    this.Log(LogLevel.Warning, "Write of 0x{0:X2} to unhandled/read-only register 0x{1:X2}", value, register);
                    break;
            }
        }

        private byte ReadRegister(byte register)
        {
            switch(register)
            {
                case WhoAmI:
                    return WhoAmIValue;
                case CtrlReg1:
                    return ctrl1;
                case CtrlReg4:
                    return ctrl4;
                case StatusReg:
                    return 0x08; // ZYXDA: new data available on all axes
                case OutZLow:
                    return (byte)(RawRate & 0xFF);
                case OutZHigh:
                    return (byte)((RawRate >> 8) & 0xFF);
                default:
                    this.Log(LogLevel.Warning, "Read from unhandled register 0x{0:X2}", register);
                    return 0;
            }
        }

        // Raw 16-bit two's-complement sample, using the full-scale currently
        // selected in CTRL_REG4. The firmware's conversion constant must be the
        // exact inverse of this one.
        private short RawRate
        {
            get
            {
                var counts = Math.Round(AngularRateZ / Sensitivity);
                if(counts > short.MaxValue)
                {
                    counts = short.MaxValue;
                }
                else if(counts < short.MinValue)
                {
                    counts = short.MinValue;
                }
                return (short)counts;
            }
        }

        // deg/s per LSB, from the FS field of CTRL_REG4 (L3GD20 values).
        private decimal Sensitivity
        {
            get
            {
                switch((ctrl4 >> 4) & 0x3)
                {
                    case 0:
                        return 0.00875m; // +/- 250 dps
                    case 1:
                        return 0.0175m;  // +/- 500 dps
                    default:
                        return 0.07m;    // +/- 2000 dps
                }
            }
        }

        private void UpdatePlant()
        {
            var nowUs = machine.ElapsedVirtualTime.TimeElapsed.TotalMicroseconds;

            if(!PlantEnabled)
            {
                // Keep the clock aligned so that enabling the plant later does not
                // integrate over the whole time the emulation has been running.
                lastSampleUs = nowUs;
                primed = true;
                return;
            }

            if(!primed)
            {
                lastSampleUs = nowUs;
                primed = true;
                return;
            }

            if(nowUs <= lastSampleUs)
            {
                return;
            }

            var dt = (nowUs - lastSampleUs) / 1000000.0;
            lastSampleUs = nowUs;

            // TIM4 CH1 duty: CCR1 == PwmNeutral means zero torque.
            var ccr1 = machine.SystemBus.ReadDoubleWord(Tim4Ccr1Address);
            var duty = ((double)ccr1 - PwmNeutral) / PwmNeutral;
            if(duty > 1.0)
            {
                duty = 1.0;
            }
            else if(duty < -1.0)
            {
                duty = -1.0;
            }

            var omega = (double)AngularRateZ;
            var omegaDot = (double)TorqueGain * duty - (double)Damping * omega;
            omega += omegaDot * dt;

            AngularRateZ = (decimal)omega;
        }

        private byte pointer;
        private byte ctrl1;
        private byte ctrl4;
        private double lastSampleUs;
        private bool primed;

        private readonly IMachine machine;

        private const byte WhoAmI = 0x0F;
        private const byte CtrlReg1 = 0x20;
        private const byte CtrlReg4 = 0x23;
        private const byte StatusReg = 0x27;
        private const byte OutZLow = 0x2C;
        private const byte OutZHigh = 0x2D;

        private const byte WhoAmIValue = 0xD4;
        private const byte DefaultCtrl1 = 0x07;

        private const ulong Tim4Ccr1Address = 0x40000834;
        private const double PwmNeutral = 100.0;
    }
}
