/* RP2350 Cortex-M33 (ARM) memory map.
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

/* Resets vector with Thumb bit set (defined here so vector_table can hold a
 * link-time constant rather than a computed function-pointer expression). */
PROVIDE(_reset_vector = _reset + 1);

SECTIONS
{
  .vectors :
  {
    KEEP(*(.vectors))
  } > FLASH

  /* picobin IMAGE_DEF block (src/image_def.S), required by the RP2350
   * bootrom's flash scan; it searches the first 4 KB of the image. */
  .image_def :
  {
    KEEP(*(.image_def))
  } > FLASH

  .text :
  {
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
    *(.bss*)
    *(COMMON)
    __bss_end = .;
  } > RAM
    . = ALIGN(4);
  __heap_start = .;
}