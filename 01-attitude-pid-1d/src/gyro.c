#include "gyro.h"

#include "i2c.h"

#define GYRO_REG_WHO_AM_I 0x0Fu
#define GYRO_REG_CTRL1 0x20u
#define GYRO_REG_CTRL4 0x23u
#define GYRO_REG_OUT_Z_L 0x2Cu
#define GYRO_REG_OUT_Z_H 0x2Du

/* CTRL_REG1: normal mode, all three axes enabled. */
#define GYRO_CTRL1_POWER_ON 0x0Fu
/* CTRL_REG4: full scale +/- 250 dps. */
#define GYRO_CTRL4_FS_250 0x00u

/*
 * Sensitivity at +/- 250 dps full scale, deg/s per LSB. This is the exact
 * inverse of the conversion the Gyro1D model applies when it turns
 * AngularRateZ into the raw register pair.
 */
#define GYRO_SENSITIVITY_DPS_PER_LSB 0.00875f

int gyro_who_am_i(uint8_t *out)
{
    return i2c_read_reg((uint8_t)GYRO_I2C_ADDR, GYRO_REG_WHO_AM_I, out);
}

int gyro_init(void)
{
    uint8_t id = 0u;
    int rc;

    rc = gyro_who_am_i(&id);
    if (rc != 0) {
        return rc;
    }
    if (id != (uint8_t)GYRO_WHO_AM_I_VALUE) {
        return -20;
    }

    rc = i2c_write_reg((uint8_t)GYRO_I2C_ADDR, GYRO_REG_CTRL1, GYRO_CTRL1_POWER_ON);
    if (rc != 0) {
        return rc;
    }

    return i2c_write_reg((uint8_t)GYRO_I2C_ADDR, GYRO_REG_CTRL4, GYRO_CTRL4_FS_250);
}

int gyro_read_rate_z(float *rate_dps)
{
    uint8_t low = 0u;
    uint8_t high = 0u;
    int16_t raw;
    int rc;

    /*
     * One register per transaction: Renode's STM32F4_I2C controller pulls a
     * single byte from the slave per addressing phase, so a burst read would
     * return the same byte twice.
     */
    rc = i2c_read_reg((uint8_t)GYRO_I2C_ADDR, GYRO_REG_OUT_Z_L, &low);
    if (rc != 0) {
        return rc;
    }

    rc = i2c_read_reg((uint8_t)GYRO_I2C_ADDR, GYRO_REG_OUT_Z_H, &high);
    if (rc != 0) {
        return rc;
    }

    raw = (int16_t)(((uint16_t)high << 8) | (uint16_t)low);
    *rate_dps = (float)raw * GYRO_SENSITIVITY_DPS_PER_LSB;
    return 0;
}
