#include "pid.h"

static float clamp(float value, float limit)
{
    if (value > limit) {
        return limit;
    }
    if (value < -limit) {
        return -limit;
    }
    return value;
}

void pid_reset(pid_t *pid)
{
    pid->integral = 0.0f;
}

float pid_update(pid_t *pid, float error, float derivative, float dt)
{
    float output;

    pid->integral += pid->ki * error * dt;
    pid->integral = clamp(pid->integral, pid->integral_limit);

    output = (pid->kp * error) + pid->integral - (pid->kd * derivative);

    return clamp(output, pid->output_limit);
}
