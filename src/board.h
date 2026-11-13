#ifndef BOARD_H
#define BOARD_H

/* Hardware setup shared by every program in this project (benchmarks and the
 * UART smoke test). Plain register writes, no SDK. Same code on ARM and RISC-V. */

/* Bring the board up: release the blocks we use from reset, start the 12 MHz
 * crystal, run clk_ref and clk_sys from it, and set up UART0 on GPIO0 (TX) /
 * GPIO1 (RX) at 115200 8N1. Call once, at the start of main(). */
void board_init(void);

/* Send a NUL-terminated string on UART0. Waits while the TX FIFO is full,
 * but gives up after a bounded number of checks so it can never hang. */
void uart_print(const char *str);

/* Send an unsigned decimal number (no padding) on UART0. */
void uart_print_u32(uint32_t value);

/* Free-running cycle counter for on-target timing (see src/main.c).
 * board_cycles_init() is called by board_init(); board_cycles_now() returns a
 * monotonically increasing count so elapsed = now() - now(). The counter wraps
 * every 2^24 cycles (~1.4 s at 12 MHz) on ARM, so keep measured windows short.
 * On ARM this is SysTick in clk_sys mode (the rp2350js simulator models it
 * too); on RISC-V it is the standard mcycle CSR. */
void board_cycles_init(void);
uint32_t board_cycles_now(void);

#endif /* BOARD_H */
