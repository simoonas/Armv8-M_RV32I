# Armv8-M vs RISC-V RP2350

Compile small C program for RP2350's 2 CPU architectures (ARM Cortex-M33, RISC-V Hazard3) and compare results:

- Binary size at `-O2` and `-Os` (flash/RAM footprint)
- Cycle count reported by [rp2350js](tools/rp2350js) while it runs produced UF2 images from `START_BENCHMARK` to `END_BENCHMARK`

builds are bare metal (own startup code + linker scripts), small and the architecture comparison is clean.

## Clone
`git clone --recursive https://github.com/simoonas/Armv8-M_RV32I`
## Install toolchains (Arch)

### ARM
`sudo pacman -S arm-none-eabi-gcc arm-none-eabi-newlib cmake base-devel`
### RISC-V
`yay -S riscv32-elf-gcc riscv32-elf-newlib`

RISC-V targets are skipped if none of these toolhains is installed:
- `riscv32-elf-gcc`
- `riscv-none-elf-gcc`
- `riscv64-unknown-elf-gcc`)

## Usage

Everything is in the toplevel Makefile:

- `make arm` builds `build_arm/arm_O2.{elf,bin,uf2}` and `build_arm/arm_Os.{elf,bin,uf2}` (Cortex-M33)
- `make riscv` same for `build_riscv/riscv_*` when a RISC-V toolchain present
- `make` / `make all` ARM + RISC-V
- `make sim` runs every produced `.uf2` through rp2350js, prints cycle count between START/END markers, UART output
- `make compare` prints the size table (uses `pyelftools` or `llvm-size`/`*-size` if `pyelftools` isn't installed) 
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
- `tools/rp2350js` git submodule of the simulator.
