#!/usr/bin/env bash
# Builds the TapDancer bootloader: upstream Adafruit nRF52 Bootloader 0.9.2
# plus the patches in ./patches.
#
# Usage:
#   ./build_bootloader.sh
#   CROSS_COMPILE=/path/to/arm-none-eabi- ./build_bootloader.sh
#
# Requirements: git, make, python3 with intelhex and adafruit-nrfutil,
# arm-none-eabi-gcc (in PATH or via CROSS_COMPILE).

set -euo pipefail

UPSTREAM_URL="https://github.com/adafruit/Adafruit_nRF52_Bootloader.git"
UPSTREAM_TAG="0.9.2"
BOARD="xiao_nrf52840_ble"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/_work"
SRC_DIR="${WORK_DIR}/Adafruit_nRF52_Bootloader"

if [ ! -d "${SRC_DIR}" ]; then
    echo "Cloning ${UPSTREAM_URL} @ ${UPSTREAM_TAG} ..."
    mkdir -p "${WORK_DIR}"
    git clone --branch "${UPSTREAM_TAG}" --depth 1 \
        --recurse-submodules --shallow-submodules \
        "${UPSTREAM_URL}" "${SRC_DIR}"

    echo "Applying patches ..."
    git -C "${SRC_DIR}" apply "${SCRIPT_DIR}"/patches/*.patch
else
    echo "Using existing checkout in ${SRC_DIR} (delete it for a clean build)"
fi

MAKE_ARGS=(BOARD="${BOARD}")
if [ -n "${CROSS_COMPILE:-}" ]; then
    MAKE_ARGS+=(CROSS_COMPILE="${CROSS_COMPILE}")
fi

make -C "${SRC_DIR}" "${MAKE_ARGS[@]}" all

echo
echo "Done. Output: ${SRC_DIR}/_build/build-${BOARD}/"
