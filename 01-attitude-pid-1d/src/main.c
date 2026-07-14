/*
 * 1-axis attitude regulation: gyro -> angle estimate -> PID -> PWM duty.
 *
 * The vehicle (a spinning stage, or a satellite pointing one axis) is held at
 * zero attitude. A gyroscope on I2C1 measures the body rate, the firmware
 * integrates it into an angle, and a PID drives TIM4 CH1 as a bidirectional
 * torque command: CCR1 = 100 is zero torque, 0 and 200 are the rails.
 */
#include "gyro.h"
#include "i2c.h"
#include "pid.h"
#include "pwm.h"
#include "stm32f4_regs.h"
#include "uart.h"

#define CONTROL_HZ 100u
#define CONTROL_DT (1.0f / (float)CONTROL_HZ)
#define TELEMETRY_DIVIDER 10u /* one telemetry line every 10 control periods */

#define SETPOINT_DEG 0.0f

/*
 * Gains for a plant with ~400 deg/s^2 of authority at full duty. Tuned in the
 * order Kp, then Kd for damping, then Ki to remove the steady-state offset.
 */
#define PID_KP 4.0f
#define PID_KI 0.8f
#define PID_KD 1.2f
#define PID_INTEGRAL_LIMIT 40.0f
#define PID_OUTPUT_LIMIT 100.0f

static volatile uint32_t g_ticks;

void SysTick_Handler(void)
{
    ++g_ticks;
}

static void systick_init(void)
{
    SYSTICK_LOAD = (CPU_HZ / CONTROL_HZ) - 1u;
    SYSTICK_VAL = 0u;
    SYSTICK_CTRL = SYSTICK_CTRL_CLKSOURCE | SYSTICK_CTRL_TICKINT | SYSTICK_CTRL_ENABLE;
}

static void print_hex8(uint8_t value)
{
    static const char digits[] = "0123456789ABCDEF";

    uart_puts("0x");
    uart_putc(digits[(value >> 4) & 0x0Fu]);
    uart_putc(digits[value & 0x0Fu]);
}

/*
 * Bring-up self-test. Each subsystem is proven on its own before the loop is
 * closed, so a failure points at one peripheral instead of the whole chain.
 */
static int self_test(void)
{
    uint8_t id = 0u;
    int rc;

    uart_puts("\r\n=== 1D attitude control : PID -> PWM ===\r\n");
    uart_puts("usart2 : ok\r\n");

    rc = gyro_who_am_i(&id);
    if (rc != 0) {
        uart_puts("gyro   : I2C transaction failed, rc=");
        uart_print_i32(rc);
        uart_puts("\r\n");
        return rc;
    }

    uart_puts("gyro   : WHO_AM_I=");
    print_hex8(id);
    if (id != (uint8_t)GYRO_WHO_AM_I_VALUE) {
        uart_puts(" UNEXPECTED\r\n");
        return -20;
    }
    uart_puts(" ok\r\n");

    rc = gyro_init();
    if (rc != 0) {
        uart_puts("gyro   : init failed, rc=");
        uart_print_i32(rc);
        uart_puts("\r\n");
        return rc;
    }

    pwm_init();
    uart_puts("tim4   : PWM ch1 armed, CCR1=");
    uart_print_i32((int32_t)pwm_get_ccr());
    uart_puts(" (neutral)\r\n");

    uart_puts("loop   : ");
    uart_print_i32((int32_t)CONTROL_HZ);
    uart_puts(" Hz, setpoint 0 deg\r\n\r\n");

    return 0;
}

static void print_telemetry(uint32_t tick, float rate, float angle, float duty)
{
    /* Integer-only formatting: no printf, no soft-float division in the path. */
    uart_puts("t=");
    uart_print_fixed((int32_t)tick, 2u); /* tick * 10 ms -> seconds, 2 decimals */
    uart_puts(" s  rate=");
    uart_print_fixed((int32_t)(rate * 100.0f), 2u);
    uart_puts(" dps  angle=");
    uart_print_fixed((int32_t)(angle * 100.0f), 2u);
    uart_puts(" deg  duty=");
    uart_print_fixed((int32_t)(duty * 10.0f), 1u);
    uart_puts(" %  ccr=");
    uart_print_i32((int32_t)pwm_get_ccr());
    uart_puts("\r\n");
}

int main(void)
{
    pid_t pid = {
        .kp = PID_KP,
        .ki = PID_KI,
        .kd = PID_KD,
        .integral_limit = PID_INTEGRAL_LIMIT,
        .output_limit = PID_OUTPUT_LIMIT,
        .integral = 0.0f,
    };

    float angle_deg = 0.0f;
    uint32_t processed = 0u;

    uart_init();
    i2c_init();

    if (self_test() != 0) {
        uart_puts("bring-up failed, halting\r\n");
        for (;;) {
        }
    }

    pid_reset(&pid);
    systick_init();

    for (;;) {
        float rate_dps = 0.0f;
        float error_deg;
        float duty;

        /* One pass per control period; SysTick is the only time reference. */
        while (g_ticks == processed) {
        }
        ++processed;

        if (gyro_read_rate_z(&rate_dps) != 0) {
            uart_puts("gyro   : read failed, holding last command\r\n");
            continue;
        }

        /* Dead-reckoned attitude: the gyro is the only sensor on this axis. */
        angle_deg += rate_dps * CONTROL_DT;

        error_deg = SETPOINT_DEG - angle_deg;
        duty = pid_update(&pid, error_deg, rate_dps, CONTROL_DT);
        pwm_set_duty(duty);

        if ((processed % TELEMETRY_DIVIDER) == 0u) {
            print_telemetry(processed, rate_dps, angle_deg, duty);
        }
    }
}
