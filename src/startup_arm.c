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

/* ARMv8-M reset: initial MSP at offset 0, reset vector at offset 4 with the
 * Thumb bit set. Must sit at the very start of flash (0x10000000). */
__attribute__((section(".vectors"), used))
const uint32_t vector_table[] = {
    (uint32_t)&__stack_top,      /* initial Main Stack Pointer */
    (uint32_t)&_reset_vector,    /* reset handler, Thumb bit set */
};

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