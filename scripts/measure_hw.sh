#!/bin/sh
# Capture benchmark cycle counts from a real board over SWD + UART.
#
# Usage:
#   OPENOCD_BIN=... OPENOCD_SCRIPTS=... TTY=/dev/ttyACM3 sh scripts/measure_hw.sh <arch> [<opt> ...]
#
#   <arch> is "arm" or "riscv" and matches build_<arch>/ plus the CMake target
#   names (<arch>_O2, <arch>_Os, ...). Without explicit <opt> arguments every
#   built benchmark image for that architecture is measured, e.g.
#   `measure_hw.sh arm` measures O0 O1 O2 O3 Os Oz if they were built.
#
# For each optimisation level the image is flashed with verify, the core is
# left halted, a UART capture is started, the core is reset+run, and the log
# is parsed into results/hardware_<arch>_<opt>.json.
set -eu

if [ $# -lt 1 ]; then
    echo "Usage: OPENOCD_BIN=... OPENOCD_SCRIPTS=... TTY=... sh scripts/measure_hw.sh <arch> [<opt> ...]" >&2
    exit 1
fi

ARCH=$1
shift
OPENOCD_BIN=${OPENOCD_BIN:?set OPENOCD_BIN to the RP2350-capable OpenOCD binary}
OPENOCD_SCRIPTS=${OPENOCD_SCRIPTS:?set OPENOCD_SCRIPTS to the OpenOCD scripts directory}
OPENOCD_TIMEOUT=${OPENOCD_TIMEOUT-}
TTY=${TTY:?set TTY to the Debug Probe UART device}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

case "$ARCH" in
    arm) ARCH_LABEL=ARM ;;
    riscv) ARCH_LABEL=RISC-V ;;
    *) echo "Unknown arch: $ARCH" >&2; exit 1 ;;
esac

# if no levels, measure every benchmark image that was built
if [ $# -eq 0 ]; then
    set -- $(ls "$ROOT/build_$ARCH" 2>/dev/null | sed -n "s/^${ARCH}_\(O[A-Za-z0-9]*\)\.elf$/\1/p")
    if [ $# -eq 0 ]; then
        echo "No benchmark images in build_$ARCH - run: make $ARCH" >&2
        exit 1
    fi
fi

openocd_run() {
    ( cd "$ROOT" && $OPENOCD_TIMEOUT "$OPENOCD_BIN" -s "$OPENOCD_SCRIPTS" \
        -f "$ROOT/pico2.cfg" -c init -c use_running_core "$@" )
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
    stty 115200 raw -echo clocal < "$TTY"
    ( timeout 6 cat "$TTY" > "$LOG" ) &
    CAT_PID=$!
    sleep 0.3
    openocd_run -c "reset run" -c shutdown
    wait "$CAT_PID" || true

    node "$ROOT/scripts/parse_hw_results.js" "$LOG" \
        --arch "$ARCH_LABEL" --opt "-$OPT" --firmware "$UF2" \
        --clock-hz 12000000 --board "Raspberry Pi Pico 2 W"
done
