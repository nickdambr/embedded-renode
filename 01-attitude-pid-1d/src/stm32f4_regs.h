/*
 * Minimal hand-written STM32F405 register map.
 *
 * Only the registers this project actually touches are declared. Offsets are
 * taken from RM0090 and cross-checked against the Renode peripheral models
 * (STM32_UART, STM32F4_I2C, STM32_Timer) that emulate them.
 */
#ifndef STM32F4_REGS_H
#define STM32F4_REGS_H

#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(addr))
#define REG32_PTR(addr) ((volatile uint32_t *)(addr))

/* ---------------------------------------------------------------- RCC ---- */
#define RCC_BASE 0x40023800u
#define RCC_AHB1ENR REG32(RCC_BASE + 0x30u)
#define RCC_APB1ENR REG32(RCC_BASE + 0x40u)

#define RCC_AHB1ENR_GPIOAEN (1u << 0)
#define RCC_AHB1ENR_GPIOBEN (1u << 1)
#define RCC_APB1ENR_TIM4EN (1u << 2)
#define RCC_APB1ENR_USART2EN (1u << 17)
#define RCC_APB1ENR_I2C1EN (1u << 21)

/* ------------------------------------------------------------- USART2 ---- */
#define USART2_BASE 0x40004400u
#define USART2_SR REG32(USART2_BASE + 0x00u)
#define USART2_DR REG32(USART2_BASE + 0x04u)
#define USART2_BRR REG32(USART2_BASE + 0x08u)
#define USART2_CR1 REG32(USART2_BASE + 0x0Cu)

#define USART_SR_TXE (1u << 7)
#define USART_CR1_TE (1u << 3)
#define USART_CR1_UE (1u << 13)

/* --------------------------------------------------------------- I2C1 ---- */
#define I2C1_BASE 0x40005400u
#define I2C1_CR1 REG32(I2C1_BASE + 0x00u)
#define I2C1_CR2 REG32(I2C1_BASE + 0x04u)
#define I2C1_DR REG32(I2C1_BASE + 0x10u)
#define I2C1_SR1 REG32(I2C1_BASE + 0x14u)
#define I2C1_SR2 REG32(I2C1_BASE + 0x18u)
#define I2C1_CCR REG32(I2C1_BASE + 0x1Cu)
#define I2C1_TRISE REG32(I2C1_BASE + 0x20u)

#define I2C1_SR1_PTR REG32_PTR(I2C1_BASE + 0x14u)

#define I2C_CR1_PE (1u << 0)
#define I2C_CR1_START (1u << 8)
#define I2C_CR1_STOP (1u << 9)
#define I2C_CR1_ACK (1u << 10)

#define I2C_SR1_SB (1u << 0)
#define I2C_SR1_ADDR (1u << 1)
#define I2C_SR1_BTF (1u << 2)
#define I2C_SR1_RXNE (1u << 6)
#define I2C_SR1_TXE (1u << 7)
#define I2C_SR1_AF (1u << 10)

/* --------------------------------------------------------------- TIM4 ---- */
#define TIM4_BASE 0x40000800u
#define TIM4_CR1 REG32(TIM4_BASE + 0x00u)
#define TIM4_EGR REG32(TIM4_BASE + 0x14u)
#define TIM4_CCMR1 REG32(TIM4_BASE + 0x18u)
#define TIM4_CCER REG32(TIM4_BASE + 0x20u)
#define TIM4_PSC REG32(TIM4_BASE + 0x28u)
#define TIM4_ARR REG32(TIM4_BASE + 0x2Cu)
#define TIM4_CCR1 REG32(TIM4_BASE + 0x34u)

#define TIM_CR1_CEN (1u << 0)
#define TIM_EGR_UG (1u << 0)
#define TIM_CCMR1_OC1PE (1u << 3)
#define TIM_CCMR1_OC1M_PWM1 (0x6u << 4)
#define TIM_CCER_CC1E (1u << 0)

/* ------------------------------------------------------------ SysTick ---- */
#define SYSTICK_CTRL REG32(0xE000E010u)
#define SYSTICK_LOAD REG32(0xE000E014u)
#define SYSTICK_VAL REG32(0xE000E018u)

#define SYSTICK_CTRL_ENABLE (1u << 0)
#define SYSTICK_CTRL_TICKINT (1u << 1)
#define SYSTICK_CTRL_CLKSOURCE (1u << 2)

/*
 * SysTick reference clock. This is NOT the 168 MHz of a real STM32F405: the
 * Renode platform (platforms/cpus/stm32f4.repl) declares the NVIC with
 * systickFrequency: 72000000, and the emulator is the hardware we run on.
 */
#define CPU_HZ 72000000u

#endif /* STM32F4_REGS_H */
