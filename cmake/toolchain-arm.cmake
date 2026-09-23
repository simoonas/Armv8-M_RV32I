# ARM (Cortex-M33) cross-compile toolchain for the RP2350.
#
# Configure with:
#   cmake -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain-arm.cmake ..
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR cortex-m33)

set(ARCH arm CACHE STRING "Target architecture" FORCE)
set(BINUTILS_PREFIX arm-none-eabi-)
set(CMAKE_C_COMPILER arm-none-eabi-gcc)

find_program(CMAKE_OBJCOPY NAMES arm-none-eabi-objcopy REQUIRED)

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(
  COMMON_C_FLAGS
  "-mcpu=cortex-m33 -mthumb -mfloat-abi=soft -ffreestanding -ffunction-sections -fdata-sections -Wall -Wextra"
  CACHE STRING "Common compile flags" FORCE
)