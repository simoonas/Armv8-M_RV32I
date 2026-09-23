#include <stdint.h>

#define UART0_DR ((volatile uint32_t *)0x40070000)

void uart_print(const char *str) {
    while (*str) {
        *UART0_DR = (uint32_t)(*str++);
    }
}

__attribute__((noinline)) void benchmark_workload(void) {
    volatile uint32_t sum = 0;
    for (uint32_t i = 0; i < 10000; i++) {
        sum += i * i;
    }
}

void main(void) {
    uart_print("START_BENCHMARK\n");
    benchmark_workload();
    uart_print("END_BENCHMARK\n");

    while (1) {
        __asm volatile("nop");
    }
}
