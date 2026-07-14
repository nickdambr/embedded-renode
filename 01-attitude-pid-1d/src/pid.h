/* Discrete PID with integral anti-windup and derivative on measurement. */
#ifndef PID_H
#define PID_H

typedef struct {
    float kp;
    float ki;
    float kd;
    float integral_limit; /* clamp on the integral term, output units */
    float output_limit;   /* clamp on the command, output units        */
    float integral;       /* state                                     */
} pid_t;

void pid_reset(pid_t *pid);

/*
 * error      : setpoint - measurement
 * derivative : d(measurement)/dt, NOT d(error)/dt. Feeding the measured rate
 *              directly avoids the derivative kick on a setpoint step and is
 *              exactly what the gyro already gives us.
 * dt         : loop period, seconds
 */
float pid_update(pid_t *pid, float error, float derivative, float dt);

#endif /* PID_H */
