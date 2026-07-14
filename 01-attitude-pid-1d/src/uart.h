/* Polled USART2 transmitter and integer-only formatting helpers. */
#ifndef UART_H
#define UART_H

#include <stdint.h>

void uart_init(void);
void uart_putc(char c);
void uart_puts(const char *s);

/* Prints a signed integer. */
void uart_print_i32(int32_t value);

/*
 * Prints a fixed-point value with an explicit sign, e.g. uart_print_fixed(-1520, 2)
 * emits "-15.20". Avoids pulling in printf and any floating-point formatting.
 */
void uart_print_fixed(int32_t scaled, uint32_t decimals);

#endif /* UART_H */
