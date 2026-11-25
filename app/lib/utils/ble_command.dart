import 'dart:convert';
import 'dart:typed_data';
import 'dart:core';
import 'package:logger/logger.dart';
import 'package:tapdancer/models/device_settings.dart';
import 'package:tapdancer/utils/logger.dart';

enum Command {
  /* ----------------------------- SET COMMANDS ----------------------------- */
  cmdSetBlinkDevice("S#BLINK"),
  cmdSetAutoOffRefresh("S#A_OFF"),
  cmdSetDeleteBond("S#DBOND"),
  cmdSetTurnOff("S#T_OFF"),
  cmdSetSaveSettings("S#S_FLE"),
  cmdSetLoadSettings("S#L_FLE"),
  cmdSetReset("S#N_RST"),
  cmdSetFactoryReset("S#F_RST"),
  cmdSetStartAdvertising("S#ADV"),
  cmdSetConfigIndex("S#CFG_IDX"),
  cmdSetMaxBleConnections("S#CFG_BLE_CONS"),
  cmdSetTxPower("S#CFG_BLE_TX"),
  cmdSetAutoOffTime("S#CFG_A_OFF"),
  cmdSetConfigName("S#CFG_NAME"),
  cmdSetButtonClickTiming("S#CFG_BTN_TIME"),
  cmdSetKeycodes("S#CFG_KEYS"),
  cmdDeleteConfig("S#CFG_DEL"),

  /* ----------------------------- GET COMMANDS ----------------------------- */
  cmdGetInformation("G#INFO"),
  cmdGetConfigurations("G#CFGS"),
  cmdGetBonds("G#BNDS"),
  cmdGetConnections("G#CONS"),

  /* ----------------------------- PUSH COMMANDS ---------------------------- */
  cmdPushKeyclick("P#KEYC"),
  cmdPushKeypress("P#KEYP"),
  cmdPushConfig("P#CONF"),

  cmdInvalid("INVALID"),
  cmdUnknown("UNKNOWN"),
  cmdReceptionInProgress("PROGRESS");

  final String value;
  const Command(this.value);
}

enum ReceptionState {
  idle,
  firstPacket,
  middlePacket,
  lastPacket,
  receptionTimeout,
}

class BLECommand {
  static final Logger _logger = Log.instance;

  static Uint8List receivedData = Uint8List(0);
  static ReceptionState receptionState = ReceptionState.idle;
  static int receptionTime = 0;

  static Uint8List buildCommand(dynamic args) {
    List<String> commandParts = [];
    for (var arg in args) {
      if (arg is List) {
        commandParts.add(arg.map((e) => e.toString()).join(" "));
      } else if (arg is double) {
        commandParts.add(arg.toStringAsFixed(3));
      } else {
        commandParts.add(arg.toString());
      }
    }
    String command = "${commandParts.join(" ")}\n";
    return ascii.encode(command);
  }

  // ----------------------------- SEND COMMANDS ---------------------------- //
  static Uint8List setBlinkDevice() {
    Command command = Command.cmdSetBlinkDevice;
    _logger.d("Sending: $command");
    return buildCommand([command.value]);
  }

  static Uint8List setAutoOffRefresh() {
    Command command = Command.cmdSetAutoOffRefresh;
    _logger.t("Sending: $command");
    return buildCommand([command.value]);
  }

  static Uint8List setDeleteBond() {
    Command command = Command.cmdSetDeleteBond;
    _logger.d("Sending: $command");
    return buildCommand([command.value]);
  }

  static Uint8List setTurnOff() {
    Command command = Command.cmdSetTurnOff;
    _logger.d("Sending: $command");
    return buildCommand([command.value]);
  }

  static Uint8List setSaveSettings() {
    Command command = Command.cmdSetSaveSettings;
    _logger.d("Sending: $command");
    return buildCommand([command.value]);
  }

  static Uint8List setLoadSettings() {
    Command command = Command.cmdSetLoadSettings;
    _logger.d("Sending: $command");
    return buildCommand([command.value]);
  }

  static Uint8List setReset(bool saveToFlash) {
    Command command = Command.cmdSetReset;
    _logger.d("Sending: $command - save to flash: $saveToFlash");
    return buildCommand([command.value, saveToFlash ? 1 : 0]);
  }

  static Uint8List setFactoryReset() {
    Command command = Command.cmdSetFactoryReset;
    _logger.d("Sending: $command");
    return buildCommand([command.value]);
  }

  static Uint8List setStartAdvertising(int timeoutS) {
    Command command = Command.cmdSetStartAdvertising;
    _logger.d("Sending: $command - timeout: ${timeoutS}s");
    return buildCommand([command.value, timeoutS]);
  }

  static Uint8List setConfigIndex(int index, bool saveToFlash) {
    Command command = Command.cmdSetConfigIndex;
    _logger.d("Sending: $command - index: $index - save to flash: $saveToFlash");
    return buildCommand([command.value, index, saveToFlash ? 1 : 0]);
  }

  static Uint8List setMaxBleConnections(int maxConnections, bool saveToFlash) {
    if (maxConnections > 8) {
      maxConnections = 8;
    }
    Command command = Command.cmdSetMaxBleConnections;
    _logger.d("Sending: $command - max connections: $maxConnections - save to flash: $saveToFlash");
    return buildCommand([command.value, maxConnections, saveToFlash ? 1 : 0]);
  }

  /// Supported BLE TX power levels (dBm) on the nRF52840. Keep in sync with
  /// is_tx_power_valid() in the firmware; the device rejects other values.
  static const List<int> supportedTxPowers = [-40, -20, -16, -12, -8, -4, 0, 2, 3, 4, 5, 6, 7, 8];

  static Uint8List setTxPower(int txPower, bool saveToFlash) {
    // Snap to the nearest supported level so the device doesn't reject the value.
    if (!supportedTxPowers.contains(txPower)) {
      txPower = supportedTxPowers.reduce((a, b) => (txPower - a).abs() < (txPower - b).abs() ? a : b);
    }
    Command command = Command.cmdSetTxPower;
    _logger.d("Sending: $command - tx power: $txPower dBm - save to flash: $saveToFlash");
    return buildCommand([command.value, txPower, saveToFlash ? 1 : 0]);
  }

  static Uint8List setAutoOffTime(int configIdx, int seconds, bool saveToFlash) {
    if (configIdx >= configNum) {
      configIdx = configNum - 1;
    }
    Command command = Command.cmdSetAutoOffTime;
    _logger.d("Sending: $command - index: $configIdx - seconds: $seconds - save to flash: $saveToFlash");
    return buildCommand([command.value, configIdx, seconds, saveToFlash ? 1 : 0]);
  }

  static Uint8List setConfigName(
    int configIdx,
    String name,
    bool saveToFlash,
  ) {
    if (configIdx >= configNum) {
      configIdx = configNum - 1;
    }

    if (name.length > maxConfigNameLen) {
      name = name.substring(0, maxConfigNameLen);
    }

    Command command = Command.cmdSetConfigName;
    _logger.d("Sending: $command - index: $configIdx - name: $name - save to flash: $saveToFlash");

    // Replace spaces with 0x1A aka substitute ascii for transmission.
    name = name.replaceAll(' ', String.fromCharCode(0x1A));
    return buildCommand([command.value, configIdx, name, saveToFlash ? 1 : 0]);
  }

  static Uint8List setButtonClickTiming(
    int configIdx,
    ButtonType buttonType,
    int doubleClickMs,
    int longClickMs,
    bool saveToFlash,
  ) {
    if (configIdx >= configNum) {
      configIdx = configNum - 1;
    }

    Command command = Command.cmdSetButtonClickTiming;
    _logger.d("Sending: $command - index: $configIdx - button type: $buttonType - double click ms: $doubleClickMs - long click ms: $longClickMs - save to flash: $saveToFlash");
    return buildCommand([command.value, configIdx, buttonType.index, doubleClickMs, longClickMs, saveToFlash ? 1 : 0]);
  }

  static Uint8List setKeycodes(
    int configIdx,
    ButtonType buttonType,
    ClickType clickType,
    HIDKeyboardReport report,
    bool saveToFlash,
  ) {
    if (configIdx >= configNum) {
      configIdx = configNum - 1;
    }
    Command command = Command.cmdSetKeycodes;
    _logger.d("Sending: $command - index: $configIdx - button type: $buttonType - click type: $clickType - modifier: ${report.modifier} - keycodes: ${report.keycodes} - save to flash: $saveToFlash");
    return buildCommand([command.value, configIdx, buttonType.index, clickType.index, report.modifier, ...report.keycodes, saveToFlash ? 1 : 0]);
  }

  static Uint8List deleteConfig(int configIdx, bool saveToFlash) {
    if (configIdx >= configNum) {
      configIdx = configNum - 1;
    }
    Command command = Command.cmdDeleteConfig;
    _logger.d("Sending: $command - index: $configIdx - save to flash: $saveToFlash");
    return buildCommand([command.value, configIdx, saveToFlash ? 1 : 0]);
  }

  static Uint8List getInfo() {
    Command command = Command.cmdGetInformation;
    _logger.d("Sending: $command");
    return buildCommand([command.value]);
  }

  static Uint8List getConfigurations(bool loadSettingsFromFlash) {
    Command command = Command.cmdGetConfigurations;
    _logger.d("Sending: $command - load settings from flash: $loadSettingsFromFlash");
    return buildCommand([command.value, loadSettingsFromFlash ? 1 : 0]);
  }

  static Uint8List getBonds() {
    Command command = Command.cmdGetBonds;
    _logger.d("Sending: $command");
    return buildCommand([command.value]);
  }

  static Uint8List getConnections() {
    Command command = Command.cmdGetConnections;
    _logger.d("Sending: $command");
    return buildCommand([command.value]);
  }

  // ----------------------------- RECEIVE RESPONSES ---------------------------- //
  Map<String, dynamic> parseResponse(Uint8List data) {
    String dataStr = utf8.decode(data);

    // Handle chunked packets.
    if (dataStr.startsWith("\$")) {
      receivedData = Uint8List(0);
      receptionState = ReceptionState.firstPacket;
    } else {
      receptionState = ReceptionState.middlePacket;
    }

    if (dataStr.endsWith("\n")) {
      receptionState = ReceptionState.lastPacket;
    }
    receivedData = Uint8List.fromList([...receivedData, ...data]);
    _logger.t("Reception state: $receptionState");

    // Only parse the last packet.
    if (receptionState != ReceptionState.lastPacket) {
      return {
        "command": Command.cmdReceptionInProgress,
        "response": {},
      };
    }

    String receivedDataStr = utf8.decode(receivedData);

    _logger.t("Received data: $receivedDataStr - ${receivedData.length} bytes");

    // Find the command.
    Command commandId = Command.cmdUnknown;
    String commandName = receivedDataStr.split("\$")[1];
    for (var value in Command.values) {
      if (value.value == commandName) {
        commandId = value;
      }
    }

    // Handle the device settings separately.
    if (commandId == Command.cmdGetConfigurations) {
      final parsedSettings = parseBleSettings(receivedDataStr);
      return {
        "command": commandId,
        "response": {"settings": parsedSettings}
      };
    }

    // Key events encode the button index in the key suffix
    // (~KEY-{button}<{value}>): for keyclicks the value is the click type, for
    // keypresses it is the pressed flag. The generic list handling below would
    // discard the button index, so extract them directly here.
    if (commandId == Command.cmdPushKeyclick || commandId == Command.cmdPushKeypress) {
      final match = RegExp(r"~KEY-(\d+)<(\d+)>").firstMatch(receivedDataStr);
      if (match != null) {
        return {
          "command": commandId,
          "response": {
            "button": int.parse(match.group(1)!),
            "value": int.parse(match.group(2)!),
          },
        };
      }
    }

    // Extract the command's values.
    String commandValues = receivedDataStr.split("\$")[2];
    final RegExp regex = RegExp(r"~([\w-]+)<([^>]*)>");
    final matches = regex.allMatches(commandValues);
    Map<String, dynamic> resultDict = {for (var match in matches) match.group(1)!: match.group(2)!};

    // Check if there are ADDR-0 keys with attached numbers.
    Map<String, dynamic> resultDictWithLists = {};
    resultDict.forEach((key, value) {
      if (key.contains('-')) {
        final prefix = key.split('-')[0];
        if (!resultDictWithLists.containsKey(prefix)) {
          resultDictWithLists[prefix] = [value];
        } else {
          (resultDictWithLists[prefix] as List).add(value);
        }
      }
    });
    resultDict.removeWhere((key, value) => key.contains('-'));
    if (resultDictWithLists.isNotEmpty) {
      resultDict.addAll(resultDictWithLists);
    }

    return {
      "command": commandId,
      "response": resultDict,
    };
  }
}
