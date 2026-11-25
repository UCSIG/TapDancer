/// @file main.cpp
///
/// https://github.com/littlefs-project/littlefs
/// https://github.com/adafruit/Adafruit_nRF52_Arduino/blob/00d0801c1461ff60d563426ceffe87b8e3e919bd/libraries/InternalFileSytem/examples/Internal_ReadWrite/Internal_ReadWrite.ino
/// https://github.com/adafruit/Adafruit_nRF52_Arduino/tree/00d0801c1461ff60d563426ceffe87b8e3e919bd/libraries/InternalFileSytem/examples
/// https://forum.seeedstudio.com/t/seeed-xiao-nrf52840-sense-external-onboard-flash-arduino-example-code/270001/7
/// https://gitlab.com/arduino5184213/seeed_xiao_nrf52840/flash_speedtest/-/tree/master
///
/// [TODO]:
/// - Provide more defaults.
/// - Split config files for faster writing
/// - Turn on then send keypress if connected.
///
/// InternalFileSystem:
/// It uses 7 * 4096 B = 28672 B / 28 kB of internal flash storage.
///
/// @author UCSIG
/// @date March 11, 2024
///
#include <Arduino.h>
#include "build_info.h"
#include "main.h"
#include "debug.h"
#include "settings.h"
#include "ble_svc.h"
#include "command.h"
#include <Button2.h>
#include "soft_timer.h"
#include <string.h>
#define MODULE_NAME "[MAIN] "

/* --------------------------------- GLOBALS -------------------------------- */
// Button objects.
static Button2 buttons[BUTTON_NUM] = {Button2(), Button2(), Button2()};

// Settings.
static struct settings* settings;
static uint8_t config_cur = 0;

// Configs and mappings.
static uint8_t led_pin_mapping[LED_NUM] = {PIN_LED_1, PIN_LED_2, PIN_LED_3};
const uint16_t config_adc_thrsh_lut[16] =
    {306, 880, 1347, 1711, 2018, 2292, 2529, 2724, 2896, 3056, 3200, 3321, 3431, 3536, 3631, 4096};

// Timers.
static soft_timer_t timer_startup;
static soft_timer_t timer_battery;
static soft_timer_t timer_autooff;

/* -------------------------------- FUNCTIONS ------------------------------- */
/* ----------------------------- GPIO AND CONFIG ---------------------------- */
static void init_gpios(void);
static uint32_t get_config_reading_adc(void);
static uint8_t get_config(uint32_t config_reading);

/* ---------------------------- POWER AND BATTERY --------------------------- */
static void power_enable(bool enable);
static void voltage_divider_enable(bool enable);
static void onboard_leds_disable(void);
static float get_battery_voltage_mv(void);
static uint8_t get_battery_level(float battery_voltage_mv);
static void reset_battery_timer(void);
static void set_startup_timer(void);

/* --------------------------------- DISPLAY -------------------------------- */
static void led_enable(uint8_t led, bool enable);
static void display_battery_level(void);
static bool display_auto_off(void);
static void display_battery_empty(void);
static void display_config_changed(void);
static void display_power_off(void);

/* ----------------------------- CLICK HANDLERS ----------------------------- */
static void pressed_handler(Button2& btn);
static void released_handler(Button2& btn);
static void single_click_handler(Button2& btn);
static void double_click_handler(Button2& btn);
static void triple_click_handler(Button2& btn);
static void long_press_handler(Button2& btn);

/* -------------------------------- DEBUGGING ------------------------------- */
static void print_tapdancer_information(void);

void setup() {
    // Clear the reset reason for the bootloader.
    NRF_POWER->RESETREAS = NRF_POWER->RESETREAS;

    Serial.begin(115200);
    // while (!Serial)
    //     ;

    // Init gpios and buttons.
    init_gpios();

    // Enable DC-DC converter
    NRF_POWER->DCDCEN = 1;

    // Start the startup timer.
    set_startup_timer();

    // Set up the adc.
    analogSampleTime(3); // 3 us sample time.
    analogReadResolution(12);
    analogReference(ADC_RANGE_OPT); // 0.6V Ref * 4 = 0..2.4V

    // Load the stored settings.
    settings_init();
    settings = settings_get_config_pointer();

    // Read the config voltage a few times to ensure the filter is initialized.
    if (settings_use_jumper_config()) {
        for (int i = 0; i < 10; i++) {
            get_config_reading_adc();
        }
        config_cur = get_config(get_config_reading_adc());
    } else {
        config_cur = settings->config_cur;
    }

    // Init buttons.
    init_button_behaviour();

    // Read the battery voltage a few times to ensure the filter is initialized.
    for (int i = 0; i < 10; i++) {
        get_battery_voltage_mv();
    }
    display_battery_level();

    // Make ble name.
    // BLE_NAME + space + 2 bytes (4 characters) unique id + null.
    const char* mcu_unique_id = getMcuUniqueID();
    static char ble_name[strlen(BLE_NAME) + 1 + 4 + 1];
    sprintf(ble_name, "%s %s", BLE_NAME, mcu_unique_id + strlen(mcu_unique_id) - 4);

    // Initialize ble.
    ble_init(ble_name, settings);

    // Print some debugging info.
    print_tapdancer_information();

    // Start auto-off timer.
    refresh_autooff_timer();

    // Start the command parser.
    cmd_init(settings);

    // Configure and start the watchdog LAST, once all (potentially slow)
    // initialization is done. Arming it earlier risks a reset mid-setup because
    // it isn't fed until loop() — BLE init + advertising can take >WATCHDOG_TIMEOUT_S.
    NRF_WDT->CONFIG = 0x01;                    // Run WDT while the CPU is asleep
    NRF_WDT->CRV = WATCHDOG_TIMEOUT_S * 32769; // CRV = timeout * 32768 + 1
    NRF_WDT->RREN = 0x01;                      // Enable the RR[0] reload register
    NRF_WDT->TASKS_START = 1;                  // Start WDT
}

void loop() {
    static bool connection_status_changed = false;
    static uint8_t connections_prev = 0;
    static bool startup_flag = true;

    // Feed the dog.
    watchdog_feed();

    // Keep onboard leds off to save power.
    onboard_leds_disable();

    /* ------------------------------- STARTUP ------------------------------ */
    // Only accept button pressed if main button has been released once after startup.
    if (startup_flag && !any_button_pressed()) {
        startup_flag = false;
    }

    // Handle button events.
    if (!startup_flag) {
        for (int button = 0; button < BUTTON_NUM; button++) {
            buttons[button].loop();
        }
    }

    /* ------------------------------- PAIRING ------------------------------ */
    // Triggered by the ble_pair_passkey_cb fuction.
    if (ble_get_pairing_state() == PAIRING_REQUEST) {
        ble_handle_pairing_request();
    }

    /* ------------------------------- BLE HID ------------------------------ */
    static soft_timer_t timer_key_release;
    if (timer_is_expired(&timer_key_release)) {
        timer_set_relative_ms(&timer_key_release, BLE_KEY_RELEASE_PERIOD_MS);
        ble_release_key_all();
    }

    /* --------------------------- BATTERY VOLTAGE -------------------------- */
    // Monitor battery voltage.
    if (timer_is_expired(&timer_battery)) {
        reset_battery_timer();

        // Get battery voltage and level.
        float battery_voltage_mv = get_battery_voltage_mv();
        uint8_t battery_level = get_battery_level(battery_voltage_mv);
        static soft_timer_t timer_battery_notify;
        if (timer_is_expired(&timer_battery_notify)) {
            timer_set_relative_ms(&timer_battery_notify, BLE_BATTERY_NOTIFY_INTERVAL_MS);
            ble_notify_battery(battery_level);
        }

        if (battery_voltage_mv < BAT_EMPTY_THRSH_MV) {
            LOGW(MODULE_NAME, " Battery empty!");
            ble_disconnect_all();
            display_battery_empty();
            delay(500);

            power_off();
        }
    }

    // Display the current battery level if nothing is connected and after startup.
    uint8_t connections = ble_get_connected();
    if ((connections == 0) || !timer_is_expired(&timer_startup)) {
        display_battery_level();
    } else {
        if (connections != connections_prev) {
            connections_prev = connections;
            connection_status_changed = true;
        }

        if (connection_status_changed) {
            connection_status_changed = false;
            refresh_autooff_timer();
        }
        leds_enable(false);
    }

    /* ------------------------------- CONFIG ------------------------------- */
    // Check if the config changed.
    if (settings_use_jumper_config()) {
        static uint8_t config_last_reading = 0;
        static soft_timer_t timer_config;
        uint8_t config_reading = get_config(get_config_reading_adc());

        if (config_reading != config_last_reading) {
            config_last_reading = config_reading;
            timer_set_relative_ms(&timer_config, CONFIG_STABLE_MS);
        }

        // Commit once the reading has held steady for the full window.
        if (timer_is_active(&timer_config) && timer_is_expired(&timer_config)) {
            if (config_reading != config_cur) {
                config_cur = config_reading;
                LOGD(MODULE_NAME, "Config changed: %d", config_cur);
                settings_print_user_config(config_cur);
                init_button_behaviour();
                display_config_changed();
                cmd_send_config(config_cur);
                refresh_autooff_timer();
            }
        }
    }

    /* ------------------------------ AUTO OFF ------------------------------ */
    // Check if the auto-off timer has expired.
    if (timer_is_expired(&timer_autooff) && (settings->configs[config_cur].time_autooff_s != 0)) {

        // The auto-off function can be aborted by clicking the main button.
        if (!display_auto_off()) {
            LOGD(MODULE_NAME,
                 "Auto-off timer expired after %lus, turning off if not connected to 5V USB.",
                 settings->configs[config_cur].time_autooff_s);
            delay(100);
            power_off();

            // If connected to 5V USB, just continue.
            delay(100);
            power_enable(true);
            refresh_autooff_timer();
        } else {
            LOGI(MODULE_NAME, "Auto-off aborted!");
            refresh_autooff_timer();
        }
    }

    // Parse incoming ble uart or serial uart messages.
    if (ble_uart_available() || Serial.available()) {
        while (ble_uart_available()) {
            uint8_t ch;
            ch = (uint8_t)ble_uart_read();
            cmd_digest(ch);
        }

        while (Serial.available()) {
            uint8_t ch;
            ch = (uint8_t)Serial.read();
            cmd_digest(ch);
        }
    }

    /* --------------------------- DEFERRED FLASH --------------------------- */
    if (cmd_task_pending() && !any_button_pressed()) {
        cmd_process_task();
    }
}

/* ---------------------------------- POWER --------------------------------- */
void power_off(void) {
    settings_save();
    delay(50);

    power_enable(false);
}

/* --------------------------------- BUTTONS -------------------------------- */
static void init_gpios(void) {
    /// ~15ms bounce.
    buttons[PRIMARY_BUTTON].begin(PRIMARY_BUTTON_PIN, INPUT, (PRIMARY_BUTTON_ACTIVE_LEVEL == LOW) ? true : false);
    buttons[SECONDARY_BUTTON].begin(SECONDARY_BUTTON_PIN, INPUT, (SECONDARY_BUTTON_ACTIVE_LEVEL == LOW) ? true : false);
    buttons[TERTIARY_BUTTON].begin(TERTIARY_BUTTON_PIN, INPUT, (TERTIARY_BUTTON_ACTIVE_LEVEL == LOW) ? true : false);

    // Power and battery.
    pinMode(PIN_POWER_EN, OUTPUT);
    pinMode(PIN_VOLT_DIV_EN, OUTPUT);
    analogReadResolution(12);

    onboard_leds_disable();

    power_enable(true);
    voltage_divider_enable(true);
    for (int led = 0; led < LED_NUM; led++) {
        pinMode(led_pin_mapping[led], OUTPUT);
        led_enable(led, false);
    }

    pinMode(PIN_DEBUG, OUTPUT);
    debug_pin_enable(false);
}

/* -------------------------------- WATCHDOG -------------------------------- */
void watchdog_feed(void) {
    // Reload the watchdog.
    NRF_WDT->RR[0] = WDT_RR_RR_Reload;
}

void init_button_behaviour(void) {
    // Set different button behaviour for every button.
    for (int button = 0; button < BUTTON_NUM; button++) {
        // The button id should be the same as @ref enum buttons.
        buttons[button].setID(button);

        buttons[button].setDebounceTime(BUTTON_DEBOUNCE_MS);
        buttons[button].setDoubleClickTime(settings->configs[config_cur].button_configs[button].timing_double_click_ms);
        buttons[button].setLongClickTime(settings->configs[config_cur].button_configs[button].timing_long_click_ms);

        // Set all handlers to NULL first to avoid unintended behaviour when changing click timings.
        buttons[button].setPressedHandler(NULL);
        buttons[button].setReleasedHandler(NULL);
        buttons[button].setClickHandler(NULL);
        buttons[button].setDoubleClickHandler(NULL);
        buttons[button].setTripleClickHandler(NULL);
        buttons[button].setLongClickDetectedHandler(NULL);

        // Set button handler functions.
        // If the double click time is 0, the button is in direct mode with press and release.
        // It can no longer be used for turning off the device.
        if (settings->configs[config_cur].button_configs[button].timing_double_click_ms == 0) {
            buttons[button].setPressedHandler(pressed_handler);
            buttons[button].setReleasedHandler(released_handler);
        } else {
            buttons[button].setClickHandler(single_click_handler);
            buttons[button].setDoubleClickHandler(double_click_handler);
            buttons[button].setTripleClickHandler(triple_click_handler);
            buttons[button].setLongClickDetectedHandler(long_press_handler);
            buttons[button].setLongClickDetectedRetriggerable(false);
        }
    }
}

bool any_button_pressed(void) {
    bool pressed = false;
    for (int button = 0; button < BUTTON_NUM; button++) {
        pressed = pressed || button_pressed((enum buttons)button);
    }
    return pressed;
}

bool button_pressed(enum buttons button) {
    bool pressed = false;
    switch (button) {
    case PRIMARY_BUTTON:
        pressed = digitalRead(PRIMARY_BUTTON_PIN) == PRIMARY_BUTTON_ACTIVE_LEVEL;
        break;
    case SECONDARY_BUTTON:
        pressed = digitalRead(SECONDARY_BUTTON_PIN) == SECONDARY_BUTTON_ACTIVE_LEVEL;
        break;
    case TERTIARY_BUTTON:
        pressed = digitalRead(TERTIARY_BUTTON_PIN) == TERTIARY_BUTTON_ACTIVE_LEVEL;
        break;
    case BUTTON_NUM:
        break;
    }
    return pressed;
}

/* --------------------------------- CONFIG --------------------------------- */
static uint32_t get_config_reading_adc(void) {
    static float config_reading = (float)analogRead(PIN_CONFIG_R2R);
    config_reading = (CONFIG_FILTER_COEFFICIENT * (float)analogRead(PIN_CONFIG_R2R)) +
                     (1.0f - CONFIG_FILTER_COEFFICIENT) * config_reading;
    return (uint32_t)config_reading;
}

static uint8_t get_config(uint32_t config_reading) {
    for (int i = 0; i < CONFIG_NUM; i++) {
        uint16_t lower_threshold = (i != 0) ? config_adc_thrsh_lut[i - 1] : 0;
        if ((config_reading < config_adc_thrsh_lut[i]) && (config_reading >= lower_threshold)) {
            return i;
        }
    }
    return 0;
}

uint8_t get_current_config(void) {
    return config_cur;
}

void set_current_config(uint8_t config) {
    if (config >= CONFIG_NUM) {
        config = CONFIG_NUM - 1;
    }

    config_cur = config;
}

void debug_pin_enable(bool enable) {
    digitalWrite(PIN_DEBUG, enable ? HIGH : LOW);
}

void debug_pin_toggle(void) {
    digitalWrite(PIN_DEBUG, !digitalRead(PIN_DEBUG));
}

static void power_enable(bool enable) {
    digitalWrite(PIN_POWER_EN, enable ? HIGH : LOW);
}

static void voltage_divider_enable(bool enable) {
    digitalWrite(PIN_VOLT_DIV_EN, enable ? HIGH : LOW);
}

static void onboard_leds_disable(void) {
    // Set all led pins as input so that calling
    // digitalWrite has no effect.
    pinMode(LED_RED, INPUT);
    pinMode(LED_GREEN, INPUT);
    pinMode(LED_BLUE, INPUT);
}

/* --------------------------------- DISPLAY -------------------------------- */
static void led_enable(uint8_t led, bool enable) {
    if (led >= LED_NUM) {
        return;
    }
    digitalWrite(led_pin_mapping[led], enable ? LOW : HIGH);
}

void leds_enable(bool enable) {
    for (int led = 0; led < LED_NUM; led++) {
        led_enable(led, enable);
    }
}

static void display_battery_level(void) {
    static soft_timer_t timer_blink;

    float battery_voltage_mv = get_battery_voltage_mv();
    if (battery_voltage_mv >= BAT_3_THRSH_MV) {
        leds_enable(true);
    } else if (battery_voltage_mv >= BAT_2_THRSH_MV) {
        led_enable(0, true);
        led_enable(1, true);
        led_enable(2, false);
    } else if (battery_voltage_mv >= BAT_1_THRSH_MV) {
        led_enable(0, true);
        led_enable(1, false);
        led_enable(2, false);
    } else {
        static bool toggle = true;
        led_enable(0, toggle);
        led_enable(1, false);
        led_enable(2, false);

        if (timer_is_expired(&timer_blink)) {
            timer_set_relative_ms(&timer_blink, 500);
            toggle = !toggle;
        }
    }
}

static bool display_auto_off(void) {
    bool auto_off_aborted = false;
    uint32_t blink_timer = 0;
    bool toggle = true;
    for (int i = 0; i < (16 * 2);) {
        watchdog_feed();
        if (any_button_pressed()) {
            auto_off_aborted = true;
            while (any_button_pressed()) {
                watchdog_feed();
                delay(50);
            }
            delay(100);
            break;
        }

        if ((millis() - blink_timer) > 200) {
            blink_timer = millis();
            leds_enable(toggle);
            toggle = !toggle;
            i++;
        }
    }
    leds_enable(false);
    return auto_off_aborted;
}

static void display_battery_empty(void) {
    for (int i = 0; i < 5; i++) {
        leds_enable(true);
        delay(100);
        leds_enable(false);
        delay(100);
    }
}

void display_device_blink(void) {
    for (int i = 0; i < 4; i++) {
        leds_enable(true);
        delay(40);
        leds_enable(false);
        delay(60);
    }
}

static void display_config_changed(void) {
    for (int i = 0; i < 3; i++) {
        leds_enable(true);
        delay(40);
        leds_enable(false);
        delay(60);
    }
}

static void display_power_off(void) {
    for (int i = 0; i < 3; i++) {
        leds_enable(true);
        delay(80);
        leds_enable(false);
        delay(80);
    }
}

/* --------------------------------- BATTERY -------------------------------- */
static float get_battery_voltage_mv(void) {
    static bool initial_run = true;

    // It takes ~10m for the voltage reading to stabilize after power on.
    if (initial_run) {
        initial_run = false;
        delay(15);
    }

    // Default adc settings are internal reference with 1/6 gain (GND..3.6V ADC range).
    static float battery_adc = (float)analogRead(PIN_BATTERY_VOLT);
    battery_adc = (BATTERY_FILTER_COEFFICIENT * (float)analogRead(PIN_BATTERY_VOLT)) +
                  (1.0f - BATTERY_FILTER_COEFFICIENT) * battery_adc;
    return (battery_adc / 4096.0f) * ADC_RANGE_MV * VOLTAGE_DIVIDER_FACTOR;
}

static uint8_t get_battery_level(float battery_voltage_mv) {
    // Avoid negative percentages.
    if (battery_voltage_mv < BAT_EMPTY_THRSH_MV) {
        battery_voltage_mv = BAT_EMPTY_THRSH_MV;
    }

    uint32_t battery_level = (uint32_t)(100.0f * (float)(battery_voltage_mv - BAT_EMPTY_THRSH_MV) /
                                        (float)(BAT_FULL_MV - BAT_EMPTY_THRSH_MV));

    if (battery_level > 100) {
        battery_level = 100;
    }
    return (uint8_t)battery_level;
}

/* ----------------------------- CLICK HANDLERS ----------------------------- */
static void pressed_handler(Button2& btn) {
    LOGD(MODULE_NAME,
         "%s: press",
         (btn.getID() == PRIMARY_BUTTON)     ? "B1"
         : (btn.getID() == SECONDARY_BUTTON) ? "B2"
                                             : "B3");
    ble_send_keypress(&settings->configs[config_cur].button_configs[btn.getID()].keycodes[SINGLE_CLICK], true);
    cmd_send_keypress((enum buttons)btn.getID(), true);
    refresh_autooff_timer();
}

static void released_handler(Button2& btn) {
    LOGD(MODULE_NAME,
         "%s: release",
         (btn.getID() == PRIMARY_BUTTON)     ? "B1"
         : (btn.getID() == SECONDARY_BUTTON) ? "B2"
                                             : "B3");
    ble_send_keypress(&settings->configs[config_cur].button_configs[btn.getID()].keycodes[SINGLE_CLICK], false);
    cmd_send_keypress((enum buttons)btn.getID(), false);
    refresh_autooff_timer();
}

static void single_click_handler(Button2& btn) {
    LOGD(MODULE_NAME,
         "%s: single",
         (btn.getID() == PRIMARY_BUTTON)     ? "B1"
         : (btn.getID() == SECONDARY_BUTTON) ? "B2"
                                             : "B3");
    ble_send_keyclick(&settings->configs[config_cur].button_configs[btn.getID()].keycodes[SINGLE_CLICK]);
    cmd_send_keyclick((enum buttons)btn.getID(), SINGLE_CLICK);
    refresh_autooff_timer();
}

static void double_click_handler(Button2& btn) {
    LOGD(MODULE_NAME,
         "%s: double",
         (btn.getID() == PRIMARY_BUTTON)     ? "B1"
         : (btn.getID() == SECONDARY_BUTTON) ? "B2"
                                             : "B3");
    ble_send_keyclick(&settings->configs[config_cur].button_configs[btn.getID()].keycodes[DOUBLE_CLICK]);
    cmd_send_keyclick((enum buttons)btn.getID(), DOUBLE_CLICK);
    refresh_autooff_timer();
}

static void triple_click_handler(Button2& btn) {
    LOGD(MODULE_NAME,
         "%s: triple",
         (btn.getID() == PRIMARY_BUTTON)     ? "B1"
         : (btn.getID() == SECONDARY_BUTTON) ? "B2"
                                             : "B3");
    ble_send_keyclick(&settings->configs[config_cur].button_configs[btn.getID()].keycodes[TRIPLE_CLICK]);
    cmd_send_keyclick((enum buttons)btn.getID(), TRIPLE_CLICK);
    refresh_autooff_timer();

    // Debug print info.
    print_tapdancer_information();

    // Display battery voltage.
    set_startup_timer();
}

static void long_press_handler(Button2& btn) {
    LOGD(MODULE_NAME,
         "%s: long press",
         (btn.getID() == PRIMARY_BUTTON)     ? "B1"
         : (btn.getID() == SECONDARY_BUTTON) ? "B2"
                                             : "B3");

    // Check whether to send a keycode or to turn off the device.
    if (ble_keyboard_report_empty(&settings->configs[config_cur].button_configs[btn.getID()].keycodes[LONG_PRESS])) {
        LOGD(MODULE_NAME, "Turning off device...");

        cmd_send_keyclick((enum buttons)btn.getID(), LONG_PRESS);
        refresh_autooff_timer();

        ble_disconnect_all();
        display_power_off();
        power_off();

        while (true) {
            if (Serial) {
                NVIC_SystemReset();
            }
            delay(100);
        }
    } else {
        ble_send_keyclick(&settings->configs[config_cur].button_configs[btn.getID()].keycodes[LONG_PRESS]);
        cmd_send_keyclick((enum buttons)btn.getID(), LONG_PRESS);
        refresh_autooff_timer();
    }
}

/* --------------------------------- TIMERS --------------------------------- */
static void reset_battery_timer() {
    timer_set_relative_ms(&timer_battery, BAT_MEASUREMENT_INTERVAL_MS);
}

void refresh_autooff_timer(void) {
    timer_set_relative_s(&timer_autooff, settings->configs[config_cur].time_autooff_s);
}

static void set_startup_timer() {
    timer_set_relative_ms(&timer_startup, TIME_DISPLAY_BATTERY_VOLTAGE_MS);
}

/* ---------------------------------- DEBUG --------------------------------- */
static void print_tapdancer_information(void) {
    // Retrieve relevant information.
    const char* bootloader_version = getBootloaderVersion();
    const char* mcu_unique_id = getMcuUniqueID();

    // Make ble name.
    // BLE_NAME + space + 2 bytes (4 characters) unique id + null.
    char ble_name[strlen(BLE_NAME) + 1 + +4 + 1];
    sprintf(ble_name, "%s %s", BLE_NAME, mcu_unique_id + strlen(mcu_unique_id) - 4);

    // Print information.
    LOGI(MODULE_NAME, "------------------- TAPDANCER -------------------");
    LOGI(MODULE_NAME, "Software:       %s - %s", SOFTWARE_VERSION, BUILD_TIME);
    LOGI(MODULE_NAME, "Hardware:       %s", HARDWARE_REVISION);
    LOGI(MODULE_NAME,
         "Battery:        %.2fmV / %d%%",
         get_battery_voltage_mv(),
         get_battery_level(get_battery_voltage_mv()));
    LOGI(MODULE_NAME, "BLE Name:       %s", ble_name);
    LOGI(MODULE_NAME, "Bootloader:     %s", bootloader_version);
    LOGI(MODULE_NAME, "MCU ID:         %s", mcu_unique_id);

    // BLE_GAP_ADDR_TYPE_PUBLIC                        0x00 ///< Public (identity) address.
    // BLE_GAP_ADDR_TYPE_RANDOM_STATIC                 0x01 ///< Random static (identity) address.
    // BLE_GAP_ADDR_TYPE_RANDOM_PRIVATE_RESOLVABLE     0x02 ///< Random private resolvable address.
    // BLE_GAP_ADDR_TYPE_RANDOM_PRIVATE_NON_RESOLVABLE 0x03 ///< Random private non-resolvable address.
    // BLE_GAP_ADDR_TYPE_ANONYMOUS                     0x7F ///< An advertiser may advertise without its address.
    uint8_t mac_address[6] = {0};
    uint8_t address_type = 0;
    address_type = ble_get_address(mac_address);
    LOGNI(MODULE_NAME, "BLE address:    ");
    for (uint8_t b = 0; b < 6; b++) {
        if (b != 5) {
            LOGNI("", "%02lX:", mac_address[5 - b]);
        } else {
            LOGNI("", "%02lX", mac_address[5 - b]);
        }
    }
    LOGNI("", " ");
    switch (address_type) {
    case BLE_GAP_ADDR_TYPE_PUBLIC:
        LOGI("", "public");
        break;
    case BLE_GAP_ADDR_TYPE_RANDOM_STATIC:
        LOGI("", "random static");
        break;
    case BLE_GAP_ADDR_TYPE_RANDOM_PRIVATE_RESOLVABLE:
        LOGI("", "random private resolvable");
        break;
    case BLE_GAP_ADDR_TYPE_RANDOM_PRIVATE_NON_RESOLVABLE:
        LOGI("", "random private non resolvable");
        break;
    case BLE_GAP_ADDR_TYPE_ANONYMOUS:
        LOGI("", "anonymous");
        break;
    default:
        break;
    }

    LOGI(MODULE_NAME, "TX Power:       %d dB", ble_get_tx_power());
    ble_print_connected_devices();
    ble_print_bond_list();
    settings_print_config(config_cur);

    LOGI(MODULE_NAME, "----------------------------------------------------");
    LOGI(MODULE_NAME, "");
}
