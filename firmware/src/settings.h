/// @file settings.h
///
/// @author UCSIG
/// @date September 12, 2024
#ifndef H_SETTINGS
#define H_SETTINGS

#include "crc.h"
#include <bluefruit.h>

/* -------------------------------- SETTINGS -------------------------------- */
/// [OPT] Number of user configs.
#define CONFIG_NUM                         16
/// [OPT] Set the settings filetype version.
/// v2: added `in_use` flag to `struct user_config`.
/// v3: added `tx_power` to `struct ble_config`.
#define SETTINGS_VERSION                   3
/// [OPT] Max length a user config name.
#define MAX_CONFIG_NAME_LEN                32
/// [OPT] The config magic value to use the jumpers for selecting the config index.
#define CONFIG_MAGIC                       UINT8_MAX
/// [OPT] The magic keycode at the last index of a keycode map to indicate a consumer key.
#define KEYCODE_CONSUMER_KEY               UINT8_MAX
/// [OPT] How often to retry saving the settings file in case of a write failure.
#define SETTINGS_SAVE_RETRY_COUNT          3

/* ------------------------------ DEFAUL VALUES ----------------------------- */
/// [OPT] Default user config name.
#define DEFAULT_CONFIG_NAME                "Default"
/// [OPT] Maximum number of simultaneous ble connections. Maximum: 20
#define DEFAULT_BLE_MAX_CONNECTIONS        4
/// [OPT] Default BLE TX power in dBm. nRF52840 supported levels:
/// -40,-20,-16,-12,-8,-4,0,2,3,4,5,6,7,8
#define DEFAULT_BLE_TX_POWER               8
/// [OPT] Time in seconds after which the device is turned off.
#define DEFAULT_TIME_AUTOOFF_S             (15 * 60)
/// [OPT] Default click modifier.
#define MODIFIER_CLICK                     0
/// [OPT] Default single click keycode.
#define KEYCODE_SINGLE_CLICK               HID_KEY_ARROW_RIGHT
/// [OPT] Default double click keycode.
#define KEYCODE_DOUBLE_CLICK               HID_KEY_ARROW_LEFT
/// [OPT] Default triple click keycode.
#define KEYCODE_TRIPLE_CLICK               HID_KEY_HOME
/// [OPT] Default longpress keycode (none - turn off device).
#define KEYCODE_LONGPRESS                  HID_KEY_NONE
/// [OPT] Default double click time in milliseconds.
#define BUTTON_DOUBLE_CLICK_MS             250
/// [OPT] Double click time to set the button in direct mode.
#define BUTTON_DOUBLE_CLICK_DIRECT_MODE_MS 0
/// [OPT] Default long click time in milliseconds.
#define BUTTON_LONG_CLICK_MS               2500

/* ---------------------------------- TYPES --------------------------------- */
enum click_type {
    SINGLE_CLICK = 0,
    DOUBLE_CLICK,
    TRIPLE_CLICK,
    LONG_PRESS,
    CLICK_NUM
};

enum buttons {
    PRIMARY_BUTTON = 0,
    SECONDARY_BUTTON,
    TERTIARY_BUTTON,
    BUTTON_NUM
};

/* ----------------------------- SETTINGS STRUCT ---------------------------- */
// Each button has its own config.
struct button_config {
    hid_keyboard_report_t keycodes[(enum click_type)CLICK_NUM];
    uint32_t timing_double_click_ms; // Set to zero only have single click and an immediate reaction.
    uint32_t timing_long_click_ms;
};

// A user can selet between @ref CONFIG_NUM different configurations.
struct user_config {
    uint32_t time_autooff_s; // Set to 0 to disable auto-off.
    char config_name[MAX_CONFIG_NAME_LEN];
    struct button_config button_configs[BUTTON_NUM];
    uint8_t in_use; // 1 once this slot has been configured (factory default or app edit), 0 if untouched.
};

// Only allow that many concurrent ble connections.
struct ble_config {
    uint8_t max_connections;
    int8_t tx_power; // BLE TX power in dBm.
};

// The settings struct contains the base settings and all user configs.
struct settings {
    uint8_t version;
    uint8_t config_cur;
    struct ble_config ble_config;
    struct user_config configs[CONFIG_NUM];
    crc_t crc; ///< MUST be the last element!
};

/* -------------------------------- FUNCTIONS ------------------------------- */
bool settings_init(void);

bool settings_load(void);

/// Save the settings to the file.
/// @note only @ref settings_save_to_file actually writes the settings to the file.
/// @warning This performs a blocking flash write. Avoid calling it from the BLE
/// command-handling context; request a deferred operation via the command
/// module instead (see @ref cmd_request_task).
bool settings_save(void);

void settings_factory_reset(void);

/// Reset a single config slot back to the untouched default state (default
/// name, default keycodes/timings, marked not in use).
void settings_reset_config(uint8_t config_num);

bool settings_use_jumper_config(void);
void settings_get_config(struct settings* settings_in);
void settings_set_config(struct settings* settings_in);
void settings_print_config(uint8_t config_num);
void settings_print_user_config(uint8_t config_num);

struct settings* settings_get_config_pointer(void);

const char* settings_get_click_type_string(enum click_type click_type);

#endif // H_SETTINGS