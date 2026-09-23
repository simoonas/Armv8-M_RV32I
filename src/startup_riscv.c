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
void _reset(void) {
    /* Set up the stack pointer, then copy .data/.bss like any runtime would. */
    __asm volatile("la sp, %0" : : "i"(&__stack_top));
    for (uint32_t *src = &__data_lma, *dst = &__data_start; dst < &__data_end;) {
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