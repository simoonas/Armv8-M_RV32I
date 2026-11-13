# Armv8-M vs RISC-V RP2350

Compile small C program for RP2350's 2 CPU architectures (ARM Cortex-M33, RISC-V Hazard3) and compare results:

- Binary size at `-O2` and `-Os` (flash/RAM footprint)
- Cycle count reported by [rp2350js](tools/rp2350js) while it runs produced UF2 images from `START_BENCHMARK` to `END_BENCHMARK`
- The same cycle counts are measured on a real Pico 2 with `make measure-arm` nd shown in `make compare`

builds are bare metal (own startup code + linker scripts), small and the architecture comparison is clean.

## Clone

```bash
git clone --recursive https://github.com/simoonas/Armv8-M_RV32I
```
## Install toolchains (Arch)

### ARM

```bash
sudo pacman -S arm-none-eabi-gcc arm-none-eabi-newlib cmake base-devel
```

### RISC-V

```bash
yay -S riscv32-elf-gcc riscv32-elf-newlib
```

RISC-V targets are skipped if none of these toolhains is installed:
- `riscv32-elf-gcc`
- `riscv-none-elf-gcc`
- `riscv64-unknown-elf-gcc`
- `riscv64-elf-gcc`

## Install toolchains (macOS)

Install the required build tools using Homebrew:

```bash
brew install cmake arm-none-eabi-gcc riscv64-elf-gcc
```

## Quick start (step by step)

```bash
make arm          # 1. build ARM benchmark images (build_arm/arm_O2|Os.uf2)
make sim          # 2. run them in the simulator, prints cycle counts
make compare      # 3. print size + cycle comparison tables
```

Run on real hardware (Pico 2 + Debug Probe, see details below):

```bash
./scripts/setup_openocd.sh   # 0. one-time: build RP2350 OpenOCD (needs ./scripts and git)
make flash-arm    # 1. build + flash + verify over SWD
make uart         # 2. watch UART output live (Ctrl-C to stop)
make halt-cm0     # 3. (when it misbehaves) SWD-halt core 0 and dump pc/lr/sp
make measure-arm  # 4. flash + capture cycle counts into results/ for make compare

make flash-smoke  # rescue: PING-only build to test when the board is silent
make clean        # remove build_arm and build_riscv
```

## Usage

Everything is in the toplevel Makefile:

- `make arm` builds `build_arm/arm_O2.{elf,bin,uf2}` and `build_arm/arm_Os.{elf,bin,uf2}` (Cortex-M33)
- `make riscv` same for `build_riscv/riscv_*` when a RISC-V toolchain present
- `make` / `make all` ARM + RISC-V
- `make sim` runs every produced `.uf2` through rp2350js, prints cycle count between START/END markers, UART output
- `make compare` prints the size table (uses `pyelftools` or `llvm-size`/`*-size` if `pyelftools` isn't installed) 
- `make measure-arm` flashes the board and captures the benchmark cycle counts into `results/hardware_arm_*.json` (both `-O2` and `-Os`); `make compare` then shows a second table with them
- `make clean` removes `build_arm` and `build_riscv`

Example:
```
make
make sim
make compare
python3 scripts/parse_elf.py build_arm/arm_O2.elf build_arm/arm_Os.elf \
    build_riscv/riscv_O2.elf build_riscv/riscv_Os.elf
```

## main.c

- `src/main.c` writes `START_BENCHMARK` to UART0 (0x40070000), runs
  `benchmark_workload()` (sum of squares for i in 1..10000), writes
  `END_BENCHMARK`, idles. Simulator measures cycles between those markers.
- `src/startup_arm.c` / `src/startup_riscv.c` - minimal reset code: sets up stack, copies `.data`, zeroes `.bss`, calls `main()`.
- `link/rp2350_arm.ld` / `link/rp2350_riscv.ld` - RP2350 memory map. Flash at 0x10000000, 520 KB SRAM at 0x20000000.

## Layout

- `CMakeLists.txt` builds each arch at `-O2`/`-Os`; needs `-DARCH=arm` or `-DARCH=riscv` (Makefile passes the toolchain file which sets it).
- `cmake/toolchain-arm.cmake`, `cmake/toolchain-riscv.cmake`
- `scripts/elf2uf2.py` converts `.bin` to RP2350 UF2 (family ID 0xe48bff56)
- `scripts/run_sim.js` loads a `.uf2` into rp2350js and boots by setting the vector table SP/PC directly (bare images have no IMAGE_DEF block), parks core 1, and prints the cycle count between START and END.
- `scripts/parse_elf.py` prints per arch binary size table.
- `scripts/measure_hw.sh` flashes the board over SWD and captures the benchmark cycle counts into `results/hardware_*.json` (`make measure-arm`).
- `scripts/parse_hw_results.js` converts a captured UART log (`CYCLE_*` lines) into that JSON
- `tools/rp2350js` git submodule of the simulator.

## Running on real hardware (Raspberry Pi Pico 2)

`make hardware` rebuilds everything and prints flash/monitor instructions.
The produced `.uf2` images are real-device bootable:

- `src/image_def.S` embeds the picobin `IMAGE_DEF` block the RP2350 bootrom
  requires (it scans the first 4 KB of flash; without this block the image
  never boots). ARM boots through the vector table at flash base; the RISC-V
  block carries the entry point and initial SP.
- `board_init()` (in `src/board.c`) starts the Pico 2's 12 MHz crystal, runs
  `clk_sys`/`clk_peri` from it, and configures UART0 (`GPIO0` = TX) at
  115200 8N1. On real hardware output is visible via the marker strings:
  `START_/END_{ARITHMETIC,ARRAY,BITWISE}_BENCHMARK`, followed by one
  `CYCLE_<BENCHMARK> <cycles>` line each.

Steps (Debug Probe, SWD + UART):

1. Wire the Debug Probe: **SWD** connector → the Pico's `DEBUG` pads
   (keyed), **UART** connector → Pico pins 1-3 next to the USB connector
   (GP0 = UART0 TX, GP1 = UART0 RX, GND).
2. One-time: build the RP2350-capable OpenOCD fork - `./scripts/setup_openocd.sh`
   (distro OpenOCD cannot flash RP2350). After a reboot, if OpenOCD reports
   `unable to find a matching CMSIS-DAP device`, reload the HID helpers:
   `sudo modprobe hid_generic usbhid` and replug the probe
3. `make flash-arm` - builds, flashes over SWD and **verifies** the image
   (`program ... verify`; BOOTSEL drag-and-drop has been seen to write flash
   only partially, leaving a silent board). `make flash-smoke` flashes the
   PING-only diagnostic build for bring-up checks.
4. `make uart` - streams the UART output live (Ctrl-C to stop).
   Expected: the six `START_/END_*_BENCHMARK` markers and their `CYCLE_*` lines.
5. `make halt-cm0` - SWD-halts core 0 and prints pc/lr/sp/xpsr for post-mortems.
   Example: a `pc` inside `_hang` means HardFault happened (vector table
   parks NMI/HardFault there);
6. `make measure-arm` - flashes both `-O2` and `-Os` images, captures the
   cycle counts and writes `results/hardware_arm_{O2,Os}.json`. `make compare`
   then prints a second table with the hardware numbers next to the simulator
   numbers.

`make hardware` reprints this command summary.

# Hardware bring-up and debugging (Pico 2 W + Debug Probe)

Workflow for running the ARM benchmark on real RP2350 hardware, established
after a long "silent board" investigation.

## Wiring

The Raspberry Pi Debug Probe exposes two 3-pin keyed connectors; both are used
simultaneously:

| Probe connector | Plugs onto            | Pins                       |
|-----------------|-----------------------|----------------------------|
| `UART`          | Pico pins 1-3, **next to the Pico's USB connector** | GP0 = UART0 TX (out of Pico), GP1 = UART0 RX (into Pico), GND |
| `SWD` (keyed)   | Pico `DEBUG` pads on the bottom edge          | SWCLK, SWDIO, GND |

Serial port: the probe enumerates as two CDC interfaces; the UART bridge is
the `if01` device, e.g.
`/dev/serial/by-id/usb-Raspberry_Pi_Debug_Probe__CMSIS-DAP__*-if01` (usually
`/dev/ttyACM3` here; the Pico's own USB CDC if02 path is separate).

Note: on a Pico **2 W** the onboard LED is on the CYW43 (WL_GPIO0), and
GPIO25 is WL_CS - firmware that "blinks GPIO25" does nothing visible.

## Flashing: always SWD + verify

`flash-arm` / `flash-smoke` run OpenOCD with `program ... verify`:

```
make flash-arm     # benchmark firmware
make flash-smoke   # UART-only diagnostic image (PING-9955 every 100 ms)
```

First build OpenOCD once (RP2350 support is not in distro 0.12.0):

```
./scripts/setup_openocd.sh          # installs to ~/.local/opt/openocd-rp2350
```

If after a reboot OpenOCD says `unable to find a matching CMSIS-DAP device`
while the probe is plugged in: the kernel HID helper modules are not loaded
(the probe's DAP interface is software-hidden from udev; the CDC serial still
enumerates). Fix with:

```
sudo modprobe hid_generic usbhid    # then unplug + replug the probe
sudo systemctl restart systemd-modules-load.service   # optional
```

Without a verified flash, prefer `make flash-arm` over BOOTSEL drag-and-drop:
BOOTSEL copies have repeatedly written flash **only partway** in this project,
leaving the tail of the image erased (`0xffffffff`). The board then executes
code with a blank literal pool/`.rodata` and either faults into the vector
table's `_hang` handler or emits garbage - symptoms which cost a long bisection
here before SWD exposed them. `program ... verify` makes writes self-checking.

OpenOCD success markers: `** Programming Finished **`, `** Verify Started **`,
`** Verified OK **`.

## Reading UART output

```
stty -F /dev/ttyACM3 115200 raw -echo clocal
timeout 30 cat /dev/ttyACM3 > /tmp/uart.log
```

Expected lines: the six `START_/END_{ARITHMETIC,ARRAY,BITWISE}_BENCHMARK`
markers, each `END_*` followed by `CYCLE_<BENCHMARK> <cycles>`, and one
`CLOCK_HZ 12000000` line before them. The firmware prints over UART0 GP0/GP1
at 115200 8N1 (12 MHz clk_peri, divisors IBRD=6/FBRD=33).

## Hardware cycle counts

`make measure-arm` flashes with verify, halt, start UART capture, reset+run, then parse the log with
`scripts/parse_hw_results.js` into `results/hardware_arm_{O2,Os}.json`.

The firmware times each benchmark with a cycle counter (`board_cycles_now()`
in `src/board.c`: SysTick at clk_sys on ARM, `mcycle` on RISC-V) and prints
the deltas. Timestamps are taken at the same points the simulator uses (just
after the last byte of the START/END markers), so the two tables are directly
comparable. Cycle counts are clock-independent; at the firmware's 12 MHz
clk_sys one cycle is 83.3 ns.

SysTick is also modeled by rp2350js, so the simulator run prints its own
`CYCLE_*` lines too - `make sim` still uses marker timing for its JSON, so
simulator results are unchanged by this.

## Live debugging

```
cd ~/.local/opt/openocd-rp2350
src/openocd -f tcl/interface/cmsis-dap.cfg -f tcl/target/rp2350.cfg -s tcl \
    -c "adapter speed 5000" -c init -c "targets rp2350.cm0" \
    -c "halt" -c "reg pc lr sp xpsr" -c "mdw 0x10000000 16" -c shutdown
```

Symbolize faulting PCs with:

```
arm-none-eabi-addr2line -e build_arm/arm_O2.elf -f -p -a <pc> <lr>
```

The vector table (src/startup_arm.c) fills NMI/HardFault/SVC/SysTick entries
with a `_hang` loop; halting the board and finding `pc` inside `_hang` means
an exception occurred - inspect the fault frame on the stack (`mdw` at `msp`)
and symbolize the frame pc/lr.

## Debug builds

- `make arm` - benchmark firmware, -O2 and -Os, UF2/ELF in `build_arm/`.
- `make smoke-arm` - `arm_smoke_O2`: `board_init()` only, then a `PING-9955`
  line every ~100 ms, no benchmarks. Use it whenever a board goes silent: it
  isolates clock/pad/UART bring-up from the benchmark.
- `make measure-arm` adds real results to `make compare`.
