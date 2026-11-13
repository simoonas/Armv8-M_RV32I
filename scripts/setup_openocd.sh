#!/usr/bin/env sh
# Get an OpenOCD that can flash the RP2350. Only Raspberry Pi's fork has the
# RP2350 target files; distro/Homebrew OpenOCD 0.12.0 only knows RP2040.
#
#   macOS: downloads Raspberry Pi's ready-made build (the same one the Pico
#          VS Code extension installs) to ~/.pico-sdk/openocd/0.12.0+dev.
#          Takes a few seconds.
#   Linux: builds the fork from source in ~/.local/opt/openocd-rp2350.
#          Takes roughly 2-5 minutes.
set -e

if [ "$(uname -s)" = Darwin ]; then
    install_dir=${1:-$HOME/.pico-sdk/openocd/0.12.0+dev}

    if [ -x "$install_dir/openocd" ]; then
        echo "Already installed: $install_dir/openocd"
        exit 0
    fi

    url=https://github.com/raspberrypi/pico-sdk-tools/releases/download/v2.3.1-0/openocd-0.12.0%2Bdev-mac.zip

    echo "Downloading $url"
    mkdir -p "$install_dir"
    curl -fL --progress-bar -o "$install_dir.zip" "$url"
    unzip -q "$install_dir.zip" -d "$install_dir"
    rm "$install_dir.zip"

    echo
    echo "Installed: $install_dir/openocd"
    "$install_dir/openocd" --version 2>&1 | head -n 1
    exit 0
fi

install_dir=${1:-$HOME/.local/opt/openocd-rp2350}

if [ -x "$install_dir/src/openocd" ]; then
    echo "Already built: $install_dir/src/openocd"
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
echo "The Makefile finds it by itself."