/*
 * Reset vector and C runtime bring-up. No assembly: the vector table is a
 * const array placed at the start of flash by the linker script, and the reset
 * handler initialises .data/.bss before calling main().
 */
#include <stdint.h>

extern uint32_t _sidata;
extern uint32_t _sdata;
extern uint32_t _edata;
extern uint32_t _sbss;
extern uint32_t _ebss;
extern uint32_t _estack;

int main(void);
void Reset_Handler(void);
void SysTick_Handler(void);
static void Default_Handler(void);

void Reset_Handler(void)
{
    /* Copy initialised data from flash to RAM. */
    uint32_t *src = &_sidata;
    for (uint32_t *dst = &_sdata; dst < &_edata; ++dst) {
        *dst = *src++;
    }

    /* Zero the .bss section. */
    for (uint32_t *dst = &_sbss; dst < &_ebss; ++dst) {
        *dst = 0u;
    }

    (void)main();

    for (;;) {
    }
}

static void Default_Handler(void)
{
    for (;;) {
    }
}

/*
 * Cortex-M4 vector table: initial stack pointer, then the 15 system exception
 * handlers. SysTick is entry 15 and is the only one this project services.
 */
__attribute__((used, section(".isr_vector"))) void (*const g_vectors[16])(void) = {
    (void (*)(void)) & _estack, /* 0  Initial stack pointer     */
    Reset_Handler,              /* 1  Reset                     */
    Default_Handler,            /* 2  NMI                       */
    Default_Handler,            /* 3  HardFault                 */
    Default_Handler,            /* 4  MemManage                 */
    Default_Handler,            /* 5  BusFault                  */
    Default_Handler,            /* 6  UsageFault                */
    0,                          /* 7  Reserved                  */
    0,                          /* 8  Reserved                  */
    0,                          /* 9  Reserved                  */
    0,                          /* 10 Reserved                  */
    Default_Handler,            /* 11 SVCall                    */
    Default_Handler,            /* 12 DebugMonitor              */
    0,                          /* 13 Reserved                  */
    Default_Handler,            /* 14 PendSV                    */
    SysTick_Handler,            /* 15 SysTick                   */
};
