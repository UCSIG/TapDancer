/// @file main.h
///
/// @author UCSIG
/// @date March 03, 2024
///
/// Device ID        | BLE Name          | Connected  | Advertising + 3 LEDs  | Off     | Note   |  Runtime Connected @ 1200 mAh
/// ------------------------------------------------------------------------------------- ------ | -----------------------------
/// 17355FC028A926C7 | TapDancer 26C7 | 3.21 mA    | 10.36 mA              | 0.16 uA |        |  374 h - 15.59 d
/// BA6A6531CBF81A6B | TapDancer 1A6B | 3.22 mA    |                       | 0.22 uA |        |
/// 3139D62B4F076288 | TapDancer 6288 | 3.22 mA    | 10.05 mA              | 0.22 uA |        |
/// 4DA6436BCBCAF9A2 | TapDancer F9A2 | 3.55 mA    |                       | 0.01 uA | M      |
/// 3237D523A7B530FE | TapDancer 30FE | 3.82 mA    |                       | 3 uA    |        |
/// 75DD4EBCC1A2C4D8 | TapDancer C4D8 | 4.21 mA    |                       | 4 uA    |        |
///
/// Keycodes can be found here:
/// Adafruit_TinyUSB_Arduino/src/class/hid/hid.h
///
/// ADC low pass filtering:
///     - ~24kHz loop frequency.
//      - https://www.desmos.com/calculator/dlhszuyuae?lang=de
///
#ifndef H_MAIN
#define H_MAIN

#include "settings.h"
#include "build_info.h"
#include <stdint.h>

/* ---------------------------- FIRMWARE SETTINGS --------------------------- */
#define SOFTWARE_VERSION                           "1.5.0." BUILD_COUNT_STR
#define HARDWARE_REVISION                          "1.0.0"

/* -------------------------------- SETTINGS -------------------------------- */
/// [FLAG] Define debug mode, wait for serial port etc.
#define FLAG_DEBUG                                 (1)

/* ---------------------------- DISPLAY SETTINGS ---------------------------- */
/// [OPT] How long to display the battery level after startup using the leds in ms.
#define TIME_DISPLAY_BATTERY_VOLTAGE_MS            3000

/* ---------------------------- BATTERY SETTINGS ---------------------------- */
/// [OPT] Battery level thresholds.
#define BAT_FULL_MV                                4200.0f
#define BAT_3_THRSH_MV                             3600.0f
#define BAT_2_THRSH_MV                             3300.0f
#define BAT_1_THRSH_MV                             3100.0f
#define BAT_EMPTY_THRSH_MV                         2900.0f

/// [OPT] How often to measure the battery level in ms.
#define BAT_MEASUREMENT_INTERVAL_MS                100

/// [OPT] Voltage divider and adc settings.
#define VOLTAGE_DIVIDER_FACTOR                     2.0f
#define ADC_RANGE_OPT                              AR_INTERNAL_2_4
#define ADC_RANGE_MV                               2400.0f

/// [OPT] Filter the battery voltage using an ema filter.
#define BATTERY_FILTER_COEFFICIENT                 0.001f // 4 Hz

/* ----------------------------- CONFIG SETTINGS ---------------------------- */
/// [OPT] Filter the config voltage using an ema filter.
#define CONFIG_FILTER_COEFFICIENT                  0.001f // 4 Hz

/// [OPT] Duration of stable config measurements until a config is considered valid in ms.
#define CONFIG_STABLE_MS                           250

/* --------------------------------- TIMING --------------------------------- */
/// [OPT] Watchdog timeout in ms.
#define WATCHDOG_TIMEOUT_S                         3

/* ------------------------------ BLE SETTINGS ------------------------------ */
/// [OPT] Ble name options.
#define BLE_NAME                                   "TapDancer"
#define BLE_DEVICE_MANUFACTURER                    "UCSIG"

/// [OPT] Timeout after which a pairing process is terminated in s.
#define BLE_PAIRING_CONFIRMATION_TIMEOUT_S         ((uint32_t)30)

/// [OPT] Interval after which the advertising process is stopped in s.
#define BLE_FAST_ADVERTISING_TIMEOUT_S             ((uint32_t)15)
#define BLE_SECONDARY_DEVICE_ADVERTISING_TIMEOUT_S ((uint32_t)20)

/// [OPT] Timeout after which the process to delete bonding info is terminated in s.
#define BLE_TIMEOUT_DELETE_BONDING_INFO_S          ((uint32_t)30)

/// [OPT] Interval after which the connection is closed if not in range in ms.
#define BLE_SUPERVISION_TIMEOUT_MS                 ((uint32_t)1500)

/// [OPT] Interval of sending battery level to server in ms.
#define BLE_BATTERY_NOTIFY_INTERVAL_MS             ((uint32_t)2000)

/// [OPT] Number of times to repeat a key release.
#define BLE_REPEAT_KEY_RELEASE                     1

/// [OPT] Repeatedly release all keys in all connections to prevent unwanted key repeats.
#define BLE_KEY_RELEASE_PERIOD_MS                  ((uint32_t)UINT32_MAX)

/* ----------------------------- BUTTON SETTINGS ---------------------------- */
/// [OPT] Duration in ms to consider button pressed.
#define BUTTON_DEBOUNCE_MS                         30

/* ---------------------------------- PINS ---------------------------------- */
#define PRIMARY_BUTTON_PIN                         D3
#define PRIMARY_BUTTON_ACTIVE_LEVEL                LOW

#define SECONDARY_BUTTON_PIN                       D7
#define SECONDARY_BUTTON_ACTIVE_LEVEL              LOW

#define TERTIARY_BUTTON_PIN                        D6
#define TERTIARY_BUTTON_ACTIVE_LEVEL               LOW

#define PIN_CONFIG_R2R                             D4
#define PIN_POWER_EN                               D2
#define PIN_BATTERY_VOLT                           D0
#define PIN_VOLT_DIV_EN                            D1

#define PIN_LED_1                                  D10
#define PIN_LED_2                                  D9
#define PIN_LED_3                                  D8
#define LED_NUM                                    3

// Unconnected pin.
#define PIN_DEBUG                                  D5

/* ---------------------------- PUBLIC FUNCTIONS ---------------------------- */
void display_device_blink(void);
void leds_enable(bool enable);
bool any_button_pressed(void);
bool button_pressed(enum buttons button);
void refresh_autooff_timer(void);

uint8_t get_current_config(void);
void set_current_config(uint8_t config);

void init_button_behaviour(void);

void debug_pin_enable(bool enable);
void debug_pin_toggle(void);

void power_off(void);

/// Feed (reload) the watchdog. Call from any long-running operation that keeps
/// control inside a single loop() iteration (chunked BLE sends, pairing wait,
/// auto-off blink) so it doesn't trip the watchdog.
void watchdog_feed(void);

#endif // H_MAIN