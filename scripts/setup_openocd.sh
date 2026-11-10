#!/usr/bin/env sh
# Build the Raspberry Pi fork of OpenOCD, the only version with RP2350 target
# support (distro 0.12.0 only knows RP2040). Installs to
# ~/.local/opt/openocd-rp2350 by default (survives reboots); pass a different
# directory as $1. Roughly 2-5 minutes; the script skips work if already built.
set -e

install_dir=${1:-$HOME/.local/opt/openocd-rp2350}

if [ -x "$install_dir/src/openocd" ]; then
    echo "Already built: $install_dir/src/openocd"
    echo "Usage: (cd $install_dir) src/openocd -f tcl/interface/cmsis-dap.cfg -f tcl/target/rp2350.cfg -s tcl ..."
    exit 0
fi

mkdir -p "$(dirname "$install_dir")"
git clone --depth 1 https://github.com/raspberrypi/openocd "$install_dir"
cd "$install_dir"
./bootstrap
./configure --enable-cmsis-dap --disable-werror
make -j"$(nproc)"

echo
echo "Built: $install_dir/src/openocd"
echo "Usage: (cd $install_dir) src/openocd -f tcl/interface/cmsis-dap.cfg -f tcl/target/rp2350.cfg -s tcl ..."
