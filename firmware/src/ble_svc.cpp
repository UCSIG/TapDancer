/// @file ble_svc.cpp
///
/// @author UCSIG
/// @date September 14, 2024
#include "main.h"
#include "debug.h"
#include "ble_svc.h"
#include "settings.h"
#include "soft_timer.h"
#include <bluefruit.h>
#include <Adafruit_LittleFS.h>
#include <InternalFileSystem.h>
using namespace Adafruit_LittleFS_Namespace;

#define MODULE_NAME "[BLE ] "

/* --------------------------------- GLOBALS -------------------------------- */
// Ble service objects.
static BLEDis bledis;
static BLEHidAdafruit blehid;
static BLEDfu bledfu;
static BLEUart bleuart;
static BLEBas blebas;

// Settings object.
static struct settings* settings;

// Connection handling.
static int32_t g_uart_connection_handle = -1;
static enum pairing_status g_pairing_state = PAIRING_IDLE;

// Keypress handling.
static hid_keyboard_report_t g_keyboard_report;

/* -------------------------------- FUNCTIONS ------------------------------- */
static void ble_release_key(uint16_t conn_hdl);
static void ble_add_key_to_report(hid_keyboard_report_t* keyboard_report);
static void ble_remove_key_from_report(hid_keyboard_report_t* keyboard_report);

/* -------------------------------- CALLBACKS ------------------------------- */
static void ble_connect_cb(uint16_t conn_handle);
static void ble_disconnect_cb(uint16_t conn_handle, uint8_t reason);
static bool ble_pair_passkey_cb(uint16_t conn_hdl, uint8_t const passkey[6], bool match_request);
static void ble_pair_passkey_req_cb(uint16_t conn_hdl, uint8_t passkey[6]);
static void ble_pair_complete_cb(uint16_t conn_hdl, uint8_t auth_status);
static void ble_secured_conn_cb(uint16_t conn_hdl);
static void ble_stop_advertising_cb(void);
static void uart_notify_cb(uint16_t conn_hdl, bool enabled);

void ble_init(const char* ble_name, struct settings* settings_in) {
    // Store pointer to main settings locally.
    settings = settings_in;

    // General ble initializations.
    Bluefruit.autoConnLed(false);
    Bluefruit.configPrphConn(247, 6, 2, BLE_GATTC_WRITE_CMD_TX_QUEUE_SIZE_DEFAULT);
    Bluefruit.setTxPower(settings->ble_config.tx_power); // Check bluefruit.h for supported values
    Bluefruit.begin(DEFAULT_BLE_MAX_CONNECTIONS, 0);

    // Peripheral stuff.
    /* Set connection interval (min, max) to your perferred value.
    * @note: It is already set by BLEHidAdafruit::begin() to 11.25ms - 15ms
    * min = 9*1.25=11.25 ms, max = 12*1.25= 15 ms 
    */
    /* Bluefruit.Periph.setConnInterval(9, 12); */
    Bluefruit.Periph.setConnSupervisionTimeoutMS(BLE_SUPERVISION_TIMEOUT_MS);
    Bluefruit.Periph.setConnectCallback(ble_connect_cb);
    Bluefruit.Periph.setDisconnectCallback(ble_disconnect_cb);

    // Configure and Start Device Information Service
    bledis.setModel(BLE_NAME);
    bledis.setManufacturer(BLE_DEVICE_MANUFACTURER);
    bledis.setSoftwareRev(SOFTWARE_VERSION);
    bledis.setHardwareRev(HARDWARE_REVISION);
    bledis.begin();

    /* Start BLE HID
    *  @note: Apple requires BLE device must have min connection interval >= 20m
    * ( The smaller the connection interval the faster we could send data).
    * However for HID and MIDI device, Apple could accept min connection interval 
    * up to 11.25 ms. Therefore BLEHidAdafruit::begin() will try to set the min and max
    * connection interval to 11.25  ms and 15 ms respectively for best performance.
    */

    // Important security stuff.
    blehid.setPermission(SECMODE_ENC_WITH_MITM, SECMODE_ENC_WITH_MITM);
    Bluefruit.Security.setIOCaps(true, true, false);
    Bluefruit.Security.setPairPasskeyCallback(&ble_pair_passkey_cb);
    Bluefruit.Security.setPairPasskeyRequestCallback(&ble_pair_passkey_req_cb);
    Bluefruit.Security.setPairCompleteCallback(&ble_pair_complete_cb);
    Bluefruit.Security.setSecuredCallback(&ble_secured_conn_cb);

    // Find out when the central enables notifications on these characteristics.
    bleuart.setNotifyCallback(uart_notify_cb);

    // Start BLE HID service.
    blehid.begin();

    // Set up ble ota updates.
    bledfu.begin();

    // Configure and Start BLE Uart Service
    bleuart.begin();

    // Start BLE Battery Service
    blebas.begin();

    // Set up and start advertising.
    ble_start_advertising(ble_name);
}

static void uart_notify_cb(uint16_t conn_hdl, bool enabled) {
    LOGD(MODULE_NAME, "[%lu] UART notifications %s", conn_hdl, enabled ? "enabled" : "disabled");
    g_uart_connection_handle = enabled ? conn_hdl : -1;
}

void ble_connect_cb(uint16_t conn_handle) {
    Bluefruit.Advertising.stop();

    BLEConnection* connection = Bluefruit.Connection(conn_handle);
    if (connection == NULL) {
        LOGW(MODULE_NAME, "[%lu] Connect callback with no connection object", conn_handle);
        return;
    }

    char central_name[64] = {0};
    connection->getPeerName(central_name, sizeof(central_name));
    // Supervision timeout: 10 ms unit.
    connection->requestConnectionParameter(9, 2, BLE_SUPERVISION_TIMEOUT_MS / 10);

    LOGI(MODULE_NAME, "[%lu] Connected to %s", conn_handle, central_name);
    if (ble_get_connected() < settings->ble_config.max_connections) {
        ble_restart_advertising(0);
    }
}

void ble_restart_advertising(uint16_t timeout) {
    LOGD(MODULE_NAME, "Restarting advertising with %us timeout", timeout);

    Bluefruit.Advertising.start(timeout);
}

void ble_disconnect_cb(uint16_t conn_handle, uint8_t reason) {
    LOGI(MODULE_NAME, "[%lu] Disconnected, reason = 0x%02X", conn_handle, reason);

    // If the disconnected device is the one with uart notifications enabled, reset the handle.
    if (g_uart_connection_handle == conn_handle) {
        g_uart_connection_handle = -1;
    }

    ble_restart_advertising(0);
}

bool ble_pair_passkey_cb(uint16_t conn_hdl, uint8_t const passkey[6], bool match_request) {
    g_pairing_state = PAIRING_REQUEST;
    LOGD(MODULE_NAME, "[%lu] Pair passkey callback", conn_hdl);

    LOGND(MODULE_NAME, "Passkey: ");
    for (int key = 0; key < 6; key++) {
        LOGND("", "%u", passkey[key]);
    }
    LOGD("", "");
    LOGD(MODULE_NAME, "Match request: %u", match_request);

    // Signal to the main loop that there is a pending paring request.
    // In the main loop, if there is a pairing request, the pairing process is started.
    // It calls the function ble_handle_pairing_request().
    // This function sets the global variable g_pairing_state to PAIRING_CONFIRMED or PAIRING_TIMEOUT.
    while (g_pairing_state == PAIRING_REQUEST) {
        watchdog_feed();
        delay(100);
    }

    LOGD(MODULE_NAME,
         "Pair passkey callback done - pairing %s",
         (g_pairing_state == PAIRING_CONFIRMED) ? "confirmed" : "timeout");

    // If set to true, the paring process is finished.
    return (g_pairing_state == PAIRING_CONFIRMED);
}

void ble_pair_passkey_req_cb(uint16_t conn_hdl, uint8_t passkey[6]) {
    LOGD(MODULE_NAME, "[%lu] Pair passkey request callback", conn_hdl);
    LOGND(MODULE_NAME, "Passkey: ");
    for (int key = 0; key < 6; key++) {
        LOGND("", "%02X", passkey[key]);
    }
    LOGD("", "");
}

void ble_pair_complete_cb(uint16_t conn_hdl, uint8_t auth_status) {
    LOGD(MODULE_NAME, "[%lu] Pairing complete callback", conn_hdl);
    LOGD(MODULE_NAME, "Authentication status: %u", auth_status);
}

void ble_secured_conn_cb(uint16_t conn_hdl) {
    LOGD(MODULE_NAME, "[%lu] Secured connestion callback", conn_hdl);
}

void ble_stop_advertising_cb(void) {
    LOGD(MODULE_NAME, "Stop advertising callback");
}

enum pairing_status ble_get_pairing_state(void) {
    return g_pairing_state;
}

uint8_t ble_get_connected(void) {
    return Bluefruit.connected();
}

bool ble_is_connected(uint16_t conn_hdl) {
    return Bluefruit.connected(conn_hdl);
}

uint8_t ble_get_address(uint8_t mac[6]) {
    return Bluefruit.getAddr(mac);
}

int8_t ble_get_tx_power(void) {
    return Bluefruit.getTxPower();
}

bool ble_set_tx_power(int8_t power) {
    // Store the value. In this Bluefruit fork setTxPower() only caches it and
    // validates against the SoftDevice's supported levels; it does not push it
    // to the radio. We therefore also apply it to any live connection and
    // re-apply it to advertising (start() reads the stored value).
    if (!Bluefruit.setTxPower(power)) {
        LOGW(MODULE_NAME, "Rejected TX power: %d dBm (unsupported level)", power);
        return false;
    }

    // Apply immediately to every active connection.
    for (uint16_t conn_hdl = 0; conn_hdl < BLE_MAX_CONNECTION; conn_hdl++) {
        if (ble_is_connected(conn_hdl)) {
            Bluefruit.Connection(conn_hdl)->setTxPower(power);
        }
    }

    // Re-apply to advertising if it is currently running.
    if (Bluefruit.Advertising.isRunning()) {
        Bluefruit.Advertising.stop();
        Bluefruit.Advertising.start(0);
    }

    return true;
}

uint16_t ble_get_max_mtu(void) {
    return Bluefruit.getMaxMtu(BLE_GAP_ROLE_PERIPH);
}

void ble_start_advertising(const char* ble_name) {
    // There is enough room for the dev name in the advertising packet
    Bluefruit.setName(ble_name);
    Bluefruit.Advertising.addName();

    // Advertising packet (max 31 bytes, name can get chopped of).
    Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
    Bluefruit.Advertising.addAppearance(BLE_APPEARANCE_HID_KEYBOARD);

    // Get notified when advertising stops.
    Bluefruit.Advertising.setStopCallback(ble_stop_advertising_cb);

    // Include BLE HID service
    Bluefruit.Advertising.addService(blehid);

    // For recommended advertising interval
    // https : //developer.apple.com/library/content/qa/qa1931/_index.html
    Bluefruit.Advertising.restartOnDisconnect(false);
    Bluefruit.Advertising.setInterval(32, 32); // fast: 20ms, slow: 20ms, in unit of 0.625 ms
    Bluefruit.Advertising.setFastTimeout(BLE_FAST_ADVERTISING_TIMEOUT_S);
    Bluefruit.Advertising.start(0); // 0 = Don't stop advertising after n seconds
}

void ble_disconnect_all(void) {
    for (uint16_t conn_hdl = 0; conn_hdl < BLE_MAX_CONNECTION; conn_hdl++) {
        if (ble_is_connected(conn_hdl)) {
            Bluefruit.disconnect(conn_hdl);
        }
    }

    soft_timer_t timer_disconnect;
    timer_set_relative_ms(&timer_disconnect, 2000);
    while (ble_get_connected() != 0) {
        watchdog_feed();
        if (timer_is_expired(&timer_disconnect)) {
            LOGW(MODULE_NAME, "Disconnection timeout!");
            break;
        }
        yield();
    }
}

void ble_clear_bonds(void) {
    Bluefruit.Periph.clearBonds();
}

static void ble_add_key_to_report(hid_keyboard_report_t* keyboard_report) {
    // Set modifier bits.
    g_keyboard_report.modifier |= keyboard_report->modifier;

    // Add to global keycodes.
    int input_idx = 0;
    for (int i = 0; i < 6; i++) {
        if (g_keyboard_report.keycode[i] == 0) {
            g_keyboard_report.keycode[i] = keyboard_report->keycode[input_idx];
            input_idx++;
        }
    }
}

static void ble_remove_key_from_report(hid_keyboard_report_t* keyboard_report) {
    // Clear modifier bits.
    g_keyboard_report.modifier &= ~keyboard_report->modifier;

    // Remove from global keycodes.1
    int input_idx = 0;
    for (int i = 0; i < 6; i++) {
        if (g_keyboard_report.keycode[i] == keyboard_report->keycode[input_idx]) {
            g_keyboard_report.keycode[i] = 0;
            input_idx++;
        }
    }

    // It isn't ideal to have zeros as gaps in the array.
    // Remove them here.
    uint8_t keycode_temp[6] = {0};
    int keycode_temp_idx = 0;
    for (int i = 0; i < 6; i++) {
        // Copy non-zero values to temp array.
        if (g_keyboard_report.keycode[i] != 0) {
            keycode_temp[keycode_temp_idx] = g_keyboard_report.keycode[i];
            keycode_temp_idx++;
        }
    }

    // Copy back to the original array
    for (int i = 0; i < 6; i++) {
        g_keyboard_report.keycode[i] = keycode_temp[i];
    }
}

void ble_send_keyclick(hid_keyboard_report_t* keyboard_report) {
    ble_send_keypress(keyboard_report, true);
    delay(20);

    // Release key.
    for (int i = 0; i < BLE_REPEAT_KEY_RELEASE; i++) {
        ble_send_keypress(keyboard_report, false);
    }
}

void ble_send_keypress(hid_keyboard_report_t* keyboard_report, bool pressed) {
    // Add keys to keyboard report.
    if (pressed) {
        ble_add_key_to_report(keyboard_report);
    } else {
        ble_remove_key_from_report(keyboard_report);
    }

    // Send keyboard report.
    bool consumer_key = ble_keyboard_report_is_consumer_key(keyboard_report);
    uint16_t usage_code = (g_keyboard_report.keycode[0] << 8) | g_keyboard_report.keycode[1];
    for (uint16_t conn_hdl = 0; conn_hdl < BLE_MAX_CONNECTION; conn_hdl++) {
        if (!ble_is_connected(conn_hdl)) {
            continue;
        }
        if (consumer_key) {
            blehid.consumerReport(conn_hdl, usage_code);
        } else {
            blehid.keyboardReport(conn_hdl, g_keyboard_report.modifier, g_keyboard_report.keycode);
        }
    }

    if (consumer_key) {
        LOGT(MODULE_NAME, "Consumer Key: %04X", usage_code);

    } else {
        LOGNT(MODULE_NAME, "Keys: mod.: 0x%02X, keys: ", g_keyboard_report.modifier);
        for (int i = 0; i < 6; i++) {
            LOGNT("", "%02X", g_keyboard_report.keycode[i]);
        }
        LOGT("", "");
    }
}

static void ble_release_key(uint16_t conn_hdl) {
    blehid.keyRelease(conn_hdl);
}

void ble_release_key_all(void) {
    LOGT(MODULE_NAME, "Releasing all keys");
    varclr(&g_keyboard_report);

    for (uint16_t conn_hdl = 0; conn_hdl < BLE_MAX_CONNECTION; conn_hdl++) {
        if (!ble_is_connected(conn_hdl)) {
            continue;
        }
        ble_release_key(conn_hdl);
    }
}

bool ble_keyboard_report_empty(hid_keyboard_report_t* keyboard_report) {
    bool keyboard_report_empty = true;

    // Check if the modifier is zero.
    if (keyboard_report->modifier != 0) {
        keyboard_report_empty = false;
    }

    // Check if the keycodes are all zero.
    for (int i = 0; i < 6; i++) {
        if (keyboard_report->keycode[i] != 0) {
            keyboard_report_empty = false;
        }
    }

    return keyboard_report_empty;
}

bool ble_keyboard_report_is_consumer_key(hid_keyboard_report_t* keyboard_report) {
    return (keyboard_report->keycode[5] == KEYCODE_CONSUMER_KEY);
}

void ble_handle_pairing_request(void) {
    LOGI(MODULE_NAME, "Handling pairing request.");

    // Wait for user confirmation.
    soft_timer_t timer_pairing_timeout;
    bool toggle = true;
    uint8_t button_pressed_state = 0;

    timer_set_relative_s(&timer_pairing_timeout, BLE_PAIRING_CONFIRMATION_TIMEOUT_S);
    leds_enable(false);

    while (true) {
        watchdog_feed();

        // Timeout after some time.
        if (timer_is_expired(&timer_pairing_timeout)) {
            g_pairing_state = PAIRING_TIMEOUT;
            break;
        }

        // Toggle and wait for button press.
        leds_enable(toggle);
        delay(120);
        toggle = !toggle;

        // Wait for button to be released if it was pressed.
        if ((button_pressed_state == 0) && !any_button_pressed()) {
            button_pressed_state = 1;
            delay(120);
        }

        // Wait for button press.
        if ((button_pressed_state == 1) && any_button_pressed()) {
            leds_enable(false);
            delay(120);
            g_pairing_state = PAIRING_CONFIRMED;
            break;
        }
    }

    // Confirmation fast toggle.
    if (g_pairing_state == PAIRING_CONFIRMED) {
        toggle = true;
        for (int i = 0; i < 8; i++) {
            leds_enable(toggle);
            delay(60);
            toggle = !toggle;
        }
    }
    leds_enable(false);
}

bool ble_bdata_skip_field(File* file) {
    int len = file->read();
    VERIFY(len > 0);

    file->seek(len + file->position());
    return true;
}

void ble_notify_battery(uint8_t battery_level) {
    blebas.notify(battery_level);
}

int ble_uart_available(void) {
    return bleuart.available();
}

int ble_uart_read(void) {
    return bleuart.read();
}

bool ble_uart_connected(void) {
    return g_uart_connection_handle != -1;
}

size_t ble_uart_write(const uint8_t* content, size_t len) {
    if (g_uart_connection_handle == -1) {
        LOGD(MODULE_NAME, "No UART connection.");
        return 0;
    }
    return bleuart.write(g_uart_connection_handle, content, len);
}

void ble_print_connected_devices(void) {
    LOGI(MODULE_NAME, "Connected devices:");
    char central_name[64] = {0};
    for (uint16_t conn_hdl = 0; conn_hdl < BLE_MAX_CONNECTION; conn_hdl++) {
        if (!ble_is_connected(conn_hdl)) {
            continue;
        }
        Bluefruit.Connection(conn_hdl)->getPeerName(central_name, sizeof(central_name));
        LOGI(MODULE_NAME, "  [%u] %s", conn_hdl, central_name);
    }
}

void ble_print_bond_list(void) {
    char const* dpath = BOND_DIR_PRPH;

    File dir(dpath, FILE_O_READ, InternalFS);
    File file(InternalFS);

    uint8_t device_count = 0;
    LOGI(MODULE_NAME, "Bonded devices:");
    while ((file = dir.openNextFile(FILE_O_READ))) {
        if (!file.isDirectory() && ble_bdata_skip_field(&file)) {
            int len = file.read();
            if (len > 0) {
                // Fixed buffer instead of a VLA sized by an untrusted file byte.
                // Clamp the read and always null-terminate before printing with %s.
                char devname[64] = {0};
                if (len > (int)sizeof(devname) - 1) {
                    len = sizeof(devname) - 1;
                }
                file.read(devname, len);
                devname[len] = '\0';

                LOGI(MODULE_NAME, "  [%d] %s: %s (%lu bytes)", device_count++, devname, file.name(), file.size());
            }
        }
        file.close();
    }
    file.close();
    dir.close();
}

void ble_remove_bond(uint8_t addr[BLE_GAP_ADDR_LEN]) {
    ble_gap_addr_t ble_config;
    for (int i = 0; i < BLE_GAP_ADDR_LEN; i++) {
        ble_config.addr[i] = addr[i];
    }
    bond_remove_key(BLE_GAP_ROLE_PERIPH, &ble_config);
}

void ble_get_connection_info(uint16_t conn_handle, char central_name[64], ble_gap_addr_t* central_addr, bool* bonded) {
    BLEConnection* connection = Bluefruit.Connection(conn_handle);
    if (connection == NULL) {
        central_name[0] = '\0';
        memset(central_addr, 0, sizeof(*central_addr));
        *bonded = false;
        return;
    }
    connection->getPeerName(central_name, 64);
    *central_addr = connection->getPeerAddr();
    *bonded = connection->bonded();
}
