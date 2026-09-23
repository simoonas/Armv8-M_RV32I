# RISC-V (Hazard3) cross-compile toolchain for the RP2350.
#
# The RP2350 RISC-V core implements rv32imc (+Zicsr/Zca). Point CMAKE_C_COMPILER
# at whatever riscv bare-metal gcc you have installed (e.g. on Arch:
# `yay -S riscv32-elf-gcc`, or riscv64-unknown-elf-gcc) and configure with:
#   cmake -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain-riscv.cmake ..
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR rv32imc)

set(ARCH riscv CACHE STRING "Target architecture" FORCE)

# Try a few common bare-metal RISC-V toolchain names; override with
# -DCMAKE_C_COMPILER=/path/to/riscv32-elf-gcc if yours differs.
if(NOT CMAKE_C_COMPILER)
  set(CMAKE_C_COMPILER riscv-none-elf-gcc)
endif()
set(BINUTILS_PREFIX riscv-none-elf-)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

find_program(CMAKE_OBJCOPY NAMES ${BINUTILS_PREFIX}objcopy riscv32-elf-objcopy riscv64-unknown-elf-objcopy REQUIRED)

set(
  COMMON_C_FLAGS
  "-march=rv32imc -mabi=ilp32 -ffreestanding -ffunction-sections -fdata-sections -Wall -Wextra"
  CACHE STRING "Common compile flags" FORCE
)