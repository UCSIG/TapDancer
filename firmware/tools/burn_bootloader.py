"""
Points the PlatformIO target 'Burn Bootloader' to the patched TapDancer
bootloader instead of the stock one shipped with the board package.

The bootloader is Adafruit nRF52 Bootloader 0.9.2 with
HCI_RX_BUF_QUEUE_SIZE raised from 8 to 16, which fixes BLE OTA updates.
Details: bootloader/README.md
"""

import os

Import("env")

bootloader_hex = os.path.join(
    env.subst("$PROJECT_DIR"),
    "bootloader",
    "bin",
    "xiao_nrf52840_ble_bootloader-0.9.3-tapdancer_s140_7.3.0.hex",
)

env.Replace(DFUBOOTHEX=bootloader_hex)
print("--------------------------------------------")
print("Burning bootloader:")
print(f"  '{bootloader_hex}'")
print("--------------------------------------------")
