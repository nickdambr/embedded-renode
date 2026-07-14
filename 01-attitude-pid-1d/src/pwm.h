/*
 * TIM4 channel 1 as a bidirectional actuator command (thruster pair or
 * reaction wheel): CCR1 = PWM_NEUTRAL is zero torque, and the duty swings
 * symmetrically around it.
 */
#ifndef PWM_H
#define PWM_H

#include <stdint.h>

#define PWM_PERIOD 200 /* ARR: counts per PWM period      */
#define PWM_NEUTRAL 100 /* CCR1 for zero commanded torque  */

void pwm_init(void);

/* Commanded torque in percent, clamped to [-100, +100]. */
void pwm_set_duty(float duty_percent);

/* Last value written to CCR1, i.e. what the plant model reads back. */
uint32_t pwm_get_ccr(void);

#endif /* PWM_H */
