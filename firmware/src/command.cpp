/// @file command.cpp
///
/// GETTERS:
///   - Start: $G#CFGS$ - when requesting information the device responds with the request command enclosed in $.
///   - End: \n
///
///   Format:
///     ~KEY[-cfg][-sub_cfg][-sub_cfg]<value/array>*
///
///   Explanation:
///     - ~: the start of the key:value combination
///     - KEY: the actual key name
///     - value/array: the value of the key, if it is an array it is separated by ,
///     - cfg: (optional) the config index
///     - sub_cfg: (optional) the sub config index
///     - *: the end of the key:value combination
///
///   Example:
///     ~AOS-1<600>*
///     - AOS (auto off (s)) is set to 600 seconds
///
///     ~K-2-0-0<79,0,0,0,0,0>*
///     - The keycode array for single click of config 2 of the primary button is set to 79,0,0,0,0,0
///
/// @author USIG
/// @date September 19, 2024
#include <Arduino.h>
#include "main.h"
#include "command.h"
#include "debug.h"
#include "ble_svc.h"
#include "settings.h"
#include "debug.h"
#include <SerialCommand.h>
#include <Adafruit_LittleFS.h>
#include <InternalFileSystem.h>
using namespace Adafruit_LittleFS_Namespace;

#define MODULE_NAME "[CMD ] "

/* ---------------------------------- TYPES --------------------------------- */
/// Deferred operations requested by the command handlers. Command
/// handlers run in the BLE command-handling context where blocking flash
/// access is undesirable, so they request an operation and the main loop
/// performs it while idle.
enum cmd_task_types {
    CMD_TASK_NONE = 0,    ///< Nothing pending.
    CMD_TASK_SAVE,        ///< Save the settings to flash.
    CMD_TASK_LOAD,        ///< Reload the settings from flash.
    CMD_TASK_RESTART_ADV, ///< Restart advertising (e.g. after a settings change affecting the advertising).
};

/* --------------------------------- GLOBALS -------------------------------- */
// Settings object.
static struct settings* settings;

// Serial command object.
static SerialCommand serialcommand;

// Ble command buffer.
#define CMD_BUF_LEN (6000)
struct command {
    char buffer[CMD_BUF_LEN];
};
static struct command cmd;

// Pending deferred flash operation. Written from the BLE command-handling
// context and consumed by @ref cmd_process_task in the main loop, hence
// volatile.
struct cmd_task {
    enum cmd_task_types type;
    uint32_t payload;
};
static volatile struct cmd_task g_pending_task;

/* -------------------------------- FUNCTIONS ------------------------------- */
/// Request a deferred operation.
static void cmd_request_task(struct cmd_task task);

/* --------------------------------- SETTERS -------------------------------- */
/// Blink the device (no arguments).
/// S#BLINK
static void cmd_S_BLINK_blink_device(const char* command);

/// Refresh the auto-off timer (no arguments).
/// S#A_OFF
static void cmd_S_A_OFF_refresh_auto_off(const char* command);

/// Delete all BLE bondings (no arguments).
/// S#DBOND
static void cmd_S_DBOND_delete_bond(const char* command);

/// Turn off the device (no arguments).
/// S#T_OFF
static void cmd_S_T_OFF_turn_off(const char* command);

/// Save the settings to file (no arguments).
/// S#S_FLE
static void cmd_S_S_FLE_save_settings(const char* command);

/// Load the settings from file (no arguments).
/// S#L_FLE
static void cmd_S_L_FLE_load_settings(const char* command);

/// Reset the device (1 argument).
/// S#N_RST <save_to_flash:bool 0|1>
static void cmd_S_N_RST_reset_device(const char* command);

/// Factory reset the device (no arguments).
/// S#F_RST
static void cmd_S_F_RST_factory_reset(const char* command);

/// Start advertising with timeout (1 argument).
/// S#ADV <timeout_s:int>
static void cmd_S_ADV_start_advertising(const char* command);

/* ---------------------------- SETTERS - CONFIG ---------------------------- */

/// Set the current config index. (2 arguments)
/// S#CFG_IDX <cfg_num:int 0-15> <save_to_flash:bool 0|1>
static void cmd_S_CFG_set_config_index(const char* command);

/// Set the maximum number of BLE connections. (2 arguments)
/// S#CFG_BLE_CONS <ble_cons_num:int 1-8> <save_to_flash:bool 0|1>
static void cmd_S_CFG_BLE_CONS_set_max_ble_connections(const char* command);

/// Set the BLE TX power. (2 arguments)
/// Supported dBm levels (nRF52840): -40,-20,-16,-12,-8,-4,0,2,3,4,5,6,7,8.
/// S#CFG_BLE_TX <tx_power_dbm:int> <save_to_flash:bool 0|1>
static void cmd_S_CFG_BLE_TX_set_tx_power(const char* command);

/// Set the auto-off time for a configuration. (3 arguments)
/// S#CFG_A_OFF <cfg_num:int 0-15> <time_s:int (0 to disable)> <save_to_flash:bool 0|1>
static void cmd_S_CFG_A_OFF_set_auto_off(const char* command);

/// Set the name for a configuration. (3 arguments)
/// Use character 0x1A substitute for space.
/// S#CFG_NAME <cfg_num:int 0-15> <cfg_name:str> <save_to_flash:bool 0|1>
static void cmd_S_CFG_NAME_set_cfg_name(const char* command);

/// Set button click timings for a configuration. (5 arguments)
/// S#CFG_BTN_TIME <cfg_num:int 0-15> <btn_num:int 0-2> <doubleclick_ms:int> <longclick_ms:int> <save_to_flash:bool 0|1>
static void cmd_S_CFG_BTN_TIME_set_button_click_time(const char* command);

/// Set keycodes for a button/click type in a configuration. (11 arguments)
/// S#CFG_KEYS <cfg_num:int 0-15> <btn_num:int 0-2> <click_type:int 0-2> <modifier:int> <code1:int> ... <code6:int> <save_to_flash:bool 0|1>
static void cmd_S_CFG_KEYS_set_keycodes(const char* command);

/// Delete a configuration, resetting it to defaults and marking it unused. (2 arguments)
/// S#CFG_DEL <cfg_num:int 0-15> <save_to_flash:bool 0|1>
static void cmd_S_CFG_DEL_delete_config(const char* command);

/* --------------------------------- GETTERS -------------------------------- */
/// Get device information (no arguments).
/// G#INFO
static void cmd_G_INFO_get_information(const char* command);

/// Get all configurations (1 argument).
/// G#CFGS <load_settings_from_file:bool 0|1>
static void cmd_G_CFGS_get_configurations(const char* command);

/// Get all BLE bondings (no arguments).
/// G#BNDS
static void cmd_G_BNDS_get_bondings(const char* command);

/// Get current BLE connections (no arguments).
/// G#CONS
static void cmd_G_CONS(const char* command);

/// Default handler for unknown commands.
static void cmd_default(const char* command);

/* ----------------------------------- ACK ---------------------------------- */
/// Send ACK/NCK response for a command.
static void cmd_send_ACK(const char* cmd, bool ack);

/* ---------------------------- HELPER FUNCTIONS ---------------------------- */
/// Send buffer in BLE MTU-sized chunks.
static void cmd_send_chunked(const uint8_t* buf, size_t len);

/// Check snprintf result for buffer overflow.
static bool cmd_check_snprintf(const char* cmd_name, int idx, size_t remaining_space);

/// Check if config number is valid.
static bool cmd_check_config_num(uint32_t cfg_num);

/// Check if button number is valid.
static bool cmd_check_button_num(uint32_t btn_num);

/// Check if click type is valid.
static bool cmd_check_click_type(uint32_t click_type);

/// Empty the command buffer.
static void cmd_empty_buffer(void);

/// Print the command buffer.
static void cmd_print_buffer(void);

void cmd_init(struct settings* settings_in) {
    // Max command length set by @ref SERIALCOMMAND_MAXCOMMANDLENGTH.

    settings = settings_in;

    /* ------------------------------- SETTERS ------------------------------ */
    serialcommand.addCommand("S#BLINK", cmd_S_BLINK_blink_device);
    serialcommand.addCommand("S#A_OFF", cmd_S_A_OFF_refresh_auto_off);
    serialcommand.addCommand("S#DBOND", cmd_S_DBOND_delete_bond);
    serialcommand.addCommand("S#T_OFF", cmd_S_T_OFF_turn_off);
    serialcommand.addCommand("S#S_FLE", cmd_S_S_FLE_save_settings);
    serialcommand.addCommand("S#L_FLE", cmd_S_L_FLE_load_settings);
    serialcommand.addCommand("S#N_RST", cmd_S_N_RST_reset_device);
    serialcommand.addCommand("S#F_RST", cmd_S_F_RST_factory_reset);
    serialcommand.addCommand("S#ADV", cmd_S_ADV_start_advertising);

    // Configs.
    serialcommand.addCommand("S#CFG_IDX", cmd_S_CFG_set_config_index);
    serialcommand.addCommand("S#CFG_BLE_CONS", cmd_S_CFG_BLE_CONS_set_max_ble_connections);
    serialcommand.addCommand("S#CFG_BLE_TX", cmd_S_CFG_BLE_TX_set_tx_power);
    serialcommand.addCommand("S#CFG_A_OFF", cmd_S_CFG_A_OFF_set_auto_off);
    serialcommand.addCommand("S#CFG_NAME", cmd_S_CFG_NAME_set_cfg_name);
    serialcommand.addCommand("S#CFG_BTN_TIME", cmd_S_CFG_BTN_TIME_set_button_click_time);
    serialcommand.addCommand("S#CFG_KEYS", cmd_S_CFG_KEYS_set_keycodes);
    serialcommand.addCommand("S#CFG_DEL", cmd_S_CFG_DEL_delete_config);

    /* ------------------------------- GETTERS ------------------------------ */
    serialcommand.addCommand("G#INFO", cmd_G_INFO_get_information);
    serialcommand.addCommand("G#CFGS", cmd_G_CFGS_get_configurations);
    serialcommand.addCommand("G#BNDS", cmd_G_BNDS_get_bondings);
    serialcommand.addCommand("G#CONS", cmd_G_CONS);

    /// Additional commands which can get send without request:
    /// P#KEYC  - Send keyclick event - cmd_send_keyclick
    ///     $P#KEYC$~KEY-{button:int 0-2}<{click:int 0-2}>*
    /// P#KEYP  - Send keypress event - cmd_send_keypress
    ///     $P#KEYP$~KEY-{button:int 0-2}<{pressed:bool}>*
    /// P#CONFS - Send current configuration index - cmd_send_config
    ///     $P#CONFS$~CFG_CUR<{config:int 0-15}>*
    serialcommand.setDefaultHandler(cmd_default);
}

/* --------------------------- DEFERRED FLASH TASK -------------------------- */
static void cmd_request_task(struct cmd_task task) {
    g_pending_task.type = task.type;
    g_pending_task.payload = task.payload;
}

bool cmd_task_pending(void) {
    return g_pending_task.type != CMD_TASK_NONE;
}

bool cmd_process_task(void) {
    // Latch and clear before the (blocking) operation so a request arriving
    // during it is preserved and handled on the next call.
    enum cmd_task_types task = g_pending_task.type;
    g_pending_task.type = CMD_TASK_NONE;

    switch (task) {
    case CMD_TASK_SAVE:
        settings_save();
        break;

    case CMD_TASK_LOAD:
        settings_load();
        // Reloaded settings may carry different click timings for the active
        // config, so reinit the button behaviour (direct vs. indirect mode).
        init_button_behaviour();
        break;

    case CMD_TASK_RESTART_ADV:
        ble_restart_advertising(g_pending_task.payload);
        break;

    case CMD_TASK_NONE:
    default:
        return false;
    }
    return true;
}

/* ----------------------------------- ACK ---------------------------------- */
static void cmd_send_ACK(const char* cmd, bool ack) {
    // Add some space for an additional value.
    const size_t buf_len = 64;
    char cmd_ack[buf_len] = {0};

    snprintf(cmd_ack, buf_len, "$%s$~%s<%u>*\n", cmd, "ACK", ack);
    ble_uart_write((uint8_t*)cmd_ack, strlen(cmd_ack));
}

/* --------------------------------- SETTERS -------------------------------- */
static void cmd_S_BLINK_blink_device(const char* command) {
    LOGD(MODULE_NAME, "%s", command);
    display_device_blink();
}

static void cmd_S_A_OFF_refresh_auto_off(const char* command) {
    // LOGD(MODULE_NAME, "%s: Refresh autooff timer", command);
    refresh_autooff_timer();
}

static void cmd_S_DBOND_delete_bond(const char* command) {
    LOGD(MODULE_NAME, "%s: Delete bonding information", command);
    ble_clear_bonds();
}

static void cmd_S_T_OFF_turn_off(const char* command) {
    LOGD(MODULE_NAME, "%s: Turning off", command);
    power_off();
}

static void cmd_S_S_FLE_save_settings(const char* command) {
    LOGD(MODULE_NAME, "%s: Requesting settings save to file", command);
    cmd_request_task((struct cmd_task){.type = CMD_TASK_SAVE});
    cmd_send_ACK(command, true);
}

static void cmd_S_L_FLE_load_settings(const char* command) {
    LOGD(MODULE_NAME, "%s: Requesting settings load from file", command);
    cmd_request_task((struct cmd_task){.type = CMD_TASK_LOAD});
    cmd_send_ACK(command, true);
}

static void cmd_S_N_RST_reset_device(const char* command) {
    char* arg;
    int save = 1;

    // Check whether to save to flash.
    arg = serialcommand.next();
    if (arg != NULL) {
        save = atoi(arg);
    }

    LOGD(MODULE_NAME, "%s: Resetting device%s", command, (save != 0) ? " and saving settings" : "");

    if (save != 0) {
        settings_save();
    }
    cmd_send_ACK(command, true);
    delay(200);

    NVIC_SystemReset();
}

static void cmd_S_F_RST_factory_reset(const char* command) {
    LOGD(MODULE_NAME, "%s: Factory-resetting device", command);
    cmd_send_ACK(command, true);
    delay(200);

    settings_factory_reset();
    delay(20);
    NVIC_SystemReset();
}

static void cmd_S_ADV_start_advertising(const char* command) {
    char* arg;
    uint16_t timeout = 0;

    // Get the advertising timeout.
    arg = serialcommand.next();
    if (arg != NULL) {
        timeout = atoi(arg);
    } else {
        LOGE(MODULE_NAME, "%s: Missing argument: timeout (s)", command);
        cmd_send_ACK(command, false);
        return;
    }

    LOGD(MODULE_NAME, "%s: Starting advertising for %u seconds", command, timeout);
    cmd_request_task((struct cmd_task){.type = CMD_TASK_RESTART_ADV, .payload = timeout});
    cmd_send_ACK(command, true);
}

/* ---------------------------- SETTERS - CONFIG ---------------------------- */
static void cmd_S_CFG_set_config_index(const char* command) {
    char* arg;
    int arguments = 0;

    uint8_t config = 0;
    int save = 1;

    arg = serialcommand.next();
    if (arg != NULL) {
        config = atoi(arg);
        arguments++;
    }

    // Check whether to save to flash.
    arg = serialcommand.next();
    if (arg != NULL) {
        save = atoi(arg);
        arguments++;
    }

    if (arguments != 2) {
        LOGE(MODULE_NAME, "%s: Invalid argument count: %d!", command, arguments);
        cmd_send_ACK(command, false);
        return;
    } else if (!cmd_check_config_num(config)) {
        // Reject out-of-range indices: an invalid value would otherwise be
        // persisted to settings->config_cur and indexed out of bounds on boot.
        cmd_send_ACK(command, false);
        return;
    } else {
        LOGD(MODULE_NAME, "%s: setting config index: %u", command, config);
        settings->config_cur = config;
        set_current_config(config);

        // The new config may use different button click timings, so reinit the
        // button behaviour (direct vs. indirect mode).
        init_button_behaviour();
        if (save != 0) {
            cmd_request_task((struct cmd_task){.type = CMD_TASK_SAVE});
        }
        cmd_send_ACK(command, true);
    }
}

static void cmd_S_CFG_BLE_CONS_set_max_ble_connections(const char* command) {
    char* arg;
    int arguments = 0;

    uint8_t max_connections = DEFAULT_BLE_MAX_CONNECTIONS;
    int save = 1;

    // Get the ble connection nums.
    arg = serialcommand.next();
    if (arg != NULL) {
        max_connections = atoi(arg);
        arguments++;
    }

    // Check whether to save to flash.
    arg = serialcommand.next();
    if (arg != NULL) {
        save = atoi(arg);
        arguments++;
    }

    if (arguments != 2) {
        LOGE(MODULE_NAME, "%s: Invalid argument count: %d!", command, arguments);
        cmd_send_ACK(command, false);
        return;
    } else {
        LOGD(MODULE_NAME, "%s: ble max connections: %u", command, max_connections);
        settings->ble_config.max_connections = max_connections;

        if (save != 0) {
            cmd_request_task((struct cmd_task){.type = CMD_TASK_SAVE});
        }
        cmd_send_ACK(command, true);
    }
}

static void cmd_S_CFG_BLE_TX_set_tx_power(const char* command) {
    char* arg;
    int arguments = 0;

    int8_t tx_power = DEFAULT_BLE_TX_POWER;
    int save = 1;

    // Get the tx power (dBm).
    arg = serialcommand.next();
    if (arg != NULL) {
        tx_power = atoi(arg);
        arguments++;
    }

    // Check whether to save to flash.
    arg = serialcommand.next();
    if (arg != NULL) {
        save = atoi(arg);
        arguments++;
    }

    if (arguments != 2) {
        LOGE(MODULE_NAME, "%s: Invalid argument count: %d!", command, arguments);
        cmd_send_ACK(command, false);
        return;
    }

    LOGD(MODULE_NAME, "%s: ble tx power: %d dBm", command, tx_power);

    // Apply immediately. Rejects unsupported dBm levels, in which case neither
    // the radio nor the stored setting is changed.
    if (!ble_set_tx_power(tx_power)) {
        cmd_send_ACK(command, false);
        return;
    }
    settings->ble_config.tx_power = tx_power;

    if (save != 0) {
        cmd_request_task((struct cmd_task){.type = CMD_TASK_SAVE});
    }
    cmd_send_ACK(command, true);
}

static void cmd_S_CFG_A_OFF_set_auto_off(const char* command) {
    char* arg;
    int arguments = 0;

    uint32_t cfg_num = 0;
    uint32_t time_autooff_s = DEFAULT_TIME_AUTOOFF_S;
    int save = 1;

    // Get the config number.
    arg = serialcommand.next();
    if (arg != NULL) {
        cfg_num = atoi(arg);
        arguments++;
    }

    // Get the time.
    arg = serialcommand.next();
    if (arg != NULL) {
        time_autooff_s = atoi(arg);
        arguments++;
    }

    // Check whether to save to flash.
    arg = serialcommand.next();
    if (arg != NULL) {
        save = atoi(arg);
        arguments++;
    }

    if (arguments != 3) {
        LOGE(MODULE_NAME, "%s: Invalid argument count: %d!", command, arguments);
        cmd_send_ACK(command, false);
        return;
    } else {
        if (!cmd_check_config_num(cfg_num)) {
            cfg_num = 0;
        }
        LOGD(MODULE_NAME, "%s: [%lu] -> auto off time: %d s", command, cfg_num, time_autooff_s);
        settings->configs[cfg_num].time_autooff_s = time_autooff_s;
        settings->configs[cfg_num].in_use = 1;

        if (save != 0) {
            cmd_request_task((struct cmd_task){.type = CMD_TASK_SAVE});
        }
        cmd_send_ACK(command, true);
    }
}

static void cmd_S_CFG_NAME_set_cfg_name(const char* command) {
    char* arg;
    int arguments = 0;

    uint32_t cfg_num = 0;
    char cfg_name[MAX_CONFIG_NAME_LEN] = DEFAULT_CONFIG_NAME;
    int save = 1;

    // Get the config number.
    arg = serialcommand.next();
    if (arg != NULL) {
        cfg_num = atoi(arg);
        arguments++;
    }

    // Get the config name.
    arg = serialcommand.next();
    if (arg != NULL) {
        strncpy(cfg_name, arg, MAX_CONFIG_NAME_LEN - 1);
        cfg_name[MAX_CONFIG_NAME_LEN - 1] = '\0';
        arguments++;
    }

    // Check whether to save to flash.
    arg = serialcommand.next();
    if (arg != NULL) {
        save = atoi(arg);
        arguments++;
    }

    if (arguments != 3) {
        LOGE(MODULE_NAME, "%s: Invalid argument count: %d!", command, arguments);
        cmd_send_ACK(command, false);
        return;
    } else {
        if (!cmd_check_config_num(cfg_num)) {
            cfg_num = 0;
        }

        // Replace substitute character 0x1A with space.
        for (size_t i = 0; i < strlen(cfg_name); i++) {
            if (cfg_name[i] == 0x1A) {
                cfg_name[i] = ' ';
            }
        }

        LOGD(MODULE_NAME, "%s: [%lu] -> config name: '%s'", command, cfg_num, cfg_name);
        strncpy(settings->configs[cfg_num].config_name, cfg_name, MAX_CONFIG_NAME_LEN);
        settings->configs[cfg_num].in_use = 1;

        if (save != 0) {
            cmd_request_task((struct cmd_task){.type = CMD_TASK_SAVE});
        }
        cmd_send_ACK(command, true);
    }
}

static void cmd_S_CFG_BTN_TIME_set_button_click_time(const char* command) {
    char* arg;
    int arguments = 0;

    uint32_t cfg_num = 0;
    uint32_t btn_num = 0;
    uint32_t timing_double_click_ms = BUTTON_DOUBLE_CLICK_MS;
    uint32_t timing_long_click_ms = BUTTON_LONG_CLICK_MS;
    int save = 1;

    // Get the config number.
    arg = serialcommand.next();
    if (arg != NULL) {
        cfg_num = atoi(arg);
        arguments++;
    }

    // Get the button number.
    arg = serialcommand.next();
    if (arg != NULL) {
        btn_num = atoi(arg);
        arguments++;
    }

    // Get the timing.
    arg = serialcommand.next();
    if (arg != NULL) {
        timing_double_click_ms = atoi(arg);
        arguments++;
    }

    // Get the timing.
    arg = serialcommand.next();
    if (arg != NULL) {
        timing_long_click_ms = atoi(arg);
        arguments++;
    }

    // Check whether to save to flash.
    arg = serialcommand.next();
    if (arg != NULL) {
        save = atoi(arg);
        arguments++;
    }

    if (arguments != 5) {
        LOGE(MODULE_NAME, "%s: Invalid argument count: %d!", command, arguments);
        cmd_send_ACK(command, false);
        return;
    } else {
        if (!cmd_check_config_num(cfg_num)) {
            cfg_num = 0;
        }
        if (!cmd_check_button_num(btn_num)) {
            btn_num = PRIMARY_BUTTON;
        }
        LOGD(MODULE_NAME,
             "%s: [%lu] -> button %lu double click: %lu ms - long click: %lu ms",
             command,
             cfg_num,
             btn_num,
             timing_double_click_ms,
             timing_long_click_ms);
        settings->configs[cfg_num].button_configs[btn_num].timing_double_click_ms = timing_double_click_ms;
        settings->configs[cfg_num].button_configs[btn_num].timing_long_click_ms = timing_long_click_ms;
        settings->configs[cfg_num].in_use = 1;

        if (cfg_num == get_current_config()) {
            init_button_behaviour();
        }

        if (save != 0) {
            cmd_request_task((struct cmd_task){.type = CMD_TASK_SAVE});
        }
        cmd_send_ACK(command, true);
    }
}

static void cmd_S_CFG_KEYS_set_keycodes(const char* command) {
    char* arg;
    int arguments = 0;

    uint32_t cfg_num = 0;
    uint32_t btn_num = 0;
    uint32_t click_type = 0;
    hid_keyboard_report_t keyboard_report;
    varclr(&keyboard_report);

    int save = 1;

    // Get the config number.
    arg = serialcommand.next();
    if (arg != NULL) {
        cfg_num = atoi(arg);
        arguments++;
    }

    // Get the button number.
    arg = serialcommand.next();
    if (arg != NULL) {
        btn_num = atoi(arg);
        arguments++;
    }

    // Get the click type.
    arg = serialcommand.next();
    if (arg != NULL) {
        click_type = atoi(arg);
        arguments++;
    }

    // Get the keyboad modifier mask.
    arg = serialcommand.next();
    if (arg != NULL) {
        keyboard_report.modifier = atoi(arg);
        arguments++;
    }

    // Get the keycodes.
    for (int key = 0; key < 6; key++) {
        arg = serialcommand.next();
        if (arg != NULL) {
            keyboard_report.keycode[key] = atoi(arg);
            arguments++;
        }
    }

    // Check whether to save to flash.
    arg = serialcommand.next();
    if (arg != NULL) {
        save = atoi(arg);
        arguments++;
    }

    if (arguments != (1 + 6 + 4)) {
        LOGE(MODULE_NAME, "%s: Invalid argument count: %d!", command, arguments);
        cmd_send_ACK(command, false);
        return;
    } else {
        if (!cmd_check_config_num(cfg_num)) {
            cfg_num = 0;
        }
        if (!cmd_check_button_num(btn_num)) {
            btn_num = PRIMARY_BUTTON;
        }
        if (!cmd_check_click_type(click_type)) {
            click_type = SINGLE_CLICK;
        }
        LOGND(MODULE_NAME, "%s: [%d] -> button %lu, click type: %lu: ", command, cfg_num, btn_num, click_type);
        for (int key = 0; key < 6; key++) {
            settings->configs[cfg_num].button_configs[btn_num].keycodes[click_type].keycode[key] =
                keyboard_report.keycode[key];
            LOGND("", "0x%02X ", keyboard_report.keycode[key]);
        }
        settings->configs[cfg_num].button_configs[btn_num].keycodes[click_type].modifier = keyboard_report.modifier;
        LOGD("", "- modifier: 0x%02X", keyboard_report.modifier);
        settings->configs[cfg_num].in_use = 1;

        if (save != 0) {
            cmd_request_task((struct cmd_task){.type = CMD_TASK_SAVE});
        }
        cmd_send_ACK(command, true);
    }
}

static void cmd_S_CFG_DEL_delete_config(const char* command) {
    char* arg;
    int arguments = 0;

    uint32_t cfg_num = 0;
    int save = 1;

    // Get the config number.
    arg = serialcommand.next();
    if (arg != NULL) {
        cfg_num = atoi(arg);
        arguments++;
    }

    // Check whether to save to flash.
    arg = serialcommand.next();
    if (arg != NULL) {
        save = atoi(arg);
        arguments++;
    }

    if (arguments != 2) {
        LOGE(MODULE_NAME, "%s: Invalid argument count: %d!", command, arguments);
        cmd_send_ACK(command, false);
        return;
    }

    if (!cmd_check_config_num(cfg_num)) {
        cfg_num = 0;
    }

    LOGD(MODULE_NAME, "%s: [%lu] -> deleting config", command, cfg_num);
    settings_reset_config(cfg_num);

    if (save != 0) {
        cmd_request_task((struct cmd_task){.type = CMD_TASK_SAVE});
    }
    cmd_send_ACK(command, true);
}

/* --------------------------------- GETTERS -------------------------------- */
static void cmd_G_INFO_get_information(const char* command) {
    cmd_empty_buffer();
    int idx = snprintf(cmd.buffer,
                       CMD_BUF_LEN,
                       "$%s$~MCU_ID<%s>*~BOOT_VER<%s>*~SOFT_VER<%s>*~HARD_VER<%s>*\n",
                       command,
                       getMcuUniqueID(),
                       getBootloaderVersion(),
                       SOFTWARE_VERSION,
                       HARDWARE_REVISION);
    if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN)) {
        return;
    }
    cmd_send_chunked((const uint8_t*)cmd.buffer, (size_t)idx);

    LOGD(MODULE_NAME, "%s", command);
    cmd_print_buffer();
}

static void cmd_G_CFGS_get_configurations(const char* command) {
    char* arg;
    bool load_settings_from_file = false;

    // Get the load settings from file flag.
    arg = serialcommand.next();
    if (arg != NULL) {
        load_settings_from_file = atoi(arg);
    }

    if (load_settings_from_file) {
        LOGD(MODULE_NAME, "%s: Loading settings from file before sending", command);
        settings_load();
        init_button_behaviour();
    }

    cmd_empty_buffer();

    // Copy the first settings.
    int cur_idx = 0;
    int idx = snprintf(cmd.buffer + cur_idx,
                       CMD_BUF_LEN - cur_idx,
                       "$%s$~VERSION<%u>*~CFG<%u>*~BLE_MAX_CON<%u>*~BLE_TX<%d>*",
                       command,
                       settings->version,
                       settings->config_cur,
                       settings->ble_config.max_connections,
                       settings->ble_config.tx_power);
    if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
        return;
    }
    cur_idx += idx;

    // Loop over all configs, but only send those in use (plus the active one so
    // its data is never stale). Unused slots are reconstructed as defaults by
    // the app from their absence.
    for (int cfg = 0; cfg < CONFIG_NUM; cfg++) {
        if (!settings->configs[cfg].in_use && cfg != settings->config_cur) {
            continue;
        }

        idx = snprintf(cmd.buffer + cur_idx,
                       CMD_BUF_LEN - cur_idx,
                       "~A-%i<%lu>*~C-%i<%s>*~U-%i<%u>*",
                       cfg,
                       settings->configs[cfg].time_autooff_s,
                       cfg,
                       settings->configs[cfg].config_name,
                       cfg,
                       settings->configs[cfg].in_use);
        if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
            return;
        }
        cur_idx += idx;

        // Primary, secondary, and tertiary button
        for (int button = 0; button < BUTTON_NUM; button++) {

            // Single, double, and triple click
            for (int click = 0; click < CLICK_NUM; click++) {
                idx = snprintf(cmd.buffer + cur_idx, CMD_BUF_LEN - cur_idx, "~K-%i-%i-%i<", cfg, button, click);
                if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
                    return;
                }
                cur_idx += idx;

                // Modifiers
                idx = snprintf(cmd.buffer + cur_idx,
                               CMD_BUF_LEN - cur_idx,
                               "%u,",
                               settings->configs[cfg].button_configs[button].keycodes[click].modifier);
                if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
                    return;
                }
                cur_idx += idx;

                // Consumer keys encode the usage code in fixed byte positions
                // ([hi, lo, .., 0xFF]); a high byte of 0 must NOT be stripped or
                // the app can't reconstruct the code. Send all 6 bytes for them.
                bool is_consumer =
                    ble_keyboard_report_is_consumer_key(&settings->configs[cfg].button_configs[button].keycodes[click]);

                // Keycodes
                for (int code = 0; code < 6; code++) {
                    // Skip zero keycodes.
                    if (!is_consumer &&
                        settings->configs[cfg].button_configs[button].keycodes[click].keycode[code] == HID_KEY_NONE) {
                        continue;
                    }
                    idx = snprintf(cmd.buffer + cur_idx,
                                   CMD_BUF_LEN - cur_idx,
                                   "%u%s",
                                   settings->configs[cfg].button_configs[button].keycodes[click].keycode[code],
                                   (code != (6 - 1)) ? "," : "");
                    if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
                        return;
                    }
                    cur_idx += idx;
                }
                idx = snprintf(cmd.buffer + cur_idx, CMD_BUF_LEN - cur_idx, ">*");
                if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
                    return;
                }
                cur_idx += idx;
            }
            idx = snprintf(cmd.buffer + cur_idx,
                           CMD_BUF_LEN - cur_idx,
                           "~DC-%i-%i<%lu>*",
                           cfg,
                           button,
                           settings->configs[cfg].button_configs[button].timing_double_click_ms);
            if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
                return;
            }
            cur_idx += idx;

            idx = snprintf(cmd.buffer + cur_idx,
                           CMD_BUF_LEN - cur_idx,
                           "~LC-%i-%i<%lu>*",
                           cfg,
                           button,
                           settings->configs[cfg].button_configs[button].timing_long_click_ms);
            if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
                return;
            }
            cur_idx += idx;
        }
    }
    idx = snprintf(cmd.buffer + cur_idx, CMD_BUF_LEN - cur_idx, "\n");
    if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
        return;
    }
    cur_idx += idx;

    // Send over ble.
    cmd_send_chunked((const uint8_t*)cmd.buffer, cur_idx);

    LOGD(MODULE_NAME, "%s", command);
    cmd_print_buffer();
}

static void cmd_G_BNDS_get_bondings(const char* command) {
    cmd_empty_buffer();

    File dir(BOND_DIR_PRPH, FILE_O_READ, InternalFS);
    File file(InternalFS);

    uint8_t device_count = 0;
    int cur_idx = 0;
    int idx = snprintf(cmd.buffer + cur_idx, CMD_BUF_LEN - cur_idx, "$%s$", command);
    if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
        return;
    }
    cur_idx += idx;

    while ((file = dir.openNextFile(FILE_O_READ))) {
        if (!file.isDirectory() && ble_bdata_skip_field(&file)) {
            int len = file.read();
            if (len > 0) {
                // Get the device name.
                char devname[64] = {0};
                if (len > (int)sizeof(devname) - 1) {
                    len = sizeof(devname) - 1;
                }
                file.read(devname, len);
                devname[len] = '\0';

                idx = snprintf(cmd.buffer + cur_idx,
                               CMD_BUF_LEN - cur_idx,
                               "~DEV-%i<%s>*~MAC-%i<%s>*",
                               device_count,
                               devname,
                               device_count,
                               file.name());
                if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
                    return;
                }
                cur_idx += idx;
                device_count++;
            }
        }
        file.close();
    }
    file.close();
    dir.close();

    idx = snprintf(cmd.buffer + cur_idx, CMD_BUF_LEN - cur_idx, "\n");
    if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
        return;
    }
    cur_idx += idx;
    cmd_send_chunked((const uint8_t*)cmd.buffer, (size_t)cur_idx);

    LOGD(MODULE_NAME, "%s", command);
    cmd_print_buffer();
}

static void cmd_G_CONS(const char* command) {
    cmd_empty_buffer();

    int cur_idx = 0;
    int idx = snprintf(cmd.buffer + cur_idx, CMD_BUF_LEN - cur_idx, "$%s$", command);
    if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
        return;
    }
    cur_idx += idx;

    for (uint16_t con = 0; con < BLE_MAX_CONNECTION; con++) {
        if (!ble_is_connected(con)) {
            continue;
        }

        char central_name[64] = {0};
        ble_gap_addr_t central_addr;
        bool bonded = false;
        ble_get_connection_info(con, central_name, &central_addr, &bonded);

        idx = snprintf(cmd.buffer + cur_idx,
                       CMD_BUF_LEN - cur_idx,
                       "~DEV-%i<%s>*~MAC-%i<%02X%02X%02X%02X%02X%02X>*~BND-%i<%i>*",
                       con,
                       central_name,
                       con,
                       central_addr.addr[0],
                       central_addr.addr[1],
                       central_addr.addr[2],
                       central_addr.addr[3],
                       central_addr.addr[4],
                       central_addr.addr[5],
                       con,
                       bonded ? 1 : 0);
        if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
            return;
        }
        cur_idx += idx;
    }

    idx = snprintf(cmd.buffer + cur_idx, CMD_BUF_LEN - cur_idx, "\n");
    if (!cmd_check_snprintf(command, idx, CMD_BUF_LEN - cur_idx)) {
        return;
    }
    cur_idx += idx;
    cmd_send_chunked((const uint8_t*)cmd.buffer, (size_t)cur_idx);
    LOGD(MODULE_NAME, "%s", command);
    cmd_print_buffer();
}

static void cmd_default(const char* command) {
    cmd_empty_buffer();

    int idx = snprintf(cmd.buffer, CMD_BUF_LEN, "$%s$~ERR*\n", command);
    if (!cmd_check_snprintf("CMD Default", idx, CMD_BUF_LEN)) {
        return;
    }
    cmd_send_chunked((const uint8_t*)cmd.buffer, (size_t)idx);

    LOGW(MODULE_NAME, "Unrecognized command %s", cmd.buffer);

    LOGD(MODULE_NAME, "Commands:");
    uint8_t command_count = serialcommand.getCommandCount();
    char buf[SERIALCOMMAND_MAXCOMMANDLENGTH] = {0};
    char ble_buf[SERIALCOMMAND_MAXCOMMANDLENGTH] = {0};
    for (uint8_t i = 0; i < command_count; i++) {
        serialcommand.getCommandName(i, buf, SERIALCOMMAND_MAXCOMMANDLENGTH);
        LOGD(MODULE_NAME, "  %s", buf);

        snprintf(ble_buf, SERIALCOMMAND_MAXCOMMANDLENGTH, "%s\n", buf);
        cmd_send_chunked((const uint8_t*)ble_buf, strlen(ble_buf));
    }
}

void cmd_digest(char input) {
    serialcommand.readSerialFromChar(input);
}

void cmd_send_keyclick(enum buttons button, enum click_type click) {
    cmd_empty_buffer();
    int idx = snprintf(cmd.buffer, CMD_BUF_LEN, "$P#KEYC$~KEY-%i<%i>*\n", button, click);
    if (!cmd_check_snprintf("P#KEYC", idx, CMD_BUF_LEN)) {
        return;
    }
    cmd_send_chunked((const uint8_t*)cmd.buffer, (size_t)idx);
    cmd_print_buffer();
}

void cmd_send_keypress(enum buttons button, bool pressed) {
    cmd_empty_buffer();
    int idx = snprintf(cmd.buffer, CMD_BUF_LEN, "$P#KEYP$~KEY-%i<%i>*\n", button, pressed);
    if (!cmd_check_snprintf("P#KEYP", idx, CMD_BUF_LEN)) {
        return;
    }
    cmd_send_chunked((const uint8_t*)cmd.buffer, (size_t)idx);
    cmd_print_buffer();
}

void cmd_send_config(uint8_t config) {
    cmd_empty_buffer();
    int idx = snprintf(cmd.buffer, CMD_BUF_LEN, "$P#CONF$~CFG_CUR<%i>*\n", config);
    if (!cmd_check_snprintf("P#CONF", idx, CMD_BUF_LEN)) {
        return;
    }
    cmd_send_chunked((const uint8_t*)cmd.buffer, (size_t)idx);
    cmd_print_buffer();
}

static void cmd_send_chunked(const uint8_t* buf, size_t len) {
    if (!ble_uart_connected()) {
        return;
    }

    // [TODO] Make sending more reliable by sending the total length and checking for it in the app.
    uint16_t mtu = ble_get_max_mtu();
    if (mtu <= 3) {
        // Guard against an underflow/zero packet size, which would make the send
        // loop spin forever (write of 0 bytes "succeeds" without advancing).
        LOGE(MODULE_NAME, "Invalid MTU %u, aborting chunked send", mtu);
        return;
    }
    size_t max_mtu_packet_size = (size_t)(mtu - 3);
    size_t total_send_len = len;
    size_t packet_send_len = 0;

    size_t cur_send_byte = 0;
    uint32_t packet_count = 0;
    uint32_t total_resend_count = 0;
    bool sent_successfully = true;
    while (cur_send_byte < total_send_len) {
        if ((total_send_len - cur_send_byte) < max_mtu_packet_size) {
            packet_send_len = total_send_len - cur_send_byte;
        } else {
            packet_send_len = max_mtu_packet_size;
        }

        // Sometimes, when multiple clients are connected to the TapDancer, one must resend packets.
        bool packet_sent = false;
        uint32_t packet_resend_count = 0;
        while (!packet_sent) {
            size_t send_len = ble_uart_write(buf + cur_send_byte, packet_send_len);
            if (send_len != packet_send_len) {
                LOGT(MODULE_NAME, "%d/%d/%d/%d", cur_send_byte, total_send_len, packet_send_len, max_mtu_packet_size);
                LOGE(MODULE_NAME,
                     "Error sending packet %lu (%lu/%lu): %d/%d B, resending count: %lu",
                     packet_count,
                     send_len,
                     packet_send_len,
                     cur_send_byte,
                     total_send_len,
                     packet_resend_count);
                packet_resend_count++;
                total_resend_count++;
                delay(PACKET_RESEND_DELAY_MS);

                if (packet_resend_count > PACKET_RESEND_COUNT) {
                    LOGE(MODULE_NAME, "Packet resend count exceeded!");
                    sent_successfully = false;
                    break;
                }
            } else {
                packet_sent = true;
            }
        }

        packet_count++;
        cur_send_byte += packet_send_len;
    }

    LOGT(MODULE_NAME, "Sending %d B in %lu packets with max %d B each", len, packet_count, max_mtu_packet_size);
    if (total_resend_count > 0) {
        LOGW(MODULE_NAME, "Resent %lu / %lu packets!", total_resend_count, packet_count);
    }

    if (!sent_successfully) {
        LOGE(MODULE_NAME, "Sending failed!");
    }
}

static bool cmd_check_snprintf(const char* cmd_name, int idx, size_t remaining_space) {
    bool success = true;
    if ((idx < 0) || ((size_t)idx >= remaining_space)) {
        LOGE(MODULE_NAME, "%s: Buffer overflow", cmd_name);
        success = false;
    }
    return success;
}

static void cmd_empty_buffer(void) {
    memset(cmd.buffer, 0, (size_t)CMD_BUF_LEN);
}

static bool cmd_check_config_num(uint32_t cfg_num) {
    bool success = true;
    if (cfg_num >= CONFIG_NUM) {
        LOGE(MODULE_NAME, "Invalid config number: %lu", cfg_num);
        success = false;
    }
    return success;
}

static bool cmd_check_button_num(uint32_t btn_num) {
    bool success = true;
    if (btn_num >= BUTTON_NUM) {
        LOGE(MODULE_NAME, "Invalid button number: %lu", btn_num);
        success = false;
    }
    return success;
}

static bool cmd_check_click_type(uint32_t click_type) {
    bool success = true;
    if (click_type >= CLICK_NUM) {
        LOGE(MODULE_NAME, "Invalid click type: %lu", click_type);
        success = false;
    }
    return success;
}

static void cmd_print_buffer(void) {
#if CONFIG_LOG_LEVEL >= LOG_DEBUG
    Serial.print(DEBUG_COLOR MODULE_NAME CLR_RESET "-> ");
    Serial.print(cmd.buffer);
#endif
}