/* RP2350 Hazard3 (RISC-V) memory map.
 *
 *  Flash: XIP aliased at 0x10000000 (16 MB)
 *  SRAM : 0x20000000 (520 KB)
 */
ENTRY(_reset)

MEMORY
{
  FLASH (rx)  : ORIGIN = 0x10000000, LENGTH = 0x1000000
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 0x82000
}

__stack_top = 0x20080000;

SECTIONS
{
  .text :
  {
    KEEP(*(.init))
    *(.text*)
  } > FLASH

  .rodata :
  {
    *(.rodata*)
  } > FLASH

  __data_lma = LOADADDR(.data);
  .data ALIGN(4) :
  {
    __data_start = .;
    *(.data*)
    __data_end = .;
  } > RAM AT> FLASH

  .bss (NOLOAD) :
  {
    . = ALIGN(4);
    __bss_start = .;
    *(.sbss*)
    *(.scommon)
    *(.bss*)
    *(COMMON)
    __bss_end = .;
  } > RAM

  . = ALIGN(4);
  __heap_start = .;
}