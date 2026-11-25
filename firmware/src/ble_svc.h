/// @file ble_svc.cpp
///
/// @author UCSIG
/// @date September 14, 2024
#ifndef H_BLE_SVC
#define H_BLE_SVC

#include <bluefruit.h>
#include <stdbool.h>
#include <Adafruit_LittleFS.h>
#include "settings.h"

using namespace Adafruit_LittleFS_Namespace;

enum pairing_status {
    PAIRING_REQUEST,
    PAIRING_CONFIRMED,
    PAIRING_TIMEOUT,
    PAIRING_IDLE
};

// Initialization.
void ble_init(const char* ble_name, struct settings* settings_in);

// BLE connections.
void ble_disconnect_all(void);
void ble_clear_bonds(void);
enum pairing_status ble_get_pairing_state(void);
void ble_handle_pairing_request(void);
void ble_remove_bond(uint8_t addr[BLE_GAP_ADDR_LEN]);
uint8_t ble_get_connected(void);
bool ble_is_connected(uint16_t conn_hdl);
uint8_t ble_get_address(uint8_t mac[6]);
uint16_t ble_get_max_mtu(void);
void ble_get_connection_info(uint16_t conn_handle, char central_name[64], ble_gap_addr_t* central_addr, bool* bonded);

// Ble advertising.
void ble_start_advertising(const char* ble_name);
void ble_restart_advertising(uint16_t timeout);
int8_t ble_get_tx_power(void);
bool ble_set_tx_power(int8_t power);

// BLE HID.
void ble_send_keyclick(hid_keyboard_report_t* keyboard_report);
void ble_send_keypress(hid_keyboard_report_t* keyboard_report, bool pressed);
void ble_release_key_all(void);
bool ble_keyboard_report_empty(hid_keyboard_report_t* keyboard_report);
bool ble_keyboard_report_is_consumer_key(hid_keyboard_report_t* keyboard_report);

// BLE BAS Battery.
void ble_notify_battery(uint8_t battery_level);

// BLE UART.
bool ble_uart_connected(void);
int ble_uart_available(void);
int ble_uart_read(void);
size_t ble_uart_write(const uint8_t* content, size_t len);

/* ------------------------------- UTILITIES+ ------------------------------- */
// Debug.
void ble_print_connected_devices(void);
void ble_print_bond_list(void);

bool ble_bdata_skip_field(File* file);

#endif // H_BLE_SVC