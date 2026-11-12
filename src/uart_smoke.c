#include <stdint.h>

#include "board.h"

/* UART smoke test: the smallest program that proves the board bring-up and
 * the serial link work. No benchmarks, just board_init() and then a short
 * line about every 100 ms, forever. If this line comes out garbled or not at
 * all, the problem is in board_init() or the wiring, not in the benchmarks. */

static void delay_loops(volatile uint32_t n)
{
    while (n--)
    {
        __asm volatile("nop");
    }
}

int main(void)
{
    board_init();

    while (1)
    {
        uart_print("PING-9955\n");
        /* One pass of the delay loop takes ~4-6 CPU cycles, so at 12 MHz
         * this is roughly 70-100 ms (measured in the simulator). */
        delay_loops(200000u);
    }
}
