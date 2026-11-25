# Bootloader

TapDancer uses the [Adafruit nRF52 Bootloader](https://github.com/adafruit/Adafruit_nRF52_Bootloader) **0.9.2** with one patch on top. Without it, BLE OTA updates to the Seeed XIAO nRF52840 do not work.

## Why a custom bootloader?

With the stock 0.9.2 bootloader, **every** OTA firmware update over BLE (Nordic Legacy DFU) failed. The root cause is the HCI RX buffer queue in `src/sdk_config.h`:

```c
#define HCI_RX_BUF_QUEUE_SIZE  8   // stock
#define HCI_RX_BUF_QUEUE_SIZE  16  // TapDancer
```

The DFU transfer sends packets faster than the bootloader can drain a queue of 8, so packets get dropped and the update aborts. With 16 buffers, OTA updates run reliably. The fix was found via upstream [issue #306](https://github.com/adafruit/Adafruit_nRF52_Bootloader/issues/306).

The change is kept as a patch instead of a vendored copy of the bootloader, so it is easy to see what differs from upstream: [`patches/0001-Increase-HCI_RX_BUF_QUEUE_SIZE-from-8-to-16.patch`](patches/0001-Increase-HCI_RX_BUF_QUEUE_SIZE-from-8-to-16.patch)

## Prebuilt binaries

Located in [`bin/`](bin/). The patched build is labeled `0.9.3-tapdancer` to tell it apart from the stock 0.9.2. It is not an official Adafruit release.

| File | Use |
|---|---|
| `xiao_nrf52840_ble_bootloader-0.9.3-tapdancer_s140_7.3.0.hex` | Bootloader + SoftDevice S140 7.3.0, flash via SWD |
| `update-xiao_nrf52840_ble_bootloader-0.9.3-tapdancer_nosd.uf2` | Bootloader self-update via drag and drop (UF2) |
| `xiao_nrf52840_ble_bootloader-0.9.3-tapdancer_s140_7.3.0.zip` | Bootloader + SoftDevice package for serial DFU (`adafruit-nrfutil`) |

## Flashing

**Option 1: UF2 (no debugger needed)**

1. Double-tap reset on the XIAO, a USB drive appears
2. Copy `update-xiao_nrf52840_ble_bootloader-0.9.3-tapdancer_nosd.uf2` onto it
3. The board flashes the new bootloader and restarts

**Option 2: PlatformIO "Burn Bootloader" (SWD debugger)**

The target `Burn Bootloader` in PlatformIO uses [`../tools/burn_bootloader.py`](../tools/burn_bootloader.py), which points `DFUBOOTHEX` to the `.hex` file in `bin/`.

## Building from source

```bash
pip install intelhex adafruit-nrfutil
./build_bootloader.sh
```

The script clones upstream at tag `0.9.2` (with submodules) into `_work/`, applies the patches and runs `make BOARD=xiao_nrf52840_ble all`. If `arm-none-eabi-gcc` is not in your `PATH`, pass the toolchain prefix, e.g. the one PlatformIO installs:

```bash
CROSS_COMPILE=~/.platformio/packages/toolchain-gccarmnoneeabi/bin/arm-none-eabi- ./build_bootloader.sh
```

On Windows, run it from Git Bash or WSL. The upstream Makefile calls `python3`, so that command must exist.

## Licenses

- Adafruit nRF52 Bootloader: MIT, see [`bin/LICENSE-Adafruit_nRF52_Bootloader`](bin/LICENSE-Adafruit_nRF52_Bootloader)
- Nordic SoftDevice S140 (contained in the merged `.hex` and `.zip`): Nordic 5-clause license, see [`bin/LICENSE-Nordic_S140_SoftDevice.txt`](bin/LICENSE-Nordic_S140_SoftDevice.txt)
