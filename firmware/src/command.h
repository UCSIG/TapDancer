/// @file command.h
///
/// @author USIG
/// @date September 19, 2024
#ifndef H_COMMAND
#define H_COMMAND

#include "settings.h"

/* -------------------------------- SETTINGS -------------------------------- */
/// [OPT] Delay between packets.
#define PACKET_DELAY_MS        21

/// [OPT] Number of times to retry sending a packet.
#define PACKET_RESEND_COUNT    10

/// [OPT] Delay between packet resends. Added to @ref PACKET_DELAY_MS.
#define PACKET_RESEND_DELAY_MS 7

/* -------------------------------- FUNCTIONS ------------------------------- */
/// Initialize the command system with the given settings pointer.
void cmd_init(struct settings* settings_in);

/// @return true if a deferred operation is pending.
bool cmd_task_pending(void);

/// Perform the pending deferred operation (if any). Call from the main
/// loop while the device is idle so the blocking flash access stays out of the
/// BLE command-handling context.
/// @return true if an operation was performed, false if none was pending.
bool cmd_process_task(void);

/// Feed a single character to the command parser.
void cmd_digest(char input);

/// Send a key click event. A click is a press followed by a release.
/// $P#KEYC$~KEY-{button:int 0-2}<{click:int 0-2}>*
void cmd_send_keyclick(enum buttons button, enum click_type click);

/// Send a key press/release event.
/// $P#KEYP$~KEY-{button:int 0-2}<{pressed:bool}>*
void cmd_send_keypress(enum buttons button, bool pressed);

/// Send the current configuration index.
/// $P#CONF$~CFG_CUR<{config:int 0-15}>*
void cmd_send_config(uint8_t config);

#endif // H_COMMAND
