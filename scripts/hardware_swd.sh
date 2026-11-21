#!/bin/sh
# Measure benchmark cycle counts on a real board over SWD only (no UART needed).
#
# Usage:
#   OPENOCD_BIN=... OPENOCD_SCRIPTS=... NM=... sh scripts/hardware_swd.sh <arch> [<opt> ...]
#
#   <arch> is "arm" or "riscv". Without explicit <opt> arguments every built benchmark
#   image in build_<arch>/ is measured (O0 O1 O2 O3 Os Oz if they were built).
#   NM is the nm of that architecture's toolchain; `make hardware` passes it.
#
# The firmware (src/main.c) keeps its results in the `bench_results` struct in RAM.
# For each image this script:
#   run 1: program + verify, reset halt, clear `done`, resume
#   (wait RUN_WAIT seconds for the benchmarks to finish)
#   run 2: halt, read the five words with `mdw`
# and then parses the OpenOCD log into results/hardware_<arch>_<opt>.json.
set -eu

if [ $# -lt 1 ]; then
    echo "Usage: OPENOCD_BIN=... OPENOCD_SCRIPTS=... NM=... sh scripts/hardware_swd.sh <arch> [<opt> ...]" >&2
    exit 1
fi

ARCH=$1
shift
OPENOCD_BIN=${OPENOCD_BIN:?set OPENOCD_BIN to the RP2350-capable OpenOCD binary}
OPENOCD_SCRIPTS=${OPENOCD_SCRIPTS:?set OPENOCD_SCRIPTS to the OpenOCD scripts directory}
OPENOCD_TIMEOUT=${OPENOCD_TIMEOUT-}
NM=${NM:?set NM to the toolchain nm for this architecture (make hardware passes it)}
RUN_WAIT=${RUN_WAIT:-2}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

case "$ARCH" in
    arm) ARCH_LABEL=ARM ;;
    riscv) ARCH_LABEL=RISC-V ;;
    *) echo "Unknown arch: $ARCH" >&2; exit 1 ;;
esac

# If no levels were given, measure every benchmark image that was built.
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

# Show the end of the OpenOCD log and stop.
fail_with_log() {
    echo "$1 - last lines of $2:" >&2
    tail -n 15 "$2" >&2
    exit 1
}

mkdir -p "$ROOT/results"

for OPT in "$@"; do
    ELF="$ROOT/build_$ARCH/${ARCH}_${OPT}.elf"
    UF2="build_$ARCH/${ARCH}_${OPT}.uf2"
    LOG="$ROOT/results/swd_hw_${ARCH}_${OPT}.log"

    if [ ! -f "$ELF" ]; then
        echo "Missing $ELF - build it first (make $ARCH)" >&2
        exit 1
    fi

    # The struct's address changes between optimisation levels, so we look it
    # up in every image.
    SYM=$("$NM" "$ELF" | awk '$3 == "bench_results" { print $1; exit }')
    if [ -z "$SYM" ]; then
        echo "No bench_results symbol in $ELF - rebuild it (make $ARCH)" >&2
        exit 1
    fi
    ADDR=$(printf '0x%08x' $((0x$SYM)))
    DONE_ADDR=$(printf '0x%08x' $((0x$SYM + 4)))

    echo "== $ARCH_LABEL -$OPT: flashing $UF2 (bench_results at $ADDR) =="
    # RAM keeps its contents across a reset, so clear `done` before starting:
    # otherwise a crashed run could show the previous image's results.
    openocd_run -c "program $ELF verify" -c "reset halt" -c "mww $DONE_ADDR 0" \
        -c resume -c shutdown > "$LOG" 2>&1 \
        || fail_with_log "Flashing failed" "$LOG"

    echo "== $ARCH_LABEL -$OPT: running for ${RUN_WAIT}s, then reading results =="
    sleep "$RUN_WAIT"
    openocd_run -c halt -c "mdw $ADDR 5" -c shutdown >> "$LOG" 2>&1 \
        || fail_with_log "Reading the results failed" "$LOG"

    node "$ROOT/scripts/parse_hw_results.js" "$LOG" --swd-address "$ADDR" \
        --arch "$ARCH_LABEL" --opt "-$OPT" --firmware "$UF2" \
        --clock-hz 12000000 --board "Raspberry Pi Pico 2 W" \
        || fail_with_log "No valid results" "$LOG"
done