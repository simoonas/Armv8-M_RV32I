#!/bin/sh
# Capture benchmark cycle counts from a real board over SWD + UART.
#
# Usage:
#   OPENOCD_DIR=... TTY=/dev/ttyACM3 sh scripts/measure_hw.sh <arch> <opt> [<opt> ...]
#
#   <arch> is "arm" or "riscv" and matches build_<arch>/ plus the CMake target
#   names (<arch>_O2, <arch>_Os, ...). Example: measure_hw.sh arm O2 Os
#
# For each optimisation level the image is flashed with verify, the core is
# left halted, a UART capture is started, the core is reset+run, and the log
# is parsed into results/hardware_<arch>_<opt>.json.
set -eu

if [ $# -lt 2 ]; then
    echo "Usage: OPENOCD_DIR=... TTY=... sh scripts/measure_hw.sh <arch> <opt> [<opt> ...]" >&2
    exit 1
fi

ARCH=$1
shift
OPENOCD_DIR=${OPENOCD_DIR:?set OPENOCD_DIR to the RP2350 OpenOCD build}
TTY=${TTY:?set TTY to the Debug Probe UART device}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

case "$ARCH" in
    arm) ARCH_LABEL=ARM ;;
    riscv) ARCH_LABEL=RISC-V ;;
    *) echo "Unknown arch: $ARCH" >&2; exit 1 ;;
esac

openocd_run() {
    ( cd "$OPENOCD_DIR" && timeout 90 src/openocd \
        -f tcl/interface/cmsis-dap.cfg -f tcl/target/rp2350.cfg -s tcl \
        -c "adapter speed 5000" -c init "$@" )
}

mkdir -p "$ROOT/results"

for OPT in "$@"; do
    ELF="$ROOT/build_$ARCH/${ARCH}_${OPT}.elf"
    UF2="build_$ARCH/${ARCH}_${OPT}.uf2"
    LOG="$ROOT/results/uart_hw_${ARCH}_${OPT}.log"

    if [ ! -f "$ELF" ]; then
        echo "Missing $ELF - build it first (make $ARCH)" >&2
        exit 1
    fi

    echo "== $ARCH_LABEL -$OPT: flashing $ELF =="
    openocd_run -c "program $ELF verify" -c "reset halt" -c shutdown

    echo "== $ARCH_LABEL -$OPT: capturing UART =="
    stty -F "$TTY" 115200 raw -echo clocal
    ( timeout 6 cat "$TTY" > "$LOG" ) &
    CAT_PID=$!
    sleep 0.3
    openocd_run -c "reset run" -c shutdown
    wait "$CAT_PID" || true

    node "$ROOT/scripts/parse_hw_results.js" "$LOG" \
        --arch "$ARCH_LABEL" --opt "-$OPT" --firmware "$UF2" \
        --clock-hz 12000000 --board "Raspberry Pi Pico 2 W"
done
