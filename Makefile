# Convenience wrapper around the per-architecture CMake cross-builds.
#
#   make            build every available toolchain (arm [+riscv])
#   make sim        run every built image through the rp2350js emulator
#   make compare    print the ELF size comparison table (pyelftools) and cycle comparison table
#   make clean      remove build directories and benchmark results

.PHONY: all arm riscv smoke-arm flash-arm flash-smoke uart halt-cm0 sim hardware compare clean

all: arm riscv

arm:
	@if command -v arm-none-eabi-gcc >/dev/null 2>&1; then \
		printf '== Building ARM (Cortex-M33) -O2 and -Os ==\n'; \
		mkdir -p build_arm; \
		cd build_arm && { \
    		if [ ! -f CMakeCache.txt ]; then \
        		cmake -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain-arm.cmake ..; \
    		else \
        		cmake ..; \
    		fi; \
		}; \
		$(MAKE); \
	else \
		printf 'Skipping ARM: arm-none-eabi-gcc not found\n'; \
	fi

riscv:
	@if command -v riscv64-elf-gcc >/dev/null 2>&1 || command -v riscv-none-elf-gcc >/dev/null 2>&1 || command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 || command -v riscv32-elf-gcc >/dev/null 2>&1; then \
		printf '== Building RISC-V (Hazard3) -O2 and -Os ==\n'; \
		mkdir -p build_riscv; \
		cd build_riscv && { \
    		if [ ! -f CMakeCache.txt ]; then \
        		cmake -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain-riscv.cmake ..; \
    		else \
        		cmake ..; \
    		fi; \
		}; \
		$(MAKE); \
	else \
		printf 'Skipping RISC-V: no riscv bare-metal toolchain found (e.g. riscv32-elf-gcc)\n'; \
	fi

sim: arm riscv
	node scripts/run_sim.js --all

smoke-arm:
	@if command -v arm-none-eabi-gcc >/dev/null 2>&1; then \
		mkdir -p build_arm; \
		cd build_arm && { \
    		if [ ! -f CMakeCache.txt ]; then \
        		cmake -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain-arm.cmake ..; \
    		else \
        		cmake ..; \
    		fi; \
		}; \
		$(MAKE) arm_smoke_O2; \
		printf 'Smoke image: build_arm/arm_smoke_O2.uf2\n'; \
	else \
		printf 'Skipping smoke: arm-none-eabi-gcc not found\n'; \
	fi

# OpenOCD invocation. scripts/setup_openocd.sh builds the Raspberry Pi fork
# (the only RP2350-capable version); OPENOCD_DIR auto-finds ~/.local/opt by
# default and falls back to the legacy /tmp/opencode location, override freely.
OPENOCD_DIR ?= $(if $(wildcard $(HOME)/.local/opt/openocd-rp2350/src/openocd),$(HOME)/.local/opt/openocd-rp2350,/tmp/opencode/openocd-rp2350)
OPENOCD_OK = $(shell test -x "$(OPENOCD_DIR)/src/openocd" && echo yes)
OPENOCD_PRECHECK = if [ "$(OPENOCD_OK)" != yes ]; then \
	printf 'No OpenOCD at %s/src/openocd\nRun: ./scripts/setup_openocd.sh\n' "$(OPENOCD_DIR)"; exit 1; fi;
OPENOCD = cd $(OPENOCD_DIR) && timeout 90 src/openocd \
	-f tcl/interface/cmsis-dap.cfg -f tcl/target/rp2350.cfg -s tcl \
	-c "adapter speed 5000" -c init

# Flash over SWD (Debug Probe on the Pico's DEBUG pads) and verify.
# ALWAYS uses program ... verify: BOOTSEL drag-and-drop has been observed to
# write flash only partway, leaving a silent board.
# Targets depend on the build so flashing never runs with stale images.
flash-arm: arm
	@$(OPENOCD_PRECHECK) \
	$(OPENOCD) \
		-c "program $(CURDIR)/build_arm/arm_O2.elf verify" \
		-c "reset run" -c shutdown

flash-smoke: smoke-arm
	@$(OPENOCD_PRECHECK) \
	$(OPENOCD) \
		-c "program $(CURDIR)/build_arm/arm_smoke_O2.elf verify" \
		-c "reset run" -c shutdown

# Serial monitor for the Debug Probe's UART bridge. AUTO_TTY resolves
# /dev/ttyACM3-style names automatically from the stable by-id link.
AUTO_TTY = $(firstword $(wildcard /dev/serial/by-id/usb-Raspberry_Pi_Debug_Probe__CMSIS-DAP__*-if01))
TTY ?= $(if $(AUTO_TTY),$(AUTO_TTY),/dev/ttyACM3)

uart:
	@stty -F $(TTY) 115200 raw -echo clocal
	@cat $(TTY)

halt-cm0:
	@$(OPENOCD_PRECHECK) \
	$(OPENOCD) -c "targets rp2350.cm0" -c "halt" \
		-c "reg pc lr sp xpsr" -c "reg r0 r1" -c shutdown

hardware: arm riscv
	@echo "Build complete. Firmware binaries (ready for flashing):"
	@echo "  ARM   : build_arm/arm_O2.uf2   build_arm/arm_Os.uf2"
	@echo "  RISC-V: build_riscv/riscv_*.uf2 (if a RISC-V toolchain was found)"
	@echo
	@echo "One-time setup (builds RP2350-capable OpenOCD into /tmp/opencode/openocd-rp2350):"
	@echo "  ./scripts/setup_openocd.sh"
	@echo
	@echo "Flash + monitor (Debug Probe: SWD on DEBUG pads, UART on pins 1-3):"
	@echo "  make flash-arm     build + SWD-flash + verify the benchmark firmware"
	@echo "  make flash-smoke   build + flash the PING-only diagnostic image"
	@echo "  make uart          stream UART output (Ctrl-C to stop)"
	@echo "  make halt-cm0      halt core 0 over SWD and dump pc/lr/sp/regs"
	@echo
	@echo "Full details: docs/hardware-debugging.md"
	@echo "Note: cycle counts are only collected by the simulator (make sim)."

compare: sim
	@echo
	@echo
	@echo
	@echo
	@echo "\n== Code size comparison =="
	@python3 scripts/parse_elf.py build_arm/arm_O2.elf build_arm/arm_Os.elf build_riscv/riscv_O2.elf build_riscv/riscv_Os.elf 2>/dev/null || \
	python3 scripts/parse_elf.py build_arm/arm_O2.elf build_arm/arm_Os.elf
	@echo "\n== Benchmark cycle comparison =="
	node scripts/compare_results.js

clean:
	rm -rf build_arm build_riscv results
