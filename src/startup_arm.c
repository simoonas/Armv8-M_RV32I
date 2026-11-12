#include <stdint.h>

/* Redirection stubs for the few libc symbols a bare-metal image may pull in.
 * Not part of the benchmark itself. */
int _close(int file) { (void)file; return -1; }
int _lseek(int file, int ptr, int dir) { (void)file; (void)ptr; (void)dir; return 0; }
int _read(int file, char *ptr, int len) { (void)file; (void)ptr; (void)len; return 0; }
int _write(int file, char *ptr, int len) { (void)file; (void)ptr; return len; }
void _exit(int status) { (void)status; while (1) { __asm volatile(""); } }
void *_sbrk(int incr) { (void)incr; return (void *)-1; }

extern int main(void);

/* Bound symbols produced by the linker script (link/rp2350_arm.ld). */
extern uint32_t __stack_top;
extern uint32_t _reset_vector;
extern uint32_t __data_start, __data_end, __data_lma;
extern uint32_t __bss_start, __bss_end;

void _reset(void);

/* Trap handler for NMI/HardFault/faults/IRQs we do not use: park instead of
 * executing whatever garbage the vector table used to contain. */
__attribute__((noreturn)) static void _hang(void)
{
    while (1) {
        __asm volatile("wfi");
    }
}

/* ARMv8-M reset: initial MSP at offset 0, reset vector at offset 4 with the
 * Thumb bit set, then NMI/HardFault and reserved/system entries. Must sit at
 * the very start of flash (0x10000000). Filling unused entries with _hang
 * keeps an accidental exception from running random flash contents. */
__attribute__((section(".vectors"), used))
const uint32_t vector_table[] = {
    (uint32_t)&__stack_top,                      /* initial Main Stack Pointer */
    (uint32_t)&_reset_vector,                    /* reset handler, Thumb bit set */
    (uint32_t)((const void *)_hang + 1),         /* NMI */
    (uint32_t)((const void *)_hang + 1),         /* HardFault */
    0, 0, 0, 0, 0, 0, 0,                         /* reserved */
    (uint32_t)((const void *)_hang + 1),         /* SVC */
    (uint32_t)((const void *)_hang + 1),         /* DebugMon */
    0,                                           /* reserved */
    (uint32_t)((const void *)_hang + 1),         /* PendSV */
    (uint32_t)((const void *)_hang + 1),         /* SysTick */
};

/* IMAGE_DEF block: tells the RP2350 bootrom "this is a bootable Arm program".
 * Without it the bootrom refuses to run the image from flash. The bootrom
 * searches the first 4 KB of flash for it; the linker script places it right
 * after the vector table. The simulator ignores it.
 * Format: RP2350 datasheet "minimum viable image metadata", same as
 * pico-sdk's embedded_start_block.inc.S. */
__attribute__((section(".embedded_block"), used))
const uint32_t image_def[] = {
    0xffffded3, /* block start marker */
    0x10210142, /* IMAGE_TYPE item (0x42), 1 word: EXE | Secure | Arm | RP2350 */
    0x000001ff, /* LAST item: the items above total 1 word */
    0x00000000, /* offset to the next block: 0 = this block links to itself */
    0xab123579, /* block end marker */
};

/* Entry point: copy .data, zero .bss, run main. */
void _reset(void) {
    /* Copy .data initialisers from flash into RAM. */
    for (uint32_t *src = &__data_lma, *dst = &__data_start; dst < &__data_end;) {
        *dst++ = *src++;
    }
    /* Zero .bss. */
    for (uint32_t *dst = &__bss_start; dst < &__bss_end;) {
        *dst++ = 0;
    }
    main();
    while (1) {
        __asm volatile("");
    }
}