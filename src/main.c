#include <stdint.h>

/* ------------------------------ RP2350 hardware --------------------------- */

#define UART0_BASE 0x40070000u
#define UART0_DR   (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART0_FR   (*(volatile uint32_t *)(UART0_BASE + 0x18))
#define UART0_IBRD (*(volatile uint32_t *)(UART0_BASE + 0x24))
#define UART0_FBRD (*(volatile uint32_t *)(UART0_BASE + 0x28))
#define UART0_LCR  (*(volatile uint32_t *)(UART0_BASE + 0x2c))
#define UART0_CR   (*(volatile uint32_t *)(UART0_BASE + 0x30))
#define UART_FR_TXFF (1u << 5)  /* TX FIFO full, wait before writing DR */

/*Peripheral 'resets' (release the blocks we touch out of reset). */
#define RESETS_BASE         0x40020000u
#define RESETS_DONE         (*(volatile uint32_t *)(RESETS_BASE + 0x0008))
#define RESETS_CLEAR        (*(volatile uint32_t *)(RESETS_BASE + 0x3000))
/* UART0 (bit 26) | PADS_BANK0 (bit 9) | IO_BANK0 (bit 6) */
#define RESETS_RELEASE_MASK 0x04000240u

/* 12 MHz crystal oscillator (Pico 2). */
#define XOSC_BASE        0x40048000u
#define XOSC_CTRL        (*(volatile uint32_t *)(XOSC_BASE + 0x00))
#define XOSC_STATUS      (*(volatile uint32_t *)(XOSC_BASE + 0x04))
#define XOSC_STARTUP     (*(volatile uint32_t *)(XOSC_BASE + 0x0c))
#define XOSC_ENABLE      (0xfabu << 12 | 0xaau)  /* enable | 1-15 MHz range */
#define XOSC_STATUS_STABLE (1u << 31)

#define CLOCKS_BASE     0x40010000u
#define CLK_REF_CTRL     (*(volatile uint32_t *)(CLOCKS_BASE + 0x30))
#define CLK_REF_SELECTED (*(volatile uint32_t *)(CLOCKS_BASE + 0x38))
#define CLK_SYS_CTRL     (*(volatile uint32_t *)(CLOCKS_BASE + 0x3c))
#define CLK_SYS_SELECTED (*(volatile uint32_t *)(CLOCKS_BASE + 0x44))
#define CLK_PERI_CTRL    (*(volatile uint32_t *)(CLOCKS_BASE + 0x48))

#define PADS_BANK0_BASE 0x40038000u
#define PADS_BANK0_ISO (1u << 8) /* pad isolated while set */
#define PADS_BANK0_IE  (1u << 6)

#define IO_BANK0_BASE 0x40028000u
#define GPIO0_CTRL    (*(volatile uint32_t *)(IO_BANK0_BASE + 0x04))
#define GPIO1_CTRL    (*(volatile uint32_t *)(IO_BANK0_BASE + 8 * 1 + 0x04))
#define GPIO_FUNC_UART 2u

/* Pico 2 on-board LED: GPIO25 driven directly by the SIO (funcsel 5).
 * NOTE on Pico 2 W the LED lives on the CYW43 (WL_GPIO0); GPIO25 is WL_CS,
 * so driving GPIO25 deglitches the WLAN chip-select, not the LED. */
#define GPIO25_CTRL     (*(volatile uint32_t *)(IO_BANK0_BASE + 8 * 25 + 0x04))
#define GPIO_FUNC_SIO   5u
/* RP2350 SIO map (differs from RP2040): OUT_SET 0x18, OUT_CLR 0x20,
 * OUT_XOR 0x28, OE 0x30, OE_SET 0x38, OE_CLR 0x40, OE_XOR 0x48. */
#define SIO_GPIO_OE_SET  (*((volatile uint32_t *)0xd0000038u))
#define SIO_GPIO_OUT_XOR (*((volatile uint32_t *)0xd0000028u))

/* Bounded successor wait: returns as soon as mask is set in reg, or after a
 * bounded number of iterations. The emulator neither implements the XOSC nor
 * advances clock-mux state, so unbounded polls would spin there forever. */
static void poll_set(volatile uint32_t *reg, uint32_t mask)
{
    for (uint32_t i = 0; i < 1000000u; i++)
    {
        if ((*reg & mask) == mask)
        {
            return;
        }
        __asm volatile("nop");
    }
}

static void delay_loops(volatile uint32_t n)
{
    while (n--)
    {
        __asm volatile("nop");
    }
}

/* Real-hardware bring-up, called once before any timed work:
 * XOSC 12 MHz -> clk_ref -> clk_sys, then UART0 on GPIO0 (TX) at 115200. */
static void board_init(void)
{
    /* Release peripherals from reset. */
    RESETS_CLEAR = RESETS_RELEASE_MASK;
    poll_set(&RESETS_DONE, RESETS_RELEASE_MASK);

    /* RP2350 pads come out of reset isolated (ISO=1, IE=0): until ISO is
     * cleared a pad neither drives its pin nor sees its input. */
    volatile uint32_t *pad = (volatile uint32_t *)(PADS_BANK0_BASE + 0x04u);
    pad[0] &= ~PADS_BANK0_ISO; /* GPIO0: UART0 TX */
    pad[1] &= ~(PADS_BANK0_ISO | PADS_BANK0_IE); /* GPIO1: UART0 RX */
    pad[1] |= PADS_BANK0_IE;
    pad[25] &= ~PADS_BANK0_ISO; /* GPIO25: on-board LED */

    /* Start the crystal and wait for stability. */
    XOSC_STARTUP = 47u; /* (12 kHz cycles + 128) / 256 */
    XOSC_CTRL = XOSC_ENABLE;
    poll_set(&XOSC_STATUS, XOSC_STATUS_STABLE);

    /* clk_sys = clk_ref = XOSC gives an exact 12 MHz time base (the bootrom
     * leaves clk_sys on the ROSC, whose frequency is inaccurate). */
    CLK_REF_CTRL = 2u; /* clk_ref source: XOSC (0=rosc 1=aux 2=xosc) */
    poll_set(&CLK_REF_SELECTED, 1u << 2);
    CLK_SYS_CTRL = 0u; /* clk_sys source: clk_ref */
    poll_set(&CLK_SYS_SELECTED, 1u << 0);
    CLK_PERI_CTRL |= 0x800u; /* clk_peri enable, aux = clk_sys */

    /* UART0 on the Pico 2's default debug pins: GPIO0 = TX, GPIO1 = RX.
     * 115200: 12 MHz / (16 * (6 + 33/64)) = 115294 (+0.08%). */
    GPIO0_CTRL = GPIO_FUNC_UART;
    GPIO1_CTRL = GPIO_FUNC_UART;
    UART0_IBRD = 6u;
    UART0_FBRD = 33u;
    UART0_LCR  = (3u << 5) | (1u << 4); /* 8 data bits + FIFO (8N1) */
    UART0_CR   = 0x101u;                /* UART enable | TX enable */
}

/* Iteration counts */
#define ARITHMETIC_ITERATIONS 10000
#define ARRAY_SIZE 256
#define ARRAY_ITERATIONS 100
#define BITWISE_ITERATIONS 10000

/* Volatile sink used to keep each benchmark's final result observable to the compiler, which prevents their computations from being eliminated as dead code */
volatile uint32_t benchmark_result;

#ifndef UART_SMOKE
/* Array used by the memory-processing benchmark */
static uint32_t data[ARRAY_SIZE];
#endif /* !UART_SMOKE */

void uart_print(const char *str)
{
    while (*str)
    {
        /* Bounded TX wait: if the UART stalls we still return, so a hang
         * can never block the LED diagnostics that follow. */
        for (uint32_t i = 0; i < 1000000u; i++)
        {
            if (!(UART0_FR & UART_FR_TXFF))
            {
                break;
            }
        }
        UART0_DR = (uint32_t)(*str++);
    }
}

#ifndef UART_SMOKE

/*
 * Benchmark 1: Arithmetic
 */
__attribute__((noinline)) void benchmark_aritmetic(void)
{
    uint32_t sum = 0;

    for (uint32_t i = 0; i < ARITHMETIC_ITERATIONS; i++)
    {
        sum += i * i;
    }

    benchmark_result = sum;
}

/*
 * Benchmark 2: Array processing
 */
__attribute__((noinline)) void benchmark_array(void)
{
    uint32_t sum = 0;

    for (uint32_t i = 0; i < ARRAY_ITERATIONS; i++)
    {
        for (uint32_t j = 0; j < ARRAY_SIZE; j++)
        {
            data[j] = data[j] * 3u + j;
            sum += data[j];
        }
    }

    benchmark_result = sum;
}

/*
 * Benchmark 3: Bitwise operations
 */
__attribute__((noinline)) void benchmark_bitwise(void)
{
    uint32_t x = 0x12345678u;

    for (uint32_t i = 0; i < BITWISE_ITERATIONS; i++)
    {
        x ^= x << 5;
        x |= x >> 7;
        x &= 0xF0F0F0F0u;
        x ^= 0xA5A5A5A5u;
        x = (x << 3) | (x >> 29);
    }

    benchmark_result = x;
}
#endif /* !UART_SMOKE */

#ifdef UART_SMOKE
/* Zero-variable smoke test: board_init at 115200, then print a short line
 * every ~100 ms forever. No LED/WL_CS writes, no benchmarks, no ALIVE loop:
 * if this garbles, the fault is in the bring-up path or wiring itself. */
int main(void)
{
    board_init();

    while (1)
    {
        uart_print("PING-9955\n");
        delay_loops(1200000u); /* ~100 ms at 12 MHz */
    }
}
#else
int main(void)
{
    board_init();

    /* LED heartbeat FIRST, before any UART traffic: if the LED blinks, the
     * reset/XOSC/clock/pad bring-up in board_init finished successfully. */
    GPIO25_CTRL = GPIO_FUNC_SIO;
    SIO_GPIO_OE_SET = 1u << 25;
    SIO_GPIO_OUT_XOR = 1u << 25;
    delay_loops(1500000u);
    SIO_GPIO_OUT_XOR = 1u << 25;
    delay_loops(1500000u);
    SIO_GPIO_OUT_XOR = 1u << 25;
    delay_loops(1500000u);
    SIO_GPIO_OUT_XOR = 1u << 25;

    /* Readability probe: digits survive garbling less ambiguously than
     * letters, so a full clean line here means the 115200 path is intact. */
    uart_print("BOOT0123456789\n");

    /* Initialize the array outside the timed benchmark */
    for (uint32_t i = 0; i < ARRAY_SIZE; i++)
    {
        data[i] = i + 1;
    }

    uart_print("START_ARITHMETIC_BENCHMARK\n");
    benchmark_aritmetic();
    uart_print("END_ARITHMETIC_BENCHMARK\n");
    SIO_GPIO_OUT_XOR = 1u << 25; /* blip 1 */
    delay_loops(750000u); SIO_GPIO_OUT_XOR = 1u << 25;
    delay_loops(750000u);

    uart_print("START_ARRAY_BENCHMARK\n");
    benchmark_array();
    uart_print("END_ARRAY_BENCHMARK\n");
    SIO_GPIO_OUT_XOR = 1u << 25; /* blip 2 */
    delay_loops(750000u); SIO_GPIO_OUT_XOR = 1u << 25;
    delay_loops(750000u);

    uart_print("START_BITWISE_BENCHMARK\n");
    benchmark_bitwise();
    uart_print("END_BITWISE_BENCHMARK\n");
    SIO_GPIO_OUT_XOR = 1u << 25; /* blip 3 */
    delay_loops(750000u); SIO_GPIO_OUT_XOR = 1u << 25;
    delay_loops(750000u);

    /* Hardware diagnostics loop (never reached in the simulator, which stops
     * as soon as the last END marker arrives): toggle the on-board LED forever
     * and re-print a non-marker string so a flashed board can be bisected
     * without working serial output. LED blinking => board_init completed. */
    while (1)
    {
        uart_print("ALIVE\n");
        delay_loops(2000000u);
        SIO_GPIO_OUT_XOR = 1u << 25;
        delay_loops(2000000u);
    }
}
#endif /* UART_SMOKE */
