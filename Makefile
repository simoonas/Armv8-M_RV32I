# Convenience wrapper around the per-architecture CMake cross-builds.
#
#   make            build every available toolchain (arm [+riscv])
#   make sim        run every built image through the rp2350js emulator
#   make compare    print the ELF size comparison table (pyelftools)
#   make clean      remove build directories

.PHONY: all arm riscv sim compare clean

all: arm riscv

arm:
	@if command -v arm-none-eabi-gcc >/dev/null 2>&1; then \
		printf '== Building ARM (Cortex-M33) -O2 and -Os ==\n'; \
		mkdir -p build_arm; \
		cd build_arm && cmake -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain-arm.cmake ..; \
		$(MAKE); \
	else \
		printf 'Skipping ARM: arm-none-eabi-gcc not found\n'; \
	fi

riscv:
	@if command -v riscv-none-elf-gcc >/dev/null 2>&1 || command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 || command -v riscv32-elf-gcc >/dev/null 2>&1; then \
		printf '== Building RISC-V (Hazard3) -O2 and -Os ==\n'; \
		mkdir -p build_riscv; \
		cd build_riscv && cmake -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain-riscv.cmake ..; \
		$(MAKE); \
	else \
		printf 'Skipping RISC-V: no riscv bare-metal toolchain found (e.g. riscv32-elf-gcc)\n'; \
	fi

sim: arm riscv
	@for uf2 in build_arm/arm_O2.uf2 build_arm/arm_Os.uf2 build_riscv/riscv_O2.uf2 build_riscv/riscv_Os.uf2; do \
		if [ -f "$$uf2" ]; then \
			printf '\n=== %s ===\n' "$$uf2"; \
			node scripts/run_sim.js "$$uf2"; \
		fi; \
	done

compare: arm riscv
	@python3 scripts/parse_elf.py build_arm/arm_O2.elf build_arm/arm_Os.elf build_riscv/riscv_O2.elf build_riscv/riscv_Os.elf 2>/dev/null || \
		python3 scripts/parse_elf.py build_arm/arm_O2.elf build_arm/arm_Os.elf

clean:
	rm -rf build_arm build_riscv