/*
 * Polled I2C1 master. Every wait is bounded: a peripheral that never raises a
 * flag returns an error code instead of hanging the firmware.
 */
#ifndef I2C_H
#define I2C_H

#include <stdint.h>

void i2c_init(void);

/* Both return 0 on success, or a negative code identifying the failed step. */
int i2c_read_reg(uint8_t slave_addr, uint8_t reg, uint8_t *out);
int i2c_write_reg(uint8_t slave_addr, uint8_t reg, uint8_t value);

#endif /* I2C_H */
