// Constants, keep up to date with settings.h file in firmware folder!
const int configNum = 16;
const int maxConfigNameLen = 32;
const int buttonNum = 3;
const int clickNum = 4;

/// Default button click timings in ms — mirror the firmware
/// (BUTTON_DOUBLE_CLICK_MS / BUTTON_LONG_CLICK_MS in settings.h).
/// A double-click timing of 0 means "direct mode" (fires instantly on press,
/// single click only).
const int defaultDoubleClickMs = 250;
const int defaultLongClickMs = 4000;

/// Default BLE TX power in dBm — mirrors DEFAULT_BLE_TX_POWER in settings.h.
const int defaultBleTxPower = 8;
const int _defaultHidArrowRight = 0x4F;
const int _defaultHidArrowLeft = 0x50;
const int _defaultHidHome = 0x4A;

enum ClickType { single, double, triple, long }

enum ButtonType { primary, secondary, tertiary }

class HIDKeyboardReport {
  final int modifier;
  final List<int> keycodes;

  HIDKeyboardReport({
    required this.modifier,
    required this.keycodes,
  });

  factory HIDKeyboardReport.fromCsv(String csv) {
    final parts = csv.split(',');
    final modifier = int.parse(parts[0]);
    final keys = parts.sublist(1).where((s) => s.isNotEmpty).map((s) => int.parse(s)).toList();
    return HIDKeyboardReport(modifier: modifier, keycodes: keys);
  }

  Map<String, dynamic> toJson() => {
        'modifier': modifier,
        // Keep the exact byte list (incl. consumer-key padding like
        // [hi, lo, 0, 0, 0, 0xFF]) so a round-trip preserves the binding.
        'keycodes': keycodes,
      };

  factory HIDKeyboardReport.fromJson(Map<String, dynamic> json) {
    final keys = (json['keycodes'] as List?)?.map((e) => (e as num).toInt()).toList() ?? <int>[];
    return HIDKeyboardReport(
      modifier: (json['modifier'] as num?)?.toInt() ?? 0,
      keycodes: keys,
    );
  }

  @override
  String toString() => 'mod=$modifier keys=$keycodes';
}

class ButtonConfig {
  final List<HIDKeyboardReport> keycodes; // length: clickNum
  final int timingDoubleClickMs;
  final int timingLongClickMs;

  ButtonConfig({
    required this.keycodes,
    required this.timingDoubleClickMs,
    required this.timingLongClickMs,
  });

  Map<String, dynamic> toJson() => {
        'dc': timingDoubleClickMs,
        'lc': timingLongClickMs,
        'keycodes': keycodes.map((r) => r.toJson()).toList(),
      };

  /// Rebuilds a fixed-length [clickNum] keycode list, padding missing entries
  /// with empty reports so a malformed/short file can't desync the click types.
  factory ButtonConfig.fromJson(Map<String, dynamic> json) {
    final rawKeys = (json['keycodes'] as List?) ?? const [];
    final reports = List<HIDKeyboardReport>.generate(clickNum, (i) {
      if (i < rawKeys.length) {
        return HIDKeyboardReport.fromJson(Map<String, dynamic>.from(rawKeys[i] as Map));
      }
      return HIDKeyboardReport(modifier: 0, keycodes: const []);
    });
    return ButtonConfig(
      keycodes: reports,
      timingDoubleClickMs: (json['dc'] as num?)?.toInt() ?? 0,
      timingLongClickMs: (json['lc'] as num?)?.toInt() ?? 0,
    );
  }
}

class UserConfig {
  int timeAutoOffS;
  String configName;
  final List<ButtonConfig> buttonConfigs; // length: buttonNum

  /// True once the slot is configured — set by the firmware (factory defaults +
  /// any app edit) and reported via the `U` field. Drives which configs the app
  /// shows. Mutable so the app can update it optimistically after an edit.
  bool inUse;

  UserConfig({
    required this.timeAutoOffS,
    required String configName,
    required this.buttonConfigs,
    this.inUse = false,
  }) : configName = configName.length > maxConfigNameLen ? configName.substring(0, maxConfigNameLen) : configName;

  Map<String, dynamic> toJson() => {
        'configName': configName,
        'timeAutoOffS': timeAutoOffS,
        'inUse': inUse,
        'buttonConfigs': buttonConfigs.map((b) => b.toJson()).toList(),
      };

  /// Rebuilds a fixed-length [buttonNum] button list, padding missing buttons
  /// with defaults so a short/foreign file can't produce an invalid config.
  factory UserConfig.fromJson(Map<String, dynamic> json) {
    final rawButtons = (json['buttonConfigs'] as List?) ?? const [];
    final buttons = List<ButtonConfig>.generate(buttonNum, (i) {
      if (i < rawButtons.length) {
        return ButtonConfig.fromJson(Map<String, dynamic>.from(rawButtons[i] as Map));
      }
      return ButtonConfig(
        keycodes: List.generate(clickNum, (_) => HIDKeyboardReport(modifier: 0, keycodes: const [])),
        timingDoubleClickMs: defaultDoubleClickMs,
        timingLongClickMs: defaultLongClickMs,
      );
    });
    return UserConfig(
      timeAutoOffS: (json['timeAutoOffS'] as num?)?.toInt() ?? 0,
      configName: (json['configName'] as String?) ?? '',
      buttonConfigs: buttons,
      inUse: (json['inUse'] as bool?) ?? true,
    );
  }
}

class BLEConfig {
  final int maxConnections;
  final int txPower;

  BLEConfig({required this.maxConnections, this.txPower = defaultBleTxPower});

  Map<String, dynamic> toJson() => {'maxConnections': maxConnections, 'txPower': txPower};

  factory BLEConfig.fromJson(Map<String, dynamic> json) => BLEConfig(
        maxConnections: (json['maxConnections'] as num?)?.toInt() ?? 0,
        txPower: (json['txPower'] as num?)?.toInt() ?? defaultBleTxPower,
      );
}

class DeviceSettings {
  int timestamp = DateTime.now().millisecondsSinceEpoch;
  final int version;
  int configIdx = 0;
  final BLEConfig bleConfig;
  final List<UserConfig> configs; // length: configNum

  DeviceSettings({
    required this.timestamp,
    required this.version,
    required this.configIdx,
    required this.bleConfig,
    required this.configs,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'version': version,
        'configIdx': configIdx,
        'bleConfig': bleConfig.toJson(),
        'configs': configs.map((c) => c.toJson()).toList(),
      };

  /// Rebuilds a fixed-length [configNum] config list, padding missing slots with
  /// defaults so a short/foreign file can't desync the slot indices.
  factory DeviceSettings.fromJson(Map<String, dynamic> json) {
    final rawConfigs = (json['configs'] as List?) ?? const [];
    final configs = List<UserConfig>.generate(configNum, (i) {
      if (i < rawConfigs.length) {
        return UserConfig.fromJson(Map<String, dynamic>.from(rawConfigs[i] as Map));
      }
      return _defaultUserConfig();
    }, growable: false);
    final ble = json['bleConfig'];
    return DeviceSettings(
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      version: (json['version'] as num?)?.toInt() ?? 0,
      configIdx: (json['configIdx'] as num?)?.toInt() ?? 0,
      bleConfig: ble is Map ? BLEConfig.fromJson(Map<String, dynamic>.from(ble)) : BLEConfig(maxConnections: 0),
      configs: configs,
    );
  }
}

DeviceSettings parseBleSettings(String input) {
  input = input.trim();

  // Remove echoed command for clean parsing
  final cleanedInput = input.replaceFirst(RegExp(r'^\$.+?\$'), '');

  // Extract each ~...<...>* block
  final entries = cleanedInput.split('*').where((e) => e.contains('~')).toList();

  int version = 0;
  int configIdx = 0;
  int maxConnections = 0;
  int txPower = defaultBleTxPower;
  final configMap = <int, Map<String, dynamic>>{};

  for (final raw in entries) {
    final line = raw.trim();
    if (!line.startsWith('~')) continue;

    final match = RegExp(r'^~(.+?)<(.+)>$').firstMatch(line);
    if (match == null) continue;

    final key = match.group(1)!;
    final value = match.group(2)!;

    if (key == 'VERSION') {
      version = int.parse(value);
      continue;
    }

    if (key == 'BLE_MAX_CON') {
      maxConnections = int.parse(value);
      continue;
    }

    if (key == 'BLE_TX') {
      txPower = int.parse(value);
      continue;
    }

    if (key == 'CFG') {
      configIdx = int.parse(value);
      continue;
    }

    final parts = key.split('-');
    final prefix = parts[0];
    final indices = parts.length > 1 ? parts.sublist(1).map(int.parse).toList() : [];

    if (indices.isEmpty || indices[0] >= configNum) continue;

    final cfgIndex = indices[0];
    configMap.putIfAbsent(
        cfgIndex,
        () => {
              'timeAutoOffS': 0,
              'configName': '',
              'inUse': false,
              'buttonConfigs': List.generate(
                  buttonNum,
                  (_) => {
                        'keycodes': List<HIDKeyboardReport?>.filled(clickNum, null),
                        'dc': 0,
                        'lc': 0,
                      }),
            });

    final cfg = configMap[cfgIndex]!;

    switch (prefix) {
      case 'A':
        cfg['timeAutoOffS'] = int.parse(value);
        break;
      case 'C':
        cfg['configName'] = value;
        break;
      case 'U':
        cfg['inUse'] = value == '1';
        break;
      case 'K':
        final buttonIndex = indices[1];
        final clickIndex = indices[2];
        final report = HIDKeyboardReport.fromCsv(value);
        (cfg['buttonConfigs'][buttonIndex]['keycodes'] as List)[clickIndex] = report;
        break;
      case 'DC':
        cfg['buttonConfigs'][indices[1]]['dc'] = int.parse(value);
        break;
      case 'LC':
        cfg['buttonConfigs'][indices[1]]['lc'] = int.parse(value);
        break;
    }
  }

  // One distinct instance per slot — unused slots (now omitted from the device
  // response) must not share a single mutable default, or editing one would
  // change them all.
  final configs = List<UserConfig>.generate(configNum, (_) => _defaultUserConfig(), growable: false);

  for (final entry in configMap.entries) {
    final cfgIndex = entry.key;
    final data = entry.value;
    final buttons = <ButtonConfig>[];

    for (final btn in data['buttonConfigs']) {
      buttons.add(ButtonConfig(
        keycodes: List<HIDKeyboardReport>.from(btn['keycodes']),
        timingDoubleClickMs: btn['dc'],
        timingLongClickMs: btn['lc'],
      ));
    }

    configs[cfgIndex] = UserConfig(
      timeAutoOffS: data['timeAutoOffS'],
      configName: data['configName'],
      buttonConfigs: buttons,
      inUse: data['inUse'] as bool,
    );
  }

  return DeviceSettings(
    timestamp: DateTime.now().millisecondsSinceEpoch,
    version: version,
    configIdx: configIdx,
    bleConfig: BLEConfig(maxConnections: maxConnections, txPower: txPower),
    configs: configs,
  );
}

UserConfig _defaultUserConfig() {
  // Fresh instances per button so editing one button doesn't affect the others.
  ButtonConfig defaultButton() => ButtonConfig(
        keycodes: [
          HIDKeyboardReport(modifier: 0, keycodes: [_defaultHidArrowRight]), // single
          HIDKeyboardReport(modifier: 0, keycodes: [_defaultHidArrowLeft]), // double
          HIDKeyboardReport(modifier: 0, keycodes: [_defaultHidHome]), // triple
          HIDKeyboardReport(modifier: 0, keycodes: []), // long press: none
        ],
        timingDoubleClickMs: defaultDoubleClickMs,
        timingLongClickMs: defaultLongClickMs,
      );

  return UserConfig(
    timeAutoOffS: 0,
    configName: '',
    buttonConfigs: List.generate(buttonNum, (_) => defaultButton()),
  );
}
