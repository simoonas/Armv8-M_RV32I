#include <stdint.h>

#include "board.h"

/* Iteration counts */
#define ARITHMETIC_ITERATIONS 10000
#define ARRAY_SIZE 256
#define ARRAY_ITERATIONS 100
#define BITWISE_ITERATIONS 10000

/* Volatile sink used to keep each benchmark's final result observable to the compiler, which prevents their computations from being eliminated as dead code */
volatile uint32_t benchmark_result;

/* Array used by the memory-processing benchmark */
static uint32_t data[ARRAY_SIZE];

/*
 * Benchmark 1: Arithmetic
 */
__attribute__((noinline)) void benchmark_arithmetic(void)
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

int main(void)
{
    board_init();

    /* Initialize the array outside the timed benchmark */
    for (uint32_t i = 0; i < ARRAY_SIZE; i++)
    {
        data[i] = i + 1;
    }

    /* Board metadata for the hardware-results parser (scripts/parse_hw_results.js). */
    uart_print("CLOCK_HZ 12000000\n");

    /* The simulator (scripts/run_sim.js) times each benchmark between its
     * START and END lines on UART0, so keep these strings unchanged.
     *
     * The cycle counts are taken at the same points the simulator uses (just
     * after the last START byte and just after the last END byte is written),
     * so the numbers are directly comparable. `make measure-arm` captures
     * them from the real board. */
    uart_print("START_ARITHMETIC_BENCHMARK\n");
    uint32_t start = board_cycles_now();
    benchmark_arithmetic();
    uart_print("END_ARITHMETIC_BENCHMARK\n");
    uint32_t cycles = board_cycles_now() - start;
    uart_print("CYCLE_ARITHMETIC ");
    uart_print_u32(cycles);
    uart_print("\n");

    uart_print("START_ARRAY_BENCHMARK\n");
    start = board_cycles_now();
    benchmark_array();
    uart_print("END_ARRAY_BENCHMARK\n");
    cycles = board_cycles_now() - start;
    uart_print("CYCLE_ARRAY ");
    uart_print_u32(cycles);
    uart_print("\n");

    uart_print("START_BITWISE_BENCHMARK\n");
    start = board_cycles_now();
    benchmark_bitwise();
    uart_print("END_BITWISE_BENCHMARK\n");
    cycles = board_cycles_now() - start;
    uart_print("CYCLE_BITWISE ");
    uart_print_u32(cycles);
    uart_print("\n");

    /* Nothing left to do: idle forever. */
    while (1)
    {
    }
}
