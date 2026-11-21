# Convenience wrapper around the per-architecture CMake cross-builds.
#
#   make                    build every available toolchain (arm, riscv)
#   make sim                run every built image through the rp2350js simulator
#   make hardware           build, run every image on the real board, read the
#                           results over SWD and print the tables
#   make compare            print the code size and cycle count tables
#   make clean              remove build directories and benchmark results
#
# Smaller board tools (SWD, build beforehand):
#   make flash-arm          flash and verify the ARM benchmark
#   make flash-riscv        same for RISC-V
#   make halt-arm           halt ARM core 0 and print some registers
#   make halt-riscv         same for RISC-V
#
# Optional, only with the probe's UART wired up:
#   make uart               show the board's serial output
#   make flash-smoke-arm    flash the PING-only UART test for ARM
#   make flash-smoke-riscv  same for RISC-V
#   make measure-arm        flash every built optimisation level, save board cycle counts in results/
#   make measure-riscv      same for RISC-V

FLASH_TARGETS = flash-arm flash-riscv flash-smoke-arm flash-smoke-riscv
HALT_TARGETS  = halt-arm halt-riscv
MEASURE_TARGETS = measure-arm measure-riscv

.PHONY: all arm riscv sim compare clean hardware hardware-help uart $(FLASH_TARGETS) $(HALT_TARGETS) $(MEASURE_TARGETS)

all: arm riscv

# ---- Build -------------------------------------------------------------------
# Helper for checking which of the listed programs is installed.
# Gives the path of the first one found, or nothing if none are.
find_tool = $(firstword $(foreach t,$(1),$(shell command -v $(t) 2>/dev/null)))

ARM_CC   = arm-none-eabi-gcc
RISCV_CC = riscv64-elf-gcc riscv-none-elf-gcc riscv64-unknown-elf-gcc riscv32-elf-gcc

# nm (lists the symbols in a program) is used by scripts/hardware_swd.sh.
ARM_NM   = $(patsubst %gcc,%nm,$(call find_tool,$(ARM_CC)))
RISCV_NM = $(patsubst %gcc,%nm,$(call find_tool,$(RISCV_CC)))

# Builds one architecture.
# If none of the compilers is installed, it prints a message and skips.
define build
@if [ -z "$(call find_tool,$(3))" ]; then \
	printf 'Skipping %s: no compiler found (looked for: %s)\n' '$(2)' '$(3)'; \
else \
	printf '== Building %s: benchmark images (all optimisation levels) + smoke ==\n' '$(2)'; \
	if [ ! -f build_$(1)/CMakeCache.txt ]; then \
		cmake -S . -B build_$(1) -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-$(1).cmake || exit 1; \
	fi; \
	$(MAKE) --no-print-directory -C build_$(1); \
fi
endef

arm:
	$(call build,arm,ARM (Cortex-M33),$(ARM_CC))

riscv:
	$(call build,riscv,RISC-V (Hazard3),$(RISCV_CC))

# ---- Simulator ---------------------------------------------------------------
sim:
	@node scripts/run_sim.js --all

# ---- Board (SWD) -------------------------------------------------------------
# Everything here talks to the board through the Debug Probe's SWD wires,
# using OpenOCD.

# Which OpenOCD to use. The first one found wins:
#   1. ~/.local/opt/openocd-rp2350 (built by scripts/setup_openocd.sh)
#   2. the newest ~/.pico-sdk/openocd/*/openocd
#   3. openocd on PATH
# The pico-sdk build can be missing shared libraries (like libjim) on some systems, hence the repo-built one is preferred.
OPENOCD =$(or $(wildcard $(HOME)/.local/opt/openocd-rp2350/src/openocd), \
                $(shell ls -d $(HOME)/.pico-sdk/openocd/*/openocd 2>/dev/null | sort -V | tail -n 1), \
                openocd)
OPENOCD_BIN = $(shell command -v $(OPENOCD) 2>/dev/null)

# Finds the folder with OpenOCD's config files, or nothing.
OPENOCD_SCRIPTS = $(abspath $(patsubst %/target/rp2350.cfg,%,$(firstword $(wildcard \
	$(dir $(OPENOCD_BIN))scripts/target/rp2350.cfg \
	$(dir $(OPENOCD_BIN))../tcl/target/rp2350.cfg \
	$(dir $(OPENOCD_BIN))../share/openocd/scripts/target/rp2350.cfg))))

# Stop a hung OpenOCD after 90 s.
TIMEOUT = $(call find_tool,timeout gtimeout)

OPENOCD_RUN = $(if $(TIMEOUT),$(TIMEOUT) 90 )$(OPENOCD_BIN) -s $(OPENOCD_SCRIPTS) \
	-f $(CURDIR)/pico2.cfg -c init -c use_running_core

# "arm" or "riscv": the last word of the target name.
goal_arch = $(lastword $(subst -, ,$@))

# What the board scripts (`hardware_swd.sh` and `measure_hw.sh`) need to know about OpenOCD.
OPENOCD_ENV = OPENOCD_BIN="$(OPENOCD_BIN)" OPENOCD_SCRIPTS="$(OPENOCD_SCRIPTS)" \
	OPENOCD_TIMEOUT="$(if $(TIMEOUT),$(TIMEOUT) 90,)"


# Main entry: the hardware twin of `make sim`. scripts/hardware_swd.sh flashes
# each benchmark image, lets it run, reads the `bench_results` struct from RAM
# over SWD and saves results/hardware_<arch>_<opt>.json.
hardware:
	@for arch in arm riscv; do \
		ls build_$$arch/$${arch}_O*.elf >/dev/null 2>&1 || \
			{ printf 'No benchmark images in build_%s - run: make %s\n' $$arch $$arch; exit 1; }; \
	done
	@$(OPENOCD_ENV) NM="$(ARM_NM)" sh scripts/hardware_swd.sh arm
	@$(OPENOCD_ENV) NM="$(RISCV_NM)" sh scripts/hardware_swd.sh riscv

# Flash over SWD, always with `program ... verify`: BOOTSEL drag-and-drop has
# been seen to write only part of the flash, leaving a silent board.
# flash-<arch> -> build_<arch>/<arch>_$(OPT).elf
# flash-smoke-<arch> -> build_<arch>/<arch>_smoke_O2.elf
OPT ?= O2
flash_elf = $(CURDIR)/build_$(goal_arch)/$(goal_arch)_$(if $(findstring smoke,$@),smoke_O2,$(OPT)).elf

$(FLASH_TARGETS):
	@test -f $(flash_elf) || { printf 'Missing %s (no toolchain?)\n' $(flash_elf); exit 1; }
	$(OPENOCD_RUN) -c "program $(flash_elf) verify" -c "reset run" -c shutdown

# Halt core 0 and print a few registers, e.g. to see where a silent board
# is stuck. Only works for the architecture the chip is running.
HALT_CORE_arm   = rp2350.cm0
HALT_REGS_arm   = pc lr sp xpsr r0 r1
HALT_CORE_riscv = rp2350.rv0
HALT_REGS_riscv = pc ra sp a0 a1

$(HALT_TARGETS):
	$(OPENOCD_RUN) -c "targets $(HALT_CORE_$(goal_arch))" -c halt \
		$(foreach r,$(HALT_REGS_$(goal_arch)),-c "reg $(r)") -c shutdown

# ---- Board (UART, optional) --------------------------------------------------
# Only usable with the Debug Probe's UART wired to GP0 (TX) / GP1 (RX).
# The flash-smoke-* targets (in the flashing rule above) flash a program that
# only prints PING over UART.

# The probe's serial port, 115200 8N1. Pick one with TTY=...
# Linux: the probe's stable /dev/serial/by-id/ link.
# macOS: the probe shows up as /dev/cu.usbmodem<serial number><n>.
TTY ?= $(firstword $(wildcard /dev/serial/by-id/usb-Raspberry_Pi_Debug_Probe__CMSIS-DAP__*-if01) \
                   $(wildcard /dev/cu.usbmodem*))

uart:
	@if [ -z "$(TTY)" ]; then \
		printf '%s\n' \
		'No Debug Probe serial port found. Is the probe plugged in?'; \
		exit 1; fi
	@printf 'Reading %s at 115200 baud (Ctrl-C to stop)\n' '$(TTY)'
	@{ stty 115200 raw -echo clocal; cat; } < '$(TTY)'

# Cycle counts over UART: scripts/measure_hw.sh flashes each built benchmark
# image, captures the UART output and saves results/hardware_<arch>_<opt>.json
# for make compare.
$(MEASURE_TARGETS):
	$(OPENOCD_ENV) TTY="$(TTY)" sh scripts/measure_hw.sh $(goal_arch)

# ---- Compare -----------------------------------------------------------------
compare:
	@printf "\n== Code size comparison ==\n"
	@python3 scripts/parse_elf.py $$(ls build_arm/arm_O*.elf build_riscv/riscv_O*.elf 2>/dev/null) 2>/dev/null || \
	python3 scripts/parse_elf.py $$(ls build_arm/arm_O*.elf 2>/dev/null)
	@printf "\n== Benchmark cycle comparison ==\n"
	@node scripts/compare_results.js

# ---- Clean -------------------------------------------------------------------
clean:
	@rm -rf build_arm build_riscv results
	@printf "Removed build and result directories\n"
