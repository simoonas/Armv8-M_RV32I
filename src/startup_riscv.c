#include <stdint.h>

/* Redirection stubs for the few libc symbols a bare-metal image may pull in. */
int _close(int file) { (void)file; return -1; }
int _lseek(int file, int ptr, int dir) { (void)file; (void)ptr; (void)dir; return 0; }
int _read(int file, char *ptr, int len) { (void)file; (void)ptr; (void)len; return 0; }
int _write(int file, char *ptr, int len) { (void)file; (void)ptr; return len; }
void _exit(int status) { (void)status; while (1) { __asm volatile(""); } }
void *_sbrk(int incr) { (void)incr; return (void *)-1; }

extern int main(void);

/* Bound symbols produced by the linker script (link/rp2350_riscv.ld). */
extern uint32_t __stack_top;
extern uint32_t __data_start, __data_end, __data_lma;
extern uint32_t __bss_start, __bss_end;

__attribute__((section(".init"), noreturn))
void _reset(void);
/* IMAGE_DEF block: tells the RP2350 bootrom "this is a bootable RISC-V
 * program". Without it the bootrom refuses to run the image from flash. The
 * bootrom searches the first 4 KB of flash for it; the linker script places it
 * right after _reset. With no ENTRY_POINT item, the bootrom starts RISC-V
 * programs at the start of the image, which is _reset. The simulator ignores it.
 * Format: RP2350 datasheet "minimum viable image metadata", same as
 * pico-sdk's embedded_start_block.inc.S. */
__attribute__((section(".embedded_block"), used))
const uint32_t image_def[] = {
    0xffffded3, /* block start marker */
    0x11010142, /* IMAGE_TYPE item (0x42), 1 word: EXE | RISC-V | RP2350 */
    0x000001ff, /* LAST item: the items above total 1 word */
    0x00000000, /* offset to the next block: 0 = this block links to itself */
    0xab123579, /* block end marker */
};

/* Entry point after reset. sp is undefined here, so this is naked (no compiler-generated
   stack use): set sp, then jump to _reset_c. */
__attribute__((naked, section(".init"), noreturn))
void _reset(void) {
    __asm volatile(
"la sp, __stack_top\n"
"j _reset_c\n"
    );
}

/* Called from _reset once sp is valid, so plain C works: copy .data/.bss like any runtime would. */
__attribute__((noreturn))
void _reset_c(void) {
    for (uint32_t *src = &__data_lma, *dst = &__data_start;
         dst < &__data_end;) {
        *dst++ = *src++;
    }

    for (uint32_t *dst = &__bss_start; dst < &__bss_end;) {
        *dst++ = 0;
    }

    main();

    while (1) {
        __asm volatile("");
    }
}