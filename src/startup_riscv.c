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