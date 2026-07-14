/*
 * Single-axis MEMS gyroscope on I2C1, L3GD20-compatible register map.
 * Emulated by the Gyro1D model in renode/gyro1d.cs.
 */
#ifndef GYRO_H
#define GYRO_H

#include <stdint.h>

#define GYRO_I2C_ADDR 0x6Bu
#define GYRO_WHO_AM_I_VALUE 0xD4u

/* Reads WHO_AM_I and powers the sensor up. Returns 0 on success. */
int gyro_init(void);

/* Reads WHO_AM_I into *out. Returns 0 on success. */
int gyro_who_am_i(uint8_t *out);

/* Angular rate about the controlled axis, deg/s. Returns 0 on success. */
int gyro_read_rate_z(float *rate_dps);

#endif /* GYRO_H */
