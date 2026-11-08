# RISC-V (Hazard3) cross-compile toolchain for the RP2350.
#
# The RP2350 RISC-V core implements rv32imc (+Zicsr/Zca). Point CMAKE_C_COMPILER
# at a supported RISC-V bare-metal GCC toolchain and configure with:
#   cmake -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain-riscv.cmake ..

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR rv32imc)

set(ARCH riscv CACHE STRING "Target architecture" FORCE)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Find a supported RISC-V bare-metal GCC toolchain.
if(NOT CMAKE_C_COMPILER)
  find_program(
    CMAKE_C_COMPILER
    NAMES
      riscv64-elf-gcc
      riscv-none-elf-gcc
      riscv64-unknown-elf-gcc
      riscv32-elf-gcc
    REQUIRED
  )
endif()

# Determine the prefix used by the installed toolchain.
get_filename_component(RISCV_GCC_NAME "${CMAKE_C_COMPILER}" NAME)

if(RISCV_GCC_NAME MATCHES "^riscv64-elf-gcc$")
  set(BINUTILS_PREFIX riscv64-elf-)
elseif(RISCV_GCC_NAME MATCHES "^riscv-none-elf-gcc$")
  set(BINUTILS_PREFIX riscv-none-elf-)
elseif(RISCV_GCC_NAME MATCHES "^riscv64-unknown-elf-gcc$")
  set(BINUTILS_PREFIX riscv64-unknown-elf-)
elseif(RISCV_GCC_NAME MATCHES "^riscv32-elf-gcc$")
  set(BINUTILS_PREFIX riscv32-elf-)
else()
  message(FATAL_ERROR "Unsupported RISC-V compiler: ${RISCV_GCC_NAME}")
endif()

find_program(
  CMAKE_OBJCOPY
  NAMES ${BINUTILS_PREFIX}objcopy
  REQUIRED
)

set(
  COMMON_C_FLAGS
  "-march=rv32imc -mabi=ilp32 -ffreestanding -ffunction-sections -fdata-sections -Wall -Wextra"
  CACHE STRING "Common compile flags" FORCE
)

set(
  CMAKE_EXE_LINKER_FLAGS
  "-march=rv32imc -mabi=ilp32"
  CACHE STRING "RISC-V linker flags" FORCE
)