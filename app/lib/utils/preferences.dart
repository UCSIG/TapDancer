/// Storage paths:
///   - windows: %APPDATA%\com.UCSIG\tapdancer\shared_preferences.json
library;

import 'dart:async' show Future;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapdancer/models/tapdancer_device.dart';

class PreferencesManager {
  static String bleDevicesKey = "bleDevices";
  static String autoBackupKey = "autoBackupOnConnect";

  static SharedPreferences? _instance;
  static Future<SharedPreferences> init() async => _instance = await SharedPreferences.getInstance();

  /* -------------------------------- SETTERS ------------------------------- */
  /// Persists the saved devices. Only id (the map key), name and auto-connect
  /// flag are stored — all live connection state is rebuilt at runtime.
  static Future<void> setDevices(List<TapDancerDevice> devices) async {
    final map = {for (final d in devices) d.id: d.toJson()};
    await _instance?.setString(bleDevicesKey, jsonEncode(map));
  }

  /// Whether configurations are automatically backed up each time a device
  /// connects (see [BackupManager]).
  static Future<void> setAutoBackupEnabled(bool enabled) async => await _instance?.setBool(autoBackupKey, enabled);

  /* -------------------------------- GETTERS ------------------------------- */
  static List<TapDancerDevice> getDevices() {
    final raw = _instance?.getString(bleDevicesKey);
    if (raw == null || raw.isEmpty) return [];

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return [];
    }

    return decoded.entries.map((e) => TapDancerDevice.fromJson(e.key, (e.value as Map<String, dynamic>?) ?? {})).toList();
  }

  /// Defaults to enabled: automatic backups are a non-destructive safety net,
  /// so they should protect the user without an explicit opt-in.
  static bool getAutoBackupEnabled() => _instance?.getBool(autoBackupKey) ?? true;

  /* ------------------------------- UTILITIES ------------------------------ */
  static Future<void> clear() async => await _instance?.clear();
}
