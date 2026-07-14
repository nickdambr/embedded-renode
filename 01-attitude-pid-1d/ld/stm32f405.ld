/* STM32F405 - 1 MB flash, 128 KB SRAM. Bare-metal, no libc, no heap. */

ENTRY(Reset_Handler)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);
_stack_size = 4K;

SECTIONS
{
    .isr_vector : ALIGN(4)
    {
        KEEP(*(.isr_vector))
    } > FLASH

    .text : ALIGN(4)
    {
        *(.text)
        *(.text*)
        *(.rodata)
        *(.rodata*)
        . = ALIGN(4);
    } > FLASH

    /* Load address of .data, used by the startup code to copy it into RAM. */
    _sidata = LOADADDR(.data);

    .data : ALIGN(4)
    {
        _sdata = .;
        *(.data)
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT > FLASH

    .bss (NOLOAD) : ALIGN(4)
    {
        _sbss = .;
        *(.bss)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    /* Fail the link instead of silently overflowing into the stack. */
    .stack_guard (NOLOAD) : ALIGN(8)
    {
        . = . + _stack_size;
    } > RAM

    /DISCARD/ :
    {
        *(.ARM.exidx*)
        *(.ARM.extab*)
    }
}
