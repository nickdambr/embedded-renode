#include "uart.h"

#include "stm32f4_regs.h"

void uart_init(void)
{
    RCC_APB1ENR |= RCC_APB1ENR_USART2EN;

    /* 115200 baud at the model's default 8 MHz clock (mantissa 4, fraction 5). */
    USART2_BRR = 0x45u;
    USART2_CR1 = USART_CR1_UE | USART_CR1_TE;
}

void uart_putc(char c)
{
    while ((USART2_SR & USART_SR_TXE) == 0u) {
    }
    USART2_DR = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *s)
{
    while (*s != '\0') {
        uart_putc(*s++);
    }
}

static void uart_print_u32(uint32_t value)
{
    char digits[10];
    uint32_t n = 0u;

    if (value == 0u) {
        uart_putc('0');
        return;
    }

    while (value > 0u) {
        digits[n++] = (char)('0' + (value % 10u));
        value /= 10u;
    }

    while (n > 0u) {
        uart_putc(digits[--n]);
    }
}

void uart_print_i32(int32_t value)
{
    uint32_t magnitude;

    if (value < 0) {
        uart_putc('-');
        magnitude = (uint32_t)(-(value + 1)) + 1u; /* safe for INT32_MIN */
    } else {
        magnitude = (uint32_t)value;
    }

    uart_print_u32(magnitude);
}

void uart_print_fixed(int32_t scaled, uint32_t decimals)
{
    uint32_t divisor = 1u;
    uint32_t magnitude;
    uint32_t fraction;

    for (uint32_t i = 0u; i < decimals; ++i) {
        divisor *= 10u;
    }

    if (scaled < 0) {
        uart_putc('-');
        magnitude = (uint32_t)(-(scaled + 1)) + 1u;
    } else {
        uart_putc('+');
        magnitude = (uint32_t)scaled;
    }

    uart_print_u32(magnitude / divisor);

    if (decimals == 0u) {
        return;
    }

    uart_putc('.');
    fraction = magnitude % divisor;

    /* Leading zeros of the fractional part. */
    for (uint32_t d = divisor / 10u; d > 1u; d /= 10u) {
        if (fraction >= d) {
            break;
        }
        uart_putc('0');
    }

    uart_print_u32(fraction);
}
