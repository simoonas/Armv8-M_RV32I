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

# Build the same programme once per optimisation level, producing
#   <arch>_O2.elf / <arch>_O2.bin / <arch>_O2.uf2
#   <arch>_Os.elf / <arch>_Os.bin / <arch>_Os.uf2
foreach(opt O2 Os)
  set(tgt ${BIN_PREFIX}_${opt})

  add_executable(${tgt} ${STARTUP} src/main.c)
  set_target_properties(${tgt} PROPERTIES SUFFIX .elf)

  target_compile_options(${tgt} PRIVATE ${COMMON_C_FLAGS} -${opt})
  target_link_options(${tgt} PRIVATE
    -nostdlib
    -T ${CMAKE_SOURCE_DIR}/${LDSCRIPT}
    -Wl,--gc-sections
    -lgcc
  )

  add_custom_command(TARGET ${tgt} POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary
            $<TARGET_FILE:${tgt}>
            ${CMAKE_CURRENT_BINARY_DIR}/${tgt}.bin
    COMMAND python3 ${CMAKE_SOURCE_DIR}/scripts/elf2uf2.py
            ${CMAKE_CURRENT_BINARY_DIR}/${tgt}.bin
            ${CMAKE_CURRENT_BINARY_DIR}/${tgt}.uf2
    COMMENT "Generating ${tgt}.bin and ${tgt}.uf2"
    VERBATIM)
endforeach()