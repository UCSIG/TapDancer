import 'package:tapdancer/providers/ble_provider.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:tapdancer/models/device_settings.dart';

/// The most recent button event pushed by the device, used for live feedback in
/// the UI. [click] is set for click events (`P#KEYC`); [pressed] is set for raw
/// press/release events (`P#KEYP`).
class LastKeyEvent {
  final ButtonType button;
  final ClickType? click;
  final bool? pressed;
  final int timeMs;

  const LastKeyEvent({
    required this.button,
    this.click,
    this.pressed,
    required this.timeMs,
  });
}

/// A host currently connected to the TapDancer over BLE, as reported by the
/// `G#CONS` command (e.g. the phone/PC the footswitch sends key events to).
class DeviceConnection {
  final String name;
  final String mac;
  final bool bonded;

  const DeviceConnection({
    required this.name,
    required this.mac,
    required this.bonded,
  });
}

/// A single TapDancer footswitch. Several of these can be connected
/// simultaneously, so the provider keeps a collection of them keyed by [id].
///
/// Only [id], [name] and [autoConnect] are persisted (see
/// `PreferencesManager`). Everything else is transient connection state that is
/// rebuilt on every app start / (re)connect via [resetTransient].
class TapDancerDevice {
  /// BLE device id (platform specific: MAC on Android/Linux, UUID on iOS/macOS).
  final String id;

  /// Advertised name as reported by the device, e.g. `TapDancer AABBCC`.
  String name;

  /// Persisted user-chosen name that overrides [name] in the UI when set.
  String? customName;

  /// Persisted preference: the user has bookmarked this device so it is
  /// remembered across launches even when out of range. Auto-connect implies
  /// saved, but a device can be saved without auto-connecting.
  bool saved;

  /// Persisted preference: reconnect to this device automatically on startup.
  bool autoConnect;

  // ── Transient (never persisted) ────────────────────────────────────────────

  /// Last scan/system result for this device (holds the scan-time RSSI).
  BleDevice? bleDevice;

  /// RSSI actively read from the live GATT connection (via `readRssi`), or null
  /// when not connected / not yet read. Preferred over the stale scan RSSI while
  /// connected. Only populated on platforms that support reading it
  /// (Android/iOS/macOS).
  int? liveRssi;

  bool connected;

  /// Session flag: when false we suppress scan-driven auto-reconnect (e.g. the
  /// user manually disconnected). [autoConnect] is the persisted preference;
  /// this is the in-memory override that resets each launch.
  bool reconnect;

  /// True while a connect+setup sequence is in flight (guards against
  /// concurrent connection attempts and drives the "Connecting..." UI).
  bool setupOngoing;

  /// True while a manual disconnect is in flight (drives the "Disconnecting..."
  /// UI until the device reports disconnected).
  bool disconnecting;

  /// `DateTime.now().millisecondsSinceEpoch` of the last scan sighting.
  int scantimeMs;

  /// Latest parsed configuration from the device (null until fetched).
  DeviceSettings? settings;

  /// Device info reported over UART (MCU_ID, BOOT_VER, SOFT_VER, HARD_VER).
  Map<String, dynamic> info;

  /// Most recent button event pushed by the device (null until one arrives).
  LastKeyEvent? lastKeyEvent;

  /// Latest battery level (0-100%) from the BLE Battery Service, or null until
  /// the first reading arrives.
  int? batteryLevel;

  /// Hosts currently connected to the device (from the last `G#CONS` request).
  List<DeviceConnection> connections;

  /// True from the start of a connect+setup until the first configuration is
  /// fetched, so the auto-backup fires exactly once per connection (and not on
  /// later manual refreshes / imports). Transient.
  bool backupPendingOnConnect;

  TapDancerDevice({
    required this.id,
    required this.name,
    this.customName,
    this.saved = false,
    this.autoConnect = false,
    this.bleDevice,
    this.connected = false,
    this.reconnect = true,
    this.setupOngoing = false,
    this.disconnecting = false,
    this.scantimeMs = 0,
    this.settings,
    this.connections = const [],
    this.backupPendingOnConnect = false,
    Map<String, dynamic>? info,
  }) : info = info ?? defaultInfo();

  static Map<String, dynamic> defaultInfo() => {
        'MCU_ID': '',
        'BOOT_VER': '0',
        'SOFT_VER': '0.0.0.0',
        'HARD_VER': '0.0.0',
      };

  /// Name shown in the UI: the user's custom name when set, else the advertised
  /// name, else the device id.
  String get displayName {
    final custom = customName?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return name.isNotEmpty ? name : id;
  }

  /// Stable key for grouping this device's config backups. Uses the advertised
  /// name (e.g. "TapDancer 6523"), which is fixed per physical device and stable
  /// across connects — unlike [id], which on iOS/macOS is a per-connection
  /// CoreBluetooth UUID that can change. Falls back to [id] if the name is
  /// somehow empty.
  String get backupKey => name.isNotEmpty ? name : id;

  /// Signal strength in dBm: the live connection reading when available, else
  /// the last scan sighting, else a floor value if never seen.
  int get rssi => liveRssi ?? bleDevice?.rssi ?? -100;

  /// Whether a real signal-strength reading is available (vs. the floor value).
  bool get hasRssi => liveRssi != null || bleDevice != null;

  /// True when this is a device sitting in the bootloader (advertising as
  /// [dfuAdvertisedNamePrefix]) rather than a running TapDancer. Such a device
  /// can only be recovered via a firmware (DFU) flash — connecting normally
  /// would fail since it exposes no UART service.
  bool get isDfuMode => name.startsWith(dfuAdvertisedNamePrefix);

  /// Clears all transient connection state (after a restart / disconnect).
  void resetTransient() {
    bleDevice = null;
    liveRssi = null;
    connected = false;
    reconnect = true;
    setupOngoing = false;
    disconnecting = false;
    scantimeMs = 0;
    settings = null;
    info = defaultInfo();
    lastKeyEvent = null;
    batteryLevel = null;
    connections = const [];
    backupPendingOnConnect = false;
  }

  /// Persisted shape (the device id is stored as the map key, so it is not
  /// repeated here). Kept backward compatible with the original storage format.
  Map<String, dynamic> toJson() => {
        'name': name,
        'custom_name': customName,
        'saved': saved,
        'auto_connect': autoConnect,
      };

  factory TapDancerDevice.fromJson(String id, Map<String, dynamic> json) {
    final autoConnect = (json['auto_connect'] as bool?) ?? false;
    return TapDancerDevice(
      id: id,
      name: (json['name'] as String?) ?? '',
      customName: json['custom_name'] as String?,
      // Back-compat: anything previously persisted was a saved device, and
      // auto-connect always implies saved.
      saved: ((json['saved'] as bool?) ?? true) || autoConnect,
      autoConnect: autoConnect,
    );
  }
}
