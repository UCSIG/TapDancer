/// @g_file settings.cpp
///
/// BLE Hid codes:
/// https://www.usb.org/sites/default/files/documents/hut1_12v2.pdf
///
/// @author UCSIG
/// @date September 12, 2024
#include "settings.h"
#include "crc.h"
#include "debug.h"
#include "ble_svc.h"
#include "main.h"
#include <bluefruit.h>
#include <Adafruit_LittleFS.h>
#include <InternalFileSystem.h>
using namespace Adafruit_LittleFS_Namespace;

#define MODULE_NAME       "[STRG] "

/* -------------------------------- SETTINGS -------------------------------- */
#define SETTINGS_FILENAME "settings.bin"

/* --------------------------------- GLOBALS -------------------------------- */
// Settings object.
static struct settings settings;

// NVM storage.
static File g_file(InternalFS);

/* -------------------------------- FUNCTIONS ------------------------------- */
static void settings_set_defaults(void);
static void settings_set_config_name(uint8_t config_num, const char* config_name);
static void settings_set_time_autooff_s(uint8_t config_num, uint16_t time_autooff_s);
static void settings_set_all_buttons_click_timing(uint8_t config_num,
                                                  uint32_t timing_double_click_ms,
                                                  uint32_t timing_long_click_ms);
static void settings_set_button_click_timing(uint8_t config_num,
                                             enum buttons button,
                                             uint32_t timing_double_click_ms,
                                             uint32_t timing_long_click_ms);
static void settings_set_keyboard_report(uint8_t config_num,
                                         enum buttons button,
                                         enum click_type click_type,
                                         hid_keyboard_report_t* keyboard_report);
static void
settings_set_consumer_key(uint8_t config_num, enum buttons button, enum click_type click_type, uint16_t usage_code);

static crc_t settings_calculate_crc(uint8_t* array, size_t len);

static void settings_print_user_configs(void);

bool settings_init(void) {
    bool status = false;

    LOGI(MODULE_NAME, "Initializing settings");

    // Set default setting values in case of a filesystem error.
    settings.version = SETTINGS_VERSION;
    settings.config_cur = 0;
    settings.ble_config.max_connections = DEFAULT_BLE_MAX_CONNECTIONS;
    settings.ble_config.tx_power = DEFAULT_BLE_TX_POWER;

    // Write the default settings for all available slots.
    for (int config = 0; config < CONFIG_NUM; config++) {
        strncpy(settings.configs[config].config_name, DEFAULT_CONFIG_NAME, MAX_CONFIG_NAME_LEN);

        settings.configs[config].time_autooff_s = DEFAULT_TIME_AUTOOFF_S;

        // Untouched slots are not "in use" until configured below or edited via the app.
        settings.configs[config].in_use = 0;

        // Set the keycodes to be sent.
        for (int button = 0; button < BUTTON_NUM; button++) {
            settings.configs[config].button_configs[button].keycodes[SINGLE_CLICK].modifier = MODIFIER_CLICK;
            settings.configs[config].button_configs[button].keycodes[SINGLE_CLICK].keycode[0] = KEYCODE_SINGLE_CLICK;

            settings.configs[config].button_configs[button].keycodes[DOUBLE_CLICK].modifier = MODIFIER_CLICK;
            settings.configs[config].button_configs[button].keycodes[DOUBLE_CLICK].keycode[0] = KEYCODE_DOUBLE_CLICK;

            settings.configs[config].button_configs[button].keycodes[TRIPLE_CLICK].modifier = MODIFIER_CLICK;
            settings.configs[config].button_configs[button].keycodes[TRIPLE_CLICK].keycode[0] = KEYCODE_TRIPLE_CLICK;

            settings.configs[config].button_configs[button].keycodes[LONG_PRESS].modifier = MODIFIER_CLICK;
            settings.configs[config].button_configs[button].keycodes[LONG_PRESS].keycode[0] = KEYCODE_LONGPRESS;

            // Button timings.
            settings.configs[config].button_configs[button].timing_double_click_ms = BUTTON_DOUBLE_CLICK_MS;
            settings.configs[config].button_configs[button].timing_long_click_ms = BUTTON_LONG_CLICK_MS;
        }
    }
    settings_set_defaults();

    // Initialize Internal File System.
    InternalFS.begin();

    // Load the settings.
    status = settings_load();
    if (status) {
        LOGD(MODULE_NAME, "Storage load SUCCESS");
    } else {
        LOGE(MODULE_NAME, "Storage load ERROR!");
    }

    settings_print_user_configs();
    return status;
}

static void settings_set_defaults(void) {
    hid_keyboard_report_t keyboard_report = {0};
    uint32_t config_num = 0;

    /* ------------------------------ CONFIG 0 ------------------------------ */
    config_num = 0;
    settings_set_config_name(config_num, "Arrows");
    settings_set_time_autooff_s(config_num, DEFAULT_TIME_AUTOOFF_S);
    settings_set_all_buttons_click_timing(config_num, BUTTON_DOUBLE_CLICK_MS, BUTTON_LONG_CLICK_MS);

    memset(&keyboard_report, 0, sizeof(hid_keyboard_report_t));
    for (int button = 0; button < BUTTON_NUM; button++) {
        keyboard_report.keycode[0] = HID_KEY_ARROW_RIGHT;
        settings_set_keyboard_report(config_num, (enum buttons)button, SINGLE_CLICK, &keyboard_report);
        keyboard_report.keycode[0] = HID_KEY_ARROW_LEFT;
        settings_set_keyboard_report(config_num, (enum buttons)button, DOUBLE_CLICK, &keyboard_report);
        keyboard_report.keycode[0] = HID_KEY_HOME;
        settings_set_keyboard_report(config_num, (enum buttons)button, TRIPLE_CLICK, &keyboard_report);
        keyboard_report.keycode[0] = HID_KEY_NONE;
        settings_set_keyboard_report(config_num, (enum buttons)button, LONG_PRESS, &keyboard_report);
    }

    /* ------------------------------ CONFIG 1 ------------------------------ */
    config_num = 1;
    settings_set_config_name(config_num, "Arrows Direct");
    settings_set_time_autooff_s(config_num, DEFAULT_TIME_AUTOOFF_S);
    settings_set_all_buttons_click_timing(config_num, BUTTON_DOUBLE_CLICK_DIRECT_MODE_MS, BUTTON_LONG_CLICK_MS);

    memset(&keyboard_report, 0, sizeof(hid_keyboard_report_t));
    keyboard_report.keycode[0] = HID_KEY_ARROW_RIGHT;
    settings_set_keyboard_report(config_num, PRIMARY_BUTTON, SINGLE_CLICK, &keyboard_report);
    keyboard_report.keycode[0] = HID_KEY_ARROW_LEFT;
    settings_set_keyboard_report(config_num, SECONDARY_BUTTON, SINGLE_CLICK, &keyboard_report);
    keyboard_report.keycode[0] = HID_KEY_HOME;
    settings_set_keyboard_report(config_num, TERTIARY_BUTTON, SINGLE_CLICK, &keyboard_report);

    /* ------------------------------ CONFIG 2 ------------------------------ */
    config_num = 2;
    settings_set_config_name(config_num, "Media Ctrl");
    settings_set_time_autooff_s(config_num, DEFAULT_TIME_AUTOOFF_S);
    settings_set_all_buttons_click_timing(config_num, BUTTON_DOUBLE_CLICK_MS, BUTTON_LONG_CLICK_MS);

    settings_set_consumer_key(config_num, PRIMARY_BUTTON, SINGLE_CLICK, HID_USAGE_CONSUMER_PLAY_PAUSE);
    settings_set_consumer_key(config_num, PRIMARY_BUTTON, DOUBLE_CLICK, HID_USAGE_CONSUMER_SCAN_NEXT);
    settings_set_consumer_key(config_num, PRIMARY_BUTTON, TRIPLE_CLICK, HID_USAGE_CONSUMER_SCAN_PREVIOUS);
    settings_set_consumer_key(config_num, PRIMARY_BUTTON, LONG_PRESS, HID_USAGE_CONSUMER_STOP);

    settings_set_consumer_key(config_num, SECONDARY_BUTTON, SINGLE_CLICK, HID_USAGE_CONSUMER_VOLUME_INCREMENT);
    settings_set_consumer_key(config_num, SECONDARY_BUTTON, DOUBLE_CLICK, HID_USAGE_CONSUMER_VOLUME_DECREMENT);
    settings_set_consumer_key(config_num, SECONDARY_BUTTON, TRIPLE_CLICK, HID_USAGE_CONSUMER_MUTE);
    settings_set_consumer_key(config_num, SECONDARY_BUTTON, LONG_PRESS, HID_USAGE_CONSUMER_MUTE);

    memset(&keyboard_report, 0, sizeof(hid_keyboard_report_t));
    keyboard_report.keycode[0] = HID_KEY_VOLUME_UP;
    settings_set_keyboard_report(config_num, TERTIARY_BUTTON, SINGLE_CLICK, &keyboard_report);
    keyboard_report.keycode[0] = HID_KEY_VOLUME_DOWN;
    settings_set_keyboard_report(config_num, TERTIARY_BUTTON, DOUBLE_CLICK, &keyboard_report);
    keyboard_report.keycode[0] = HID_KEY_MUTE;
    settings_set_keyboard_report(config_num, TERTIARY_BUTTON, TRIPLE_CLICK, &keyboard_report);
    keyboard_report.keycode[0] = HID_KEY_MUTE;
    settings_set_keyboard_report(config_num, TERTIARY_BUTTON, LONG_PRESS, &keyboard_report);

    /* ------------------------------ CONFIG 3 ------------------------------ */
    config_num = 3;
    settings_set_config_name(config_num, "Gamer Direct");
    settings_set_time_autooff_s(config_num, DEFAULT_TIME_AUTOOFF_S);
    settings_set_all_buttons_click_timing(config_num, BUTTON_DOUBLE_CLICK_DIRECT_MODE_MS, BUTTON_LONG_CLICK_MS);

    memset(&keyboard_report, 0, sizeof(hid_keyboard_report_t));
    keyboard_report.keycode[0] = HID_KEY_S;
    settings_set_keyboard_report(config_num, PRIMARY_BUTTON, SINGLE_CLICK, &keyboard_report);
    keyboard_report.keycode[0] = HID_KEY_W;
    settings_set_keyboard_report(config_num, SECONDARY_BUTTON, SINGLE_CLICK, &keyboard_report);
    keyboard_report.keycode[0] = HID_KEY_A;
    settings_set_keyboard_report(config_num, TERTIARY_BUTTON, SINGLE_CLICK, &keyboard_report);

    // Mark the factory-configured slots as in use so the app shows them.
    settings.configs[0].in_use = 1;
    settings.configs[1].in_use = 1;
    settings.configs[2].in_use = 1;
    settings.configs[3].in_use = 1;

    // /* ------------------------------ CONFIG 3 ------------------------------ */
    // strncpy(settings.configs[3].config_name, "Gamer", MAX_CONFIG_NAME_LEN);
    // settings.configs[3].time_autooff_s = DEFAULT_TIME_AUTOOFF_S;

    // settings.configs[3].button_configs[PRIMARY_BUTTON].keycodes[SINGLE_CLICK].keycode[0] = HID_KEY_W;
    // settings.configs[3].button_configs[PRIMARY_BUTTON].keycodes[DOUBLE_CLICK].keycode[0] = HID_KEY_A;
    // settings.configs[3].button_configs[PRIMARY_BUTTON].keycodes[TRIPLE_CLICK].keycode[0] = HID_KEY_S;
    // settings.configs[3].button_configs[PRIMARY_BUTTON].keycodes[LONG_PRESS].keycode[0] = HID_KEY_D;

    // settings.configs[3].button_configs[SECONDARY_BUTTON].keycodes[SINGLE_CLICK].keycode[0] = HID_KEY_LEFT_SHIFT;
    // settings.configs[3].button_configs[SECONDARY_BUTTON].keycodes[DOUBLE_CLICK].keycode[0] = HID_KEY_LEFT_CTRL;
    // settings.configs[3].button_configs[SECONDARY_BUTTON].keycodes[TRIPLE_CLICK].keycode[0] = HID_KEY_R;
    // settings.configs[3].button_configs[SECONDARY_BUTTON].keycodes[LONG_PRESS].keycode[0] = HID_KEY_SPACE;

    // settings.configs[3].button_configs[TERTIARY_BUTTON].keycodes[SINGLE_CLICK].keycode[0] = HID_KEY_1;
    // settings.configs[3].button_configs[TERTIARY_BUTTON].keycodes[DOUBLE_CLICK].keycode[0] = HID_KEY_2;
    // settings.configs[3].button_configs[TERTIARY_BUTTON].keycodes[TRIPLE_CLICK].keycode[0] = HID_KEY_3;
    // settings.configs[3].button_configs[TERTIARY_BUTTON].keycodes[LONG_PRESS].keycode[0] = HID_KEY_Q;
}

bool settings_load(void) {
    // Check if there is already a settings file. Else create one with the previously set default values.
    if (!g_file.open(SETTINGS_FILENAME, FILE_O_READ)) {
        LOGD(MODULE_NAME, "Creating settings file " SETTINGS_FILENAME);
        return settings_save();
    }

    // Keep a temporary settings object in case of crc failure.
    // Only copy the temp settings to the main settings object if the crc is valid.
    struct settings settings_temp;

    g_file.read((uint8_t*)&settings_temp, sizeof(settings_temp));
    g_file.close();

    // Verify CRC.
    crc_t crc = settings_calculate_crc((uint8_t*)&settings_temp, sizeof(settings_temp) - sizeof(settings_temp.crc));
    if (crc != settings_temp.crc) {
        LOGW(MODULE_NAME, "CRC mismatch! Removing settings file " SETTINGS_FILENAME);

        // Remove the corrupted file, use default settings and try again next time.
        settings_factory_reset();
        return false;
    }

    // Reject settings written by a different firmware version.
    if (settings_temp.version != SETTINGS_VERSION) {
        LOGW(MODULE_NAME,
             "Settings version mismatch (file %u, firmware %u)! Removing " SETTINGS_FILENAME,
             settings_temp.version,
             SETTINGS_VERSION);
        settings_factory_reset();
        return false;
    }

    // Copy settings.
    settings = settings_temp;

    return true;
}

bool settings_save(void) {
    if (!g_file.open(SETTINGS_FILENAME, FILE_O_WRITE)) {
        LOGE(MODULE_NAME, "Failed to open settings file " SETTINGS_FILENAME);
        return false;
    }

    // Calculate the CRC of the settings.
    // This must be done before writing the settings to the file.
    settings.crc = settings_calculate_crc((uint8_t*)&settings, sizeof(settings) - sizeof(settings.crc));

    size_t size_written = 0;
    uint8_t retry_count = 0;

    // Check if all bytes were written.
    while (size_written != sizeof(settings)) {
        g_file.seek(0);
        size_written = g_file.write((uint8_t*)&settings, sizeof(settings));
        retry_count++;

        if (retry_count >= SETTINGS_SAVE_RETRY_COUNT) {
            LOGE(MODULE_NAME, "Failed to write settings to file " SETTINGS_FILENAME " after %d retries", retry_count);
            g_file.close();
            return false;
        }

        delay(5);
    }

    LOGD(MODULE_NAME, "Saved settings to file (size %lu bytes) " SETTINGS_FILENAME, g_file.size());
    g_file.close();

    return true;
}

bool settings_use_jumper_config(void) {
    return settings.config_cur == CONFIG_MAGIC;
}

void settings_get_config(struct settings* settings_in) {
    *settings_in = settings;
}

struct settings* settings_get_config_pointer(void) {
    return &settings;
}

void settings_set_config(struct settings* settings_in) {
    settings = *settings_in;
}

void settings_factory_reset(void) {
    InternalFS.format();
}

void settings_reset_config(uint8_t config_num) {
    if (config_num >= CONFIG_NUM) {
        return;
    }

    struct user_config* cfg = &settings.configs[config_num];

    strncpy(cfg->config_name, DEFAULT_CONFIG_NAME, MAX_CONFIG_NAME_LEN);
    cfg->time_autooff_s = DEFAULT_TIME_AUTOOFF_S;
    cfg->in_use = 0;

    for (int button = 0; button < BUTTON_NUM; button++) {
        // Clear any residual keycodes (e.g. leftover consumer-key bytes) before
        // restoring the per-click-type defaults.
        memset(cfg->button_configs[button].keycodes, 0, sizeof(cfg->button_configs[button].keycodes));

        cfg->button_configs[button].keycodes[SINGLE_CLICK].modifier = MODIFIER_CLICK;
        cfg->button_configs[button].keycodes[SINGLE_CLICK].keycode[0] = KEYCODE_SINGLE_CLICK;

        cfg->button_configs[button].keycodes[DOUBLE_CLICK].modifier = MODIFIER_CLICK;
        cfg->button_configs[button].keycodes[DOUBLE_CLICK].keycode[0] = KEYCODE_DOUBLE_CLICK;

        cfg->button_configs[button].keycodes[TRIPLE_CLICK].modifier = MODIFIER_CLICK;
        cfg->button_configs[button].keycodes[TRIPLE_CLICK].keycode[0] = KEYCODE_TRIPLE_CLICK;

        cfg->button_configs[button].keycodes[LONG_PRESS].modifier = MODIFIER_CLICK;
        cfg->button_configs[button].keycodes[LONG_PRESS].keycode[0] = KEYCODE_LONGPRESS;

        cfg->button_configs[button].timing_double_click_ms = BUTTON_DOUBLE_CLICK_MS;
        cfg->button_configs[button].timing_long_click_ms = BUTTON_LONG_CLICK_MS;
    }
}

static void settings_set_config_name(uint8_t config_num, const char* config_name) {
    strncpy(settings.configs[config_num].config_name, config_name, MAX_CONFIG_NAME_LEN - 1);
    settings.configs[config_num].config_name[MAX_CONFIG_NAME_LEN - 1] = '\0';
}

static void settings_set_time_autooff_s(uint8_t config_num, uint16_t time_autooff_s) {
    settings.configs[config_num].time_autooff_s = time_autooff_s;
}

static void settings_set_all_buttons_click_timing(uint8_t config_num,
                                                  uint32_t timing_double_click_ms,
                                                  uint32_t timing_long_click_ms) {
    for (int button = 0; button < BUTTON_NUM; button++) {
        settings_set_button_click_timing(config_num,
                                         (enum buttons)button,
                                         timing_double_click_ms,
                                         timing_long_click_ms);
    }
}

static void settings_set_button_click_timing(uint8_t config_num,
                                             enum buttons button,
                                             uint32_t timing_double_click_ms,
                                             uint32_t timing_long_click_ms) {
    settings.configs[config_num].button_configs[button].timing_double_click_ms = timing_double_click_ms;
    settings.configs[config_num].button_configs[button].timing_long_click_ms = timing_long_click_ms;
}

static void settings_set_keyboard_report(uint8_t config_num,
                                         enum buttons button,
                                         enum click_type click_type,
                                         hid_keyboard_report_t* keyboard_report) {
    settings.configs[config_num].button_configs[button].keycodes[click_type].modifier = keyboard_report->modifier;
    memcpy(settings.configs[config_num].button_configs[button].keycodes[click_type].keycode,
           keyboard_report->keycode,
           6);
}

static void
settings_set_consumer_key(uint8_t config_num, enum buttons button, enum click_type click_type, uint16_t usage_code) {
    settings.configs[config_num].button_configs[button].keycodes[click_type].keycode[0] = usage_code >> 8;
    settings.configs[config_num].button_configs[button].keycodes[click_type].keycode[1] = usage_code;
    settings.configs[config_num].button_configs[button].keycodes[click_type].keycode[5] = KEYCODE_CONSUMER_KEY;
}

static void settings_print_user_configs(void) {
    LOGD(MODULE_NAME, "User Configs:");
    for (int config = 0; config < CONFIG_NUM; config++) {
        // Only print configs that are in use.
        if (!settings.configs[config].in_use && config != settings.config_cur) {
            continue;
        }

        settings_print_user_config(config);
    }
}

void settings_print_config(uint8_t config_num) {
    LOGD(MODULE_NAME, "Settings:");
    LOGD(MODULE_NAME, "  - Version:         %d", settings.version);
    LOGD(MODULE_NAME,
         "  - Config:          %d (%s)",
         settings.config_cur,
         settings_use_jumper_config() ? "Jumper" : "App");
    LOGD(MODULE_NAME, "BLE:");
    LOGD(MODULE_NAME, "  - Max connections: %d", settings.ble_config.max_connections);
    LOGD(MODULE_NAME, "  - TX power:        %d dBm", settings.ble_config.tx_power);
    LOGD(MODULE_NAME, "User Configs:");
    settings_print_user_config(config_num);
}

void settings_print_user_config(uint8_t config_num) {
    LOGD(MODULE_NAME, "  [%d] - '%s'", config_num, settings.configs[config_num].config_name);
    LOGT(MODULE_NAME, "      Autooff:   %.1f min", (float)settings.configs[config_num].time_autooff_s / 60.0f);

    // Keycodes can be found here: .platformio\packages\framework-arduinoadafruitnrf52-seeed\libraries\Adafruit_TinyUSB_Arduino\src\class\hid\hid.h

    // Primary - secondary - tertiary buttons
    for (int button = 0; button < BUTTON_NUM; button++) {
        LOGT(MODULE_NAME,
             "      %s %.3f s (dc) / %.3f s (lc)",
             (button == PRIMARY_BUTTON)     ? "Primary:  "
             : (button == SECONDARY_BUTTON) ? "Secondary:"
                                            : "Tertiary: ",
             (float)settings.configs[config_num].button_configs[button].timing_double_click_ms / 1000.0f,
             (float)settings.configs[config_num].button_configs[button].timing_long_click_ms / 1000.0f);

        // Single - double - triple clicks
        for (int code = SINGLE_CLICK; code < CLICK_NUM; code++) {
            // We are in direct mode.
            if ((settings.configs[config_num].button_configs[button].timing_double_click_ms == 0) &&
                code != SINGLE_CLICK) {
                continue;
            }

            LOGNT(MODULE_NAME, "       - %s:", settings_get_click_type_string((enum click_type)code));

            if ((code == LONG_PRESS) &&
                ble_keyboard_report_empty(&settings.configs[config_num].button_configs[button].keycodes[code])) {
                LOGT("", " turn off device");
                continue;
            }

            // Consumer keyboard report or regular keyboard report?
            if (ble_keyboard_report_is_consumer_key(
                    &settings.configs[config_num].button_configs[button].keycodes[code])) {
                LOGNT("",
                      " %04X - consumer key",
                      (settings.configs[config_num].button_configs[button].keycodes[code].keycode[0] << 8) |
                          settings.configs[config_num].button_configs[button].keycodes[code].keycode[1]);
            } else {
                for (int key = 0; key < 6; key++) {
                    if (settings.configs[config_num].button_configs[button].keycodes[code].keycode[key] !=
                        HID_KEY_NONE) {
                        LOGNT("",
                              " %02X",
                              settings.configs[config_num].button_configs[button].keycodes[code].keycode[key]);
                    }
                }
            }

            if (settings.configs[config_num].button_configs[button].keycodes[code].modifier != 0) {
                LOGT("",
                     " - modifier: 0x%02X",
                     settings.configs[config_num].button_configs[button].keycodes[code].modifier);
            } else {
                LOGT("", "");
            }

            if (settings.configs[config_num].button_configs[button].timing_double_click_ms == 0) {
                LOGT(MODULE_NAME, "       - direct mode");
            }
        }
    }
}

const char* settings_get_click_type_string(enum click_type click_type) {
    switch (click_type) {
    case SINGLE_CLICK:
        return "Single";
    case DOUBLE_CLICK:
        return "Double";
    case TRIPLE_CLICK:
        return "Triple";
    case LONG_PRESS:
        return "Long  ";
    default:
        return "";
    }
}

static crc_t settings_calculate_crc(uint8_t* array, size_t len) {
    crc_t crc = crc_init();
    crc = crc_update(crc, array, len);
    crc = crc_finalize(crc);
    return crc;
}
