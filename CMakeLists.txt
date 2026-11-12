cmake_minimum_required(VERSION 3.13)
project(arm_vs_riscv_benchmark C)

# The cross toolchain files (cmake/toolchain-<arch>.cmake) define ARCH,
# BINUTILS_PREFIX, COMMON_C_FLAGS and CMAKE_C_COMPILER. One architecture per
# build directory: build_arm/ and build_riscv/.
if(NOT DEFINED ARCH)
  message(FATAL_ERROR
    "ARCH is not set. Configure with -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain-<arch>.cmake (see Makefile).")
endif()

if(ARCH STREQUAL "arm")
  set(BIN_PREFIX arm)
  set(STARTUP src/startup_arm.c)
  set(LDSCRIPT link/rp2350_arm.ld)
elseif(ARCH STREQUAL "riscv")
  set(BIN_PREFIX riscv)
  set(STARTUP src/startup_riscv.c)
  set(LDSCRIPT link/rp2350_riscv.ld)
else()
  message(FATAL_ERROR "Unknown ARCH '${ARCH}'. Expected 'arm' or 'riscv'.")
endif()

# Split COMMON_C_FLAGS (a single string from the toolchain file) into args.
separate_arguments(COMMON_C_FLAGS UNIX_COMMAND "${COMMON_C_FLAGS}")

# add_firmware(<name> <opt> <sources...>)
# Builds <name>.elf from the given sources at optimisation level -<opt>, then
# converts it to <name>.bin (raw bytes) and <name>.uf2 (for drag-and-drop
# flashing). Every image in this project goes through here.
function(add_firmware name opt)
  add_executable(${name} ${ARGN})
  set_target_properties(${name} PROPERTIES SUFFIX .elf)

  target_compile_options(${name} PRIVATE ${COMMON_C_FLAGS} -${opt})
  target_link_options(${name} PRIVATE
    -nostdlib
    -T ${CMAKE_SOURCE_DIR}/${LDSCRIPT}
    -Wl,--gc-sections
    -lgcc
  )

  add_custom_command(TARGET ${name} POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary
            $<TARGET_FILE:${name}>
            ${CMAKE_CURRENT_BINARY_DIR}/${name}.bin
    COMMAND python3 ${CMAKE_SOURCE_DIR}/scripts/elf2uf2.py
            ${CMAKE_CURRENT_BINARY_DIR}/${name}.bin
            ${CMAKE_CURRENT_BINARY_DIR}/${name}.uf2
            ${ARCH}
    COMMENT "Generating ${name}.bin and ${name}.uf2"
    VERBATIM)
endfunction()

# The benchmark programme, once per optimisation level:
#   <arch>_O2.elf / .bin / .uf2   and   <arch>_Os.elf / .bin / .uf2
foreach(opt O2 Os)
  add_firmware(${BIN_PREFIX}_${opt} ${opt} ${STARTUP} src/board.c src/main.c)
endforeach()

# UART smoke test: board_init() + a repeating "PING-9955" line, nothing else.
# Used to check the board bring-up and serial wiring on real hardware.
#   <arch>_smoke_O2.elf / .bin / .uf2
add_firmware(${BIN_PREFIX}_smoke_O2 O2 ${STARTUP} src/board.c src/uart_smoke.c)
