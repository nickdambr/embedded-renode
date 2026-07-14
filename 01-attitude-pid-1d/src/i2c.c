#include "i2c.h"

#include "stm32f4_regs.h"

/*
 * Generous enough that a healthy transaction never trips it, small enough that
 * a broken one fails in well under a simulated second.
 */
#define I2C_TIMEOUT 200000u

static int i2c_wait_flag(volatile uint32_t *reg, uint32_t mask)
{
    uint32_t budget = I2C_TIMEOUT;

    while ((*reg & mask) == 0u) {
        if (--budget == 0u) {
            return -1;
        }
    }
    return 0;
}

static void i2c_clear_addr(void)
{
    /* ADDR is cleared by reading SR1 followed by SR2. */
    volatile uint32_t scratch = I2C1_SR1;
    scratch = I2C1_SR2;
    (void)scratch;
}

void i2c_init(void)
{
    RCC_AHB1ENR |= RCC_AHB1ENR_GPIOBEN;
    RCC_APB1ENR |= RCC_APB1ENR_I2C1EN;

    I2C1_CR2 = 42u;   /* APB1 clock, MHz  */
    I2C1_CCR = 210u;  /* 100 kHz standard mode */
    I2C1_TRISE = 43u;
    I2C1_CR1 = I2C_CR1_PE | I2C_CR1_ACK;
}

int i2c_read_reg(uint8_t slave_addr, uint8_t reg, uint8_t *out)
{
    /* Phase 1: address the slave for writing and hand it the register pointer. */
    I2C1_CR1 |= I2C_CR1_START;
    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_SB) != 0) {
        return -1;
    }

    I2C1_DR = (uint32_t)((uint32_t)slave_addr << 1);
    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_ADDR) != 0) {
        return -2;
    }
    i2c_clear_addr();

    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_TXE) != 0) {
        return -3;
    }
    I2C1_DR = (uint32_t)reg;
    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_BTF) != 0) {
        return -4;
    }

    /* Phase 2: repeated START turns the bus around and flushes the pointer. */
    I2C1_CR1 |= I2C_CR1_START;
    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_SB) != 0) {
        return -5;
    }

    I2C1_DR = (uint32_t)(((uint32_t)slave_addr << 1) | 1u);
    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_ADDR) != 0) {
        return -6;
    }
    i2c_clear_addr();

    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_RXNE) != 0) {
        return -7;
    }
    *out = (uint8_t)(I2C1_DR & 0xFFu);

    I2C1_CR1 |= I2C_CR1_STOP;
    return 0;
}

int i2c_write_reg(uint8_t slave_addr, uint8_t reg, uint8_t value)
{
    I2C1_CR1 |= I2C_CR1_START;
    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_SB) != 0) {
        return -1;
    }

    I2C1_DR = (uint32_t)((uint32_t)slave_addr << 1);
    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_ADDR) != 0) {
        return -2;
    }
    i2c_clear_addr();

    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_TXE) != 0) {
        return -3;
    }
    I2C1_DR = (uint32_t)reg;
    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_BTF) != 0) {
        return -4;
    }

    I2C1_DR = (uint32_t)value;
    if (i2c_wait_flag(I2C1_SR1_PTR, I2C_SR1_BTF) != 0) {
        return -5;
    }

    /* The payload reaches the slave when STOP is generated. */
    I2C1_CR1 |= I2C_CR1_STOP;
    return 0;
}
