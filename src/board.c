#include <stdint.h>

#include "board.h"

/* ------------------------------ RP2350 hardware --------------------------- */

#define UART0_BASE 0x40070000u
#define UART0_DR   (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART0_FR   (*(volatile uint32_t *)(UART0_BASE + 0x18))
#define UART0_IBRD (*(volatile uint32_t *)(UART0_BASE + 0x24))
#define UART0_FBRD (*(volatile uint32_t *)(UART0_BASE + 0x28))
#define UART0_LCR  (*(volatile uint32_t *)(UART0_BASE + 0x2c))
#define UART0_CR   (*(volatile uint32_t *)(UART0_BASE + 0x30))
#define UART_FR_TXFF (1u << 5)  /* TX FIFO full, wait before writing DR */

/* Peripheral resets (release the blocks we touch out of reset). */
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

#define CLOCKS_BASE      0x40010000u
#define CLK_REF_CTRL     (*(volatile uint32_t *)(CLOCKS_BASE + 0x30))
#define CLK_REF_SELECTED (*(volatile uint32_t *)(CLOCKS_BASE + 0x38))
#define CLK_SYS_CTRL     (*(volatile uint32_t *)(CLOCKS_BASE + 0x3c))
#define CLK_SYS_SELECTED (*(volatile uint32_t *)(CLOCKS_BASE + 0x44))
#define CLK_PERI_CTRL    (*(volatile uint32_t *)(CLOCKS_BASE + 0x48))

#define PADS_BANK0_BASE 0x40038000u
#define PADS_BANK0_ISO (1u << 8) /* pad isolated while set */
#define PADS_BANK0_IE  (1u << 6) /* input enable */

#define IO_BANK0_BASE 0x40028000u
#define GPIO0_CTRL    (*(volatile uint32_t *)(IO_BANK0_BASE + 0x04))
#define GPIO1_CTRL    (*(volatile uint32_t *)(IO_BANK0_BASE + 8 * 1 + 0x04))
#define GPIO_FUNC_UART 2u

/* Bounded busy-wait: returns as soon as all bits of mask are set in reg, or
 * after a fixed number of tries. The simulator does not implement the XOSC
 * (its registers just read back as all ones), so we can't rely on its status
 * bit there; and on a real board a register that never reports ready still
 * can't hang the program forever. */
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

/* Real-hardware bring-up, called once before any timed work:
 * XOSC 12 MHz -> clk_ref -> clk_sys, then UART0 on GPIO0 (TX) at 115200. */
void board_init(void)
{
    /* Release peripherals from reset. */
    RESETS_CLEAR = RESETS_RELEASE_MASK;
    poll_set(&RESETS_DONE, RESETS_RELEASE_MASK);

    /* RP2350 pads come out of reset isolated (ISO=1, IE=0): until ISO is
     * cleared a pad neither drives its pin nor sees its input. */
    volatile uint32_t *pad = (volatile uint32_t *)(PADS_BANK0_BASE + 0x04u);
    pad[0] &= ~PADS_BANK0_ISO;                          /* GPIO0: UART0 TX */
    pad[1] = (pad[1] & ~PADS_BANK0_ISO) | PADS_BANK0_IE; /* GPIO1: UART0 RX */

    /* Start the crystal and wait for it to be stable. */
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
     * 115200: 12 MHz / (16 * (6 + 33/64)) = 115108 (-0.08%). */
    GPIO0_CTRL = GPIO_FUNC_UART;
    GPIO1_CTRL = GPIO_FUNC_UART;
    UART0_IBRD = 6u;
    UART0_FBRD = 33u;
    UART0_LCR  = (3u << 5) | (1u << 4); /* 8 data bits + FIFO (8N1) */
    UART0_CR   = 0x101u;                /* UART enable | TX enable */

    board_cycles_init();
}

void uart_print(const char *str)
{
    while (*str)
    {
        /* Bounded TX wait: if the UART stalls we still return, so a stuck
         * UART can't hang the program. */
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

void uart_print_u32(uint32_t value)
{
    char digits[10];
    uint32_t count = 0;

    if (value == 0u)
    {
        uart_print("0");
        return;
    }

    while (value > 0u)
    {
        digits[count++] = (char)('0' + (value % 10u));
        value /= 10u;
    }

    while (count > 0u)
    {
        char one[2] = { digits[--count], '\0' };
        uart_print(one);
    }
}

/* ---------------------------- cycle counter ------------------------------ */
/* ARM: SysTick used as a free-running 24-bit down-counter (clk_sys, no
 * interrupt). It is part of the core's PPB, so it needs no reset/peripheral
 * clock setup, and the rp2350js simulator implements it as well. We return
 * the count as a rising value so `elapsed = after - before` works.
 * RISC-V: the standard mcycle CSR (Hazard3 supports rdcycle). */

#if defined(__arm__) || defined(__thumb__)

#define SYST_CSR (*(volatile uint32_t *)0xE000E010u)
#define SYST_RVR (*(volatile uint32_t *)0xE000E014u)
#define SYST_CVR (*(volatile uint32_t *)0xE000E018u)
#define SYST_CSR_ENABLE    (1u << 0)
#define SYST_CSR_CLKSOURCE (1u << 2) /* 1 = clk_sys */
#define SYST_RELOAD        0x00FFFFFFu

void board_cycles_init(void)
{
    SYST_RVR = SYST_RELOAD;
    SYST_CVR = 0u;
    SYST_CSR = SYST_CSR_ENABLE | SYST_CSR_CLKSOURCE;
}

uint32_t board_cycles_now(void)
{
    return SYST_RELOAD - SYST_CVR;
}

#elif defined(__riscv)

void board_cycles_init(void)
{
}

uint32_t board_cycles_now(void)
{
    uint32_t cycles;
    __asm volatile("rdcycle %0" : "=r"(cycles));
    return cycles;
}

#else

void board_cycles_init(void)
{
}

uint32_t board_cycles_now(void)
{
    return 0u;
}

#endif
