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

#endif /* BOARD_H */
