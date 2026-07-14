#include "pwm.h"

#include "stm32f4_regs.h"

/*
 * Renode's STM32_Timer disables the capture/compare channel when CCR is written
 * as 0, so the command is clamped one count short of the rail. The lost 1% of
 * negative authority is irrelevant to the control problem and keeps the
 * actuator model live at full deflection.
 */
#define PWM_CCR_MIN 1u
#define PWM_CCR_MAX ((uint32_t)PWM_PERIOD)

void pwm_init(void)
{
    RCC_APB1ENR |= RCC_APB1ENR_TIM4EN;

    TIM4_PSC = 0u;
    TIM4_ARR = (uint32_t)PWM_PERIOD;

    /*
     * PWM mode 1 on channel 1. On real silicon OC1PE would also be set, to make
     * CCR1 double-buffered against the update event; Renode's STM32_Timer has no
     * preload register and rejects that bit, and writing CCR1 there takes effect
     * immediately, so the loop reads back exactly what it wrote.
     */
    TIM4_CCMR1 = TIM_CCMR1_OC1M_PWM1;
    TIM4_CCER = TIM_CCER_CC1E;
    TIM4_CCR1 = (uint32_t)PWM_NEUTRAL;
    TIM4_EGR = TIM_EGR_UG; /* latch PSC/ARR immediately */
    TIM4_CR1 = TIM_CR1_CEN;
}

void pwm_set_duty(float duty_percent)
{
    int32_t ccr;

    if (duty_percent > 100.0f) {
        duty_percent = 100.0f;
    } else if (duty_percent < -100.0f) {
        duty_percent = -100.0f;
    }

    /* Round half away from zero so a +0.5% command is not truncated to neutral. */
    if (duty_percent >= 0.0f) {
        ccr = (int32_t)PWM_NEUTRAL + (int32_t)(duty_percent + 0.5f);
    } else {
        ccr = (int32_t)PWM_NEUTRAL + (int32_t)(duty_percent - 0.5f);
    }

    if (ccr < (int32_t)PWM_CCR_MIN) {
        ccr = (int32_t)PWM_CCR_MIN;
    } else if (ccr > (int32_t)PWM_CCR_MAX) {
        ccr = (int32_t)PWM_CCR_MAX;
    }

    TIM4_CCR1 = (uint32_t)ccr;
}

uint32_t pwm_get_ccr(void)
{
    return TIM4_CCR1;
}
