/*
 * picobin IMAGE_DEF block, required by the RP2350 bootrom (it scans the first
 * 4 KB of a flash image for this block; without it the image is treated as
 * blank and never boots).
 *
 * Single block, 20 (ARM) / 28 (RISC-V) bytes:
 *
 *   word 0: block marker 0xffffded3
 *   1BS_IMAGE_TYPE item (tag 0x42, size 1):
 *     ARM    -> 0x1021  EXE | CHIP_RP2350 | ARM  (no entry point: the bootrom
 *                                           remaps the flash image to address
 *                                           0 and boots it via the vector
 *                                           table, so both stay at flash
 *                                           offset 0 for the emulator too)
 *     RISC-V -> 0x1101  EXE | CHIP_RP2350 | RISC-V
 *   [RISC-V only] 1BS_ENTRY_POINT item (tag 0x44, size 3): entry PC + initial SP
 *   2BS_LAST item (tag 0xff): (size in words items preceding it, i.e.
 *                              (block_end - block_start - 16) / 4)
 *   word: next block pointer (0 = self, i.e. no further blocks)
 *   word: block end marker 0xab123579
 */
.balign 4
.section .image_def, "a"
__image_def_block_start:
    .word 0xffffded3

#ifdef __riscv
    .byte 0x42, 0x01
    .short 0x1101

    .byte 0x44
    .short 0x0003
    .byte 0x00
    .word _reset
    .word __stack_top

    /* image_type + entry(header + 2 payload words) = 3 words before LAST */
    .byte 0xff
    .short 0x0003
#else
    .byte 0x42, 0x01
    .short 0x1021

    /* image_type only = 1 word before LAST */
    .byte 0xff
    .short 0x0001
#endif
    .byte 0x00

    .word 0x00000000
    .word 0xab123579
__image_def_block_end:
