import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:logger/logger.dart';
import 'package:tapdancer/models/device_settings.dart';
import 'package:tapdancer/models/tapdancer_device.dart';
import 'package:tapdancer/utils/backup_manager.dart';
import 'package:tapdancer/utils/ble_command.dart';
import 'package:tapdancer/utils/logger.dart';
import 'package:tapdancer/utils/preferences.dart';
import 'package:tapdancer/utils/utils.dart';

enum ConnectErrors {
  success,
  scanTimeout,
  serviceNotFound,
  connectionFailed,
  alreadyConnected,
  inProgress,
  deviceNotFound,
}

enum SendCommandErrors {
  success,
  deviceNotFound,
  deviceNotConnected,
  failedToWrite,
  retryFailed,
}

/* -------------------------------- SETTINGS -------------------------------- */
/// The maximum age of a ble scan result until it is no longer regarded as valid in ms.
const bleScanResultMaxAgeMs = 10000;

/// The maximum time to wait for a ble device to be scanned in ms.
const bleScanWaitTimeoutMs = 10000;

/// The name filter for the ble scan.
const bleScanNameFilter = "TapDancer ";

/// Advertised name of a device sitting in the Adafruit nRF52 bootloader.
const dfuAdvertisedNamePrefix = "AdaDFU";

/// How often to send a command to reset the auto off timer.
const periodicAutoOffTimerMs = 10000;

/// How often to read the live RSSI of connected devices.
const periodicRssiReadMs = 1500;

// ── State ─────────────────────────────────────────────────────────────────────

class BLEState {
  /// All known devices (saved + nearby), in stable insertion order.
  final List<TapDancerDevice> devices;

  /// Empty or the id of a connected device.
  final String selectedDeviceId;

  /// Latest Bluetooth adapter/permission state.
  final AvailabilityState availability;

  const BLEState({
    this.devices = const [],
    this.selectedDeviceId = '',
    this.availability = AvailabilityState.unknown,
  });

  /// Adapter is on and we're authorized — scanning/connecting is possible.
  bool get bleReady => availability == AvailabilityState.poweredOn;

  /// Bluetooth permission denied.
  bool get blePermissionDenied => availability == AvailabilityState.unauthorized;

  /// Bluetooth is supported & authorized but turned off.
  bool get bleOff => availability == AvailabilityState.poweredOff;

  /// This device has no Bluetooth LE support at all.
  bool get bleUnsupported => availability == AvailabilityState.unsupported;

  List<TapDancerDevice> get connectedDevices => devices.where((d) => d.connected).toList();
  int get connectionCount => connectedDevices.length;
  int get shouldConnectionCount => devices.where((d) => d.autoConnect).length;

  /// True while any device is mid connect+setup.
  bool get setupOngoing => devices.any((d) => d.setupOngoing);

  /// Case-insensitive lookup by id.
  TapDancerDevice? deviceById(String id) {
    final n = id.toLowerCase();
    for (final d in devices) {
      if (d.id.toLowerCase() == n) return d;
    }
    return null;
  }

  TapDancerDevice? get selectedDevice => deviceById(selectedDeviceId);
}

// ── Notifier ────────────────────────────────────────────────────────────────

class BLENotifier extends StateNotifier<BLEState> {
  final Logger _logger = Log.instance;

  // Send/receive commands.
  final BLECommand _bleCommand = BLECommand();

  /// All devices keyed by lowercased id; snapshotted into [BLEState] by [_emit].
  final Map<String, TapDancerDevice> _devices = {};

  String _selectedDeviceId = '';
  AvailabilityState _availability = AvailabilityState.unknown;
  Timer? _autoOffTimer;
  Timer? _rssiTimer;

  // Ble service and characteristic ids.
  static const String _uartService = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  static const String _uartRxNotifyChar = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
  static const String _uartTxWriteChar = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";

  // Standard Battery Service: one 0-100 byte, pushed via notifications.
  static const String _batteryService = "0000180f-0000-1000-8000-00805f9b34fb";
  static const String _batteryLevelChar = "00002a19-0000-1000-8000-00805f9b34fb";

  // Ble settings.
  static const int _bleMtu = 517;
  static const int _sendRetries = 3;
  static const int _sendDelayMs = 50;

  /// Max wait for the disconnect confirmation (Windows may never send it).
  static const Duration _disconnectTimeout = Duration(seconds: 4);

  /// True while [connectAllDevices] runs, so startup and availability changes
  /// don't start overlapping passes.
  bool _autoConnectRunning = false;

  /// Backoff for scan-driven reconnects after failed attempts.
  static const Duration _reconnectBackoffBase = Duration(seconds: 2);
  static const Duration _reconnectBackoffMax = Duration(seconds: 60);

  /// Reconnect backoff state per device.
  final Map<String, ({int failures, DateTime nextAttempt})> _reconnectBackoff = {};

  /* ------------------------------ CONSTRUCTOR ----------------------------- */
  BLENotifier({required List<TapDancerDevice> devices}) : super(const BLEState()) {
    for (final d in devices) {
      d.resetTransient();
      _devices[d.id.toLowerCase()] = d;
    }
    _initBle();
    _emit();
  }

  @override
  void dispose() {
    _autoOffTimer?.cancel();
    _rssiTimer?.cancel();
    super.dispose();
  }

  TapDancerDevice? _deviceById(String id) => _devices[id.toLowerCase()];

  String _dbg(TapDancerDevice d) => "${d.name} (${d.id})";

  /// Publishes the device map as a new [BLEState].
  void _emit() {
    _ensureValidSelection();
    state = BLEState(
      devices: List.of(_devices.values),
      selectedDeviceId: _selectedDeviceId,
      availability: _availability,
    );
  }

  /// Keeps [_selectedDeviceId] empty or pointing at a connected device.
  void _ensureValidSelection() {
    final sel = _deviceById(_selectedDeviceId);
    if (sel != null && sel.connected) return;
    TapDancerDevice? firstConnected;
    for (final d in _devices.values) {
      if (d.connected) {
        firstConnected = d;
        break;
      }
    }
    _selectedDeviceId = firstConnected?.id ?? '';
  }

  /* ----------------------------- BLE LIFECYCLE ---------------------------- */
  void _initBle() {
    UniversalBle.queueType = QueueType.global;
    UniversalBle.timeout = const Duration(seconds: 3);

    UniversalBle.onAvailabilityChange = _onAvailabilityChange;
    UniversalBle.onQueueUpdate = (id, remaining) => _logger.t("Queue: $id - $remaining");
    UniversalBle.onScanResult = _onScanResult;
    UniversalBle.onConnectionChange = _onConnectionChange;
    UniversalBle.onValueChange = _onValueChange;

    // Periodically refresh the auto-off timer on every connected device.
    _autoOffTimer = Timer.periodic(
      const Duration(milliseconds: periodicAutoOffTimerMs),
      (_) => _refreshAutoOff(),
    );

    // Periodically read the live RSSI of every connected device.
    _rssiTimer = Timer.periodic(
      const Duration(milliseconds: periodicRssiReadMs),
      (_) => _refreshRssi(),
    );
  }

  /// Resumes auto-connect when BLE powers back on.
  void _onAvailabilityChange(AvailabilityState s) {
    _logger.d("BLE availability: ${s.name}");
    final wasReady = _availability == AvailabilityState.poweredOn;
    _availability = s;
    _emit();
    if (s == AvailabilityState.poweredOn && !wasReady) {
      connectAllDevices();
    }
  }

  /// Requests permissions and starts auto-connect if BLE is on.
  Future<void> startConnection() async {
    if (!await _ensurePermissions()) return;

    _availability = await UniversalBle.getBluetoothAvailabilityState();
    _emit();

    if (_availability == AvailabilityState.poweredOff) {
      // Prompts on Android; elsewhere we resume via onAvailabilityChange.
      await UniversalBle.enableBluetooth(timeout: const Duration(minutes: 30));
      return;
    }
    if (_availability != AvailabilityState.poweredOn) return;

    await connectAllDevices();
  }

  /// Asks the OS to enable Bluetooth (Android only; no-op elsewhere).
  Future<void> enableBluetooth() async {
    try {
      await UniversalBle.enableBluetooth();
    } catch (e) {
      _logger.e("enableBluetooth failed: $e");
    }
  }

  Future<bool> _ensurePermissions() async {
    try {
      await UniversalBle.requestPermissions();
      return true;
    } catch (e) {
      _logger.e("BLE permissions denied: $e");
      _availability = AvailabilityState.unauthorized;
      _emit();
      return false;
    }
  }

  /* -------------------------- CONNECTION HANDLING ------------------------- */
  Future<void> connectAllDevices() async {
    if (_autoConnectRunning) return;
    _autoConnectRunning = true;
    try {
      await _connectAllDevices();
    } finally {
      _autoConnectRunning = false;
    }
  }

  Future<void> _connectAllDevices() async {
    if (_availability != AvailabilityState.poweredOn) {
      _availability = await UniversalBle.getBluetoothAvailabilityState();
      if (_availability != AvailabilityState.poweredOn) {
        _logger.d("Bluetooth not powered on (${_availability.name}); skipping auto-connect.");
        _emit();
        return;
      }
    }

    final autoConnectCount = _devices.values.where((d) => d.autoConnect).length;
    _logger.d("Auto-connecting devices ($autoConnectCount / ${_devices.length}).");

    await _startScan();

    // Devices the OS is already connected to don't show up in scans. They
    // still need a regular connect() so the plugin attaches to them.
    final systemIds = <String>{};
    try {
      final systemDevices = await UniversalBle.getSystemDevices(withServices: []);
      for (final sys in systemDevices) {
        final name = sys.name;
        if (name == null || !name.contains(bleScanNameFilter)) continue;
        final key = sys.deviceId.toLowerCase();
        final d = _devices[key] ?? (_devices[key] = TapDancerDevice(id: sys.deviceId, name: name));
        d.bleDevice = sys;
        systemIds.add(key);
      }
      _emit();
    } catch (e) {
      _logger.e("getSystemDevices failed: $e");
    }

    // Snapshot: callbacks may mutate the map.
    for (final d in _devices.values.toList()) {
      if (!d.autoConnect && !systemIds.contains(d.id.toLowerCase())) continue;
      await connectDevice(d.id);
    }

    _logger.d("Auto-connect pass finished.");
  }

  Future<void> _startScan() async {
    if (_availability != AvailabilityState.poweredOn) return;
    try {
      // Android throttles frequent scan starts, so don't restart a running scan.
      if (await UniversalBle.isScanning()) return;
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withNamePrefix: [bleScanNameFilter, dfuAdvertisedNamePrefix]),
      );
    } catch (e) {
      _logger.e("startScan failed: $e");
    }
  }

  void _onScanResult(BleDevice result) {
    final name = result.name;
    if (name == null) return;

    final key = result.deviceId.toLowerCase();
    var d = _devices[key];
    if (d == null) {
      d = TapDancerDevice(id: result.deviceId, name: name);
      _devices[key] = d;
    } else if (name.isNotEmpty) {
      d.name = name;
    }
    d.bleDevice = result;
    d.scantimeMs = DateTime.now().millisecondsSinceEpoch;
    _emit();

    _logger.t("Scan: ${d.name} - ${d.id} - ${result.rssi}dBm");

    // Auto-(re)connect whenever a wanted device reappears nearby.
    if (d.autoConnect && d.reconnect && !d.connected && !d.setupOngoing) {
      reconnectDevice(d.id);
    }
  }

  void _onConnectionChange(BleConnectionChange change) {
    final deviceId = change.deviceId;
    final isConnected = change.isConnected;
    final error = change.error;
    final d = _deviceById(deviceId);
    if (d == null) {
      // Untracked device (e.g. other OS-bonded device).
      _logger.d("Connection change for untracked device $deviceId (ignored).");
      return;
    }

    _logger.d(
      '${_dbg(d)}: ${isConnected ? "connected" : "disconnected"}'
      '${error != null ? ' - error: $error' : ''}',
    );

    d.connected = isConnected;
    if (!isConnected) {
      d.setupOngoing = false;
      d.disconnecting = false;
      d.liveRssi = null;
      d.settings = null;
      d.connections = const [];
      d.info = TapDancerDevice.defaultInfo();
    }
    _emit();

    // Keep scanning so we reconnect when a wanted device reappears.
    if (!isConnected && d.autoConnect && d.reconnect) {
      _startScan();
    }
  }

  Future<ConnectErrors> connectDevice(String deviceId) async {
    final d = _deviceById(deviceId);
    if (d == null) {
      _logger.e("connectDevice: untracked device $deviceId");
      return ConnectErrors.deviceNotFound;
    }

    if (d.connected) {
      _logger.d("Already connected to ${_dbg(d)}");
      d.setupOngoing = false;
      _emit();
      return ConnectErrors.alreadyConnected;
    }
    if (d.setupOngoing || d.disconnecting) {
      _logger.d("Connect/disconnect already in progress for ${_dbg(d)}");
      return ConnectErrors.inProgress;
    }

    d.reconnect = true;
    d.setupOngoing = true;
    _emit();

    // System-connected devices don't advertise to us; everything else must
    // have been seen recently so we only connect to devices in range.
    if (d.bleDevice?.isSystemDevice != true) {
      final scan = await _checkScanResult(d);
      if (scan != ConnectErrors.success) {
        _logger.e("Failed to find ${_dbg(d)}: $scan");
        d.setupOngoing = false;
        _emit();
        return scan;
      }
    }

    try {
      _logger.d("Connecting to ${_dbg(d)}...");
      await UniversalBle.connect(d.id);
      d.connected = true;
      _emit();
      _logger.d("Connected to ${_dbg(d)}");

      if (!await setupDevice(d.id)) {
        // UART service unusable: drop the half-open connection.
        d.setupOngoing = false;
        _logger.e("Service setup failed for ${_dbg(d)}; disconnecting.");
        await disconnectDevice(d.id, stopReconnect: false);
        return ConnectErrors.serviceNotFound;
      }

      // New devices default to auto-connect; known devices keep their setting.
      if (!d.saved) {
        d.saved = true;
        d.autoConnect = true;
        d.reconnect = true;
        await _persistDevices();
      }

      d.setupOngoing = false;
      _emit();
      return ConnectErrors.success;
    } catch (e) {
      d.connected = false;
      d.setupOngoing = false;
      _emit();
      _logger.e("Failed to connect to ${_dbg(d)}: $e");
      return ConnectErrors.connectionFailed;
    }
  }

  /// Waits for a fresh scan sighting so we only connect to devices in range.
  Future<ConnectErrors> _checkScanResult(TapDancerDevice d) async {
    final start = DateTime.now().millisecondsSinceEpoch;
    while (DateTime.now().millisecondsSinceEpoch - d.scantimeMs > bleScanResultMaxAgeMs) {
      if (DateTime.now().millisecondsSinceEpoch - start > bleScanWaitTimeoutMs) {
        return ConnectErrors.scanTimeout;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _logger.d("Found device: ${_dbg(d)}");
    return ConnectErrors.success;
  }

  /// Discovers services and requests the initial state. Returns false if the
  /// UART service can't be set up.
  Future<bool> setupDevice(String deviceId) async {
    final d = _deviceById(deviceId);
    if (d == null || !d.connected) return false;

    _logger.d("Setting up ${_dbg(d)}...");
    d.backupPendingOnConnect = true;
    try {
      await UniversalBle.discoverServices(d.id);
      await UniversalBle.subscribeNotifications(d.id, _uartService, _uartRxNotifyChar);
      if (Platform.isAndroid) {
        await UniversalBle.requestMtu(d.id, _bleMtu);
      }
    } catch (e) {
      _logger.e("Setup failed for ${_dbg(d)}: $e");
      return false;
    }

    await _setupBatteryService(d);

    await _sendRetry(d.id, BLECommand.setAutoOffRefresh());
    await _sendRetry(d.id, BLECommand.getInfo());
    await _sendRetry(d.id, BLECommand.getConfigurations(false));
    await _sendRetry(d.id, BLECommand.getConnections());
    return true;
  }

  /// Subscribes to battery notifications and reads the initial level (optional).
  Future<void> _setupBatteryService(TapDancerDevice d) async {
    try {
      await UniversalBle.subscribeNotifications(d.id, _batteryService, _batteryLevelChar);
      final initial = await UniversalBle.read(d.id, _batteryService, _batteryLevelChar);
      _updateBatteryLevel(d, initial);
    } catch (e) {
      _logger.d("Battery service unavailable for ${_dbg(d)}: $e");
    }
  }

  /// Parses a battery level (one 0-100 byte).
  void _updateBatteryLevel(TapDancerDevice d, Uint8List value) {
    if (value.isEmpty) return;
    final level = value[0];
    if (level > 100) return;
    if (d.batteryLevel == level) return;
    d.batteryLevel = level;
    _logger.d("${d.name} battery: $level%");
    _emit();
  }

  /// Best-effort automatic backup on connect, if enabled.
  Future<void> _backupOnConnect(TapDancerDevice d, DeviceSettings settings) async {
    if (!PreferencesManager.getAutoBackupEnabled()) return;
    try {
      final file = await saveBackup(d.backupKey, settings, appVersion: PackageInformation.getAppVersionString());
      if (file != null) _logger.d("Backed up config for ${_dbg(d)} to ${file.path}");
    } catch (e) {
      _logger.e("Auto-backup failed for ${_dbg(d)}: $e");
    }
  }

  Future<void> disconnectDevice(String deviceId, {bool stopReconnect = true}) async {
    final d = _deviceById(deviceId);
    if (d == null) return;

    if (stopReconnect) d.reconnect = false;
    if (d.disconnecting) return;

    // Mark disconnected immediately to stop periodic traffic to the device.
    d.disconnecting = true;
    d.connected = false;
    d.setupOngoing = false;
    d.liveRssi = null;
    _emit();

    try {
      await UniversalBle.disconnect(d.id, timeout: _disconnectTimeout);
      _logger.d("Disconnected from ${_dbg(d)}");
    } catch (e) {
      _logger.e("Failed to disconnect from ${_dbg(d)}: $e");
    }

    d.connected = false;
    d.setupOngoing = false;
    d.disconnecting = false;
    d.settings = null;
    d.connections = const [];
    d.info = TapDancerDevice.defaultInfo();
    _emit();

    if (d.autoConnect && d.reconnect) _startScan();
  }

  /// Scan-driven reconnect with exponential backoff after failures.
  /// [resetBackoff] skips the wait (user-initiated).
  Future<void> reconnectDevice(String deviceId, {bool resetBackoff = false}) async {
    final d = _deviceById(deviceId);
    if (d == null || d.connected || d.setupOngoing || d.disconnecting || !d.reconnect) {
      return;
    }
    final key = d.id.toLowerCase();
    if (resetBackoff) _reconnectBackoff.remove(key);
    final backoff = _reconnectBackoff[key];
    if (backoff != null && DateTime.now().isBefore(backoff.nextAttempt)) return;

    _logger.d("Reconnecting to ${_dbg(d)}");
    final result = await connectDevice(d.id);
    if (result == ConnectErrors.success || result == ConnectErrors.alreadyConnected) {
      _reconnectBackoff.remove(key);
    } else if (result != ConnectErrors.inProgress) {
      final failures = (backoff?.failures ?? 0) + 1;
      final delayMs = (_reconnectBackoffBase.inMilliseconds * (1 << (failures - 1).clamp(0, 16)))
          .clamp(0, _reconnectBackoffMax.inMilliseconds);
      _reconnectBackoff[key] = (
        failures: failures,
        nextAttempt: DateTime.now().add(Duration(milliseconds: delayMs)),
      );
      _logger.d("Reconnect to ${_dbg(d)} failed ($result); next attempt in ${delayMs ~/ 1000}s.");
    }
  }

  /* ----------------------------- BLE MESSAGES ----------------------------- */
  Future<SendCommandErrors> sendCommand(String deviceId, Uint8List command, bool withResponse) async {
    final d = _deviceById(deviceId);
    if (d == null) {
      _logger.e("Failed to send command ${utf8.decode(command)} to '$deviceId': device not found.");
      return SendCommandErrors.deviceNotFound;
    }
    if (!d.connected || d.disconnecting) {
      return SendCommandErrors.deviceNotConnected;
    }

    try {
      await UniversalBle.write(
        d.id,
        _uartService,
        _uartTxWriteChar,
        command,
        withoutResponse: !withResponse,
      );
      return SendCommandErrors.success;
    } on UniversalBleException catch (e) {
      // Link is down: the connection-change event updates state, no retry.
      if (e.code == UniversalBleErrorCode.deviceDisconnected ||
          e.code == UniversalBleErrorCode.operationCancelled) {
        return SendCommandErrors.deviceNotConnected;
      }
      _logger.e("Failed to send command ${utf8.decode(command).trim()} to ${_dbg(d)}: $e");
      return SendCommandErrors.failedToWrite;
    } catch (e) {
      _logger.e("Failed to send command ${utf8.decode(command).trim()} to ${_dbg(d)}: $e");
      return SendCommandErrors.failedToWrite;
    }
  }

  /// Sends [command] with bounded retries.
  Future<SendCommandErrors> _sendRetry(String deviceId, Uint8List command) async {
    for (int i = 0; i < _sendRetries; i++) {
      final r = await sendCommand(deviceId, command, true);
      if (r == SendCommandErrors.success) return r;
      if (r == SendCommandErrors.deviceNotFound || r == SendCommandErrors.deviceNotConnected) return r;
      await Future.delayed(const Duration(milliseconds: _sendDelayMs));
    }
    return SendCommandErrors.retryFailed;
  }

  Future<void> _refreshAutoOff() async {
    for (final d in _devices.values.toList()) {
      if (d.connected && !d.disconnecting && !d.setupOngoing) {
        await sendCommand(d.id, BLECommand.setAutoOffRefresh(), true);
      }
    }
  }

  /// Polls live RSSI (Android/iOS/macOS only).
  Future<void> _refreshRssi() async {
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) return;

    for (final d in _devices.values.toList()) {
      if (!d.connected || d.disconnecting) continue;

      try {
        final rssi = await UniversalBle.readRssi(d.id);
        if (d.liveRssi != rssi) {
          d.liveRssi = rssi;
          _emit();
        }
      } catch (e) {
        _logger.t("readRssi failed for ${_dbg(d)}: $e");
      }
    }
  }

  /* ---------------------------- CONFIG IMPORT ----------------------------- */
  /// Writes [config] into slot [configIdx] using the editor's setter commands.
  /// Pass [save]/[refresh] = false when batching (see [applyUserConfigs]).
  Future<bool> applyUserConfig(
    String deviceId,
    int configIdx,
    UserConfig config, {
    bool save = true,
    bool refresh = true,
  }) async {
    final d = _deviceById(deviceId);
    if (d == null || !d.connected) return false;
    if (configIdx < 0 || configIdx >= configNum) return false;

    Future<bool> send(Uint8List cmd) async => await _sendRetry(deviceId, cmd) == SendCommandErrors.success;

    if (!await send(BLECommand.setConfigName(configIdx, config.configName, false))) return false;
    if (!await send(BLECommand.setAutoOffTime(configIdx, config.timeAutoOffS, false))) return false;

    for (int b = 0; b < config.buttonConfigs.length && b < buttonNum; b++) {
      final btn = config.buttonConfigs[b];
      final buttonType = ButtonType.values[b];
      if (!await send(BLECommand.setButtonClickTiming(configIdx, buttonType, btn.timingDoubleClickMs, btn.timingLongClickMs, false))) {
        return false;
      }
      for (int c = 0; c < btn.keycodes.length && c < clickNum; c++) {
        // Pad to the 6-slot HID report the firmware expects.
        final padded = [...btn.keycodes[c].keycodes, 0, 0, 0, 0, 0, 0].sublist(0, 6);
        final report = HIDKeyboardReport(modifier: btn.keycodes[c].modifier, keycodes: padded);
        if (!await send(BLECommand.setKeycodes(configIdx, buttonType, ClickType.values[c], report, false))) {
          return false;
        }
      }
    }

    if (save) await send(BLECommand.setSaveSettings());
    if (refresh) await _sendRetry(deviceId, BLECommand.getConfigurations(false));
    return true;
  }

  /// Writes several configs, then saves and refreshes once.
  Future<bool> applyUserConfigs(String deviceId, Map<int, UserConfig> configsByIndex) async {
    final d = _deviceById(deviceId);
    if (d == null || !d.connected) return false;

    var ok = true;
    for (final entry in configsByIndex.entries) {
      final applied = await applyUserConfig(deviceId, entry.key, entry.value, save: false, refresh: false);
      ok = ok && applied;
    }
    await _sendRetry(deviceId, BLECommand.setSaveSettings());
    await _sendRetry(deviceId, BLECommand.getConfigurations(false));
    return ok;
  }

  void _onValueChange(BleCharacteristicValue event) {
    final deviceId = event.deviceId;
    final characteristicId = event.characteristicId;
    final value = event.value;
    final timestamp = event.timestamp;
    final d = _deviceById(deviceId);
    if (d == null) return;

    // Battery Service notifications are raw level bytes, not UART responses.
    if (BleUuidParser.compareStrings(characteristicId, _batteryLevelChar)) {
      _updateBatteryLevel(d, value);
      return;
    }

    final response = _bleCommand.parseResponse(value);
    final Command command = response["command"] as Command;
    final Map<String, dynamic> r = (response["response"] as Map<String, dynamic>?) ?? {};

    _logger.t("${d.name}:\n$r");

    if (r.containsKey("ACK")) {
      final ack = (int.tryParse(r["ACK"].toString()) ?? 0) == 1;
      _logger.d("${ack ? 'ACK' : 'NACK'}: $command");
      return;
    }

    switch (command) {
      /* -------------------------- PUSH COMMANDS ------------------------- */
      case Command.cmdPushKeyclick:
        _logger.d("Keyclick received. $r");
        final clickBtn = int.tryParse(r["button"].toString());
        final click = int.tryParse(r["value"].toString());
        if (clickBtn != null && click != null && clickBtn < ButtonType.values.length && click < ClickType.values.length) {
          d.lastKeyEvent = LastKeyEvent(
            button: ButtonType.values[clickBtn],
            click: ClickType.values[click],
            timeMs: timestamp ?? DateTime.now().millisecondsSinceEpoch,
          );
          _emit();
        }
        break;
      case Command.cmdPushKeypress:
        _logger.d("Keypress received. $r");
        final pressBtn = int.tryParse(r["button"].toString());
        final pressed = int.tryParse(r["value"].toString());
        if (pressBtn != null && pressed != null && pressBtn < ButtonType.values.length) {
          d.lastKeyEvent = LastKeyEvent(
            button: ButtonType.values[pressBtn],
            pressed: pressed == 1,
            timeMs: timestamp ?? DateTime.now().millisecondsSinceEpoch,
          );
          _emit();
        }
        break;
      case Command.cmdPushConfig:
        _logger.d("Config index received. $r");
        break;

      /* -------------------------- GET RESPONSES ------------------------- */
      case Command.cmdGetInformation:
        _logger.d("Information received. $r");
        d.info = r;
        _emit();
        break;

      case Command.cmdGetConfigurations:
        _logger.d("Configuration received.");
        final settings = r["settings"];
        if (settings is DeviceSettings) {
          d.settings = settings;
          _emit();

          if (d.backupPendingOnConnect) {
            d.backupPendingOnConnect = false;
            _backupOnConnect(d, settings);
          }
        }
        break;

      case Command.cmdGetConnections:
        _logger.d("Connections received. $r");
        d.connections = _parseConnections(r);
        _emit();
        break;

      /* ------------------------- CHUNKED PACKETS ------------------------ */
      case Command.cmdReceptionInProgress:
        break;

      default:
        _logger.d("Unknown command received: $response");
    }
  }

  /// Parses `G#CONS`: parallel DEV / MAC / BND lists, aligned by index.
  List<DeviceConnection> _parseConnections(Map<String, dynamic> r) {
    List<String> asList(dynamic v) => (v is List) ? v.map((e) => e.toString()).toList() : const [];
    final names = asList(r['DEV']);
    final macs = asList(r['MAC']);
    final bonds = asList(r['BND']);

    return [
      for (int i = 0; i < names.length; i++)
        DeviceConnection(
          name: names[i],
          mac: i < macs.length ? macs[i] : '',
          bonded: i < bonds.length && bonds[i] == '1',
        ),
    ];
  }

  /* ---------------------------- STATE HANDLING ---------------------------- */
  void setSelectedDeviceId(String deviceId) {
    final d = _deviceById(deviceId);
    if (d == null) return;
    _logger.d("Selected device: ${_dbg(d)}");
    _selectedDeviceId = d.id;
    _emit();
  }

  Future<void> setAutoConnectFlag(String deviceId, bool autoConnect) async {
    final d = _deviceById(deviceId);
    if (d == null) return;
    d.autoConnect = autoConnect;
    if (autoConnect) {
      d.reconnect = true;
      // Auto-connect implies the device is remembered.
      d.saved = true;
    }
    await _persistDevices();
    _emit();
    if (autoConnect && !d.connected) {
      reconnectDevice(d.id, resetBackoff: true);
    }
  }

  Future<void> toggleAutoConnectFlag(String deviceId) async {
    final d = _deviceById(deviceId);
    if (d == null) return;
    await setAutoConnectFlag(deviceId, !d.autoConnect);
  }

  bool getAutoConnectFlag(String deviceId) => _deviceById(deviceId)?.autoConnect ?? false;

  /// Bookmark / forget a device. Forgetting also clears auto-connect.
  Future<void> setSavedFlag(String deviceId, bool saved) async {
    final d = _deviceById(deviceId);
    if (d == null) return;
    d.saved = saved;
    if (!saved) d.autoConnect = false;
    await _persistDevices();
    _emit();
  }

  Future<void> toggleSavedFlag(String deviceId) async {
    final d = _deviceById(deviceId);
    if (d == null) return;
    await setSavedFlag(deviceId, !d.saved);
  }

  bool getSavedFlag(String deviceId) => _deviceById(deviceId)?.saved ?? false;

  /// Sets or clears a custom name. Naming a device also saves it.
  Future<void> setCustomName(String deviceId, String? name) async {
    final d = _deviceById(deviceId);
    if (d == null) return;
    final trimmed = name?.trim();
    d.customName = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    if (d.customName != null) d.saved = true;
    await _persistDevices();
    _emit();
  }

  String? getCustomName(String deviceId) => _deviceById(deviceId)?.customName;

  /// Persists only saved devices.
  Future<void> _persistDevices() async {
    await PreferencesManager.setDevices(_devices.values.where((d) => d.saved).toList());
  }
}

/* -------------------------------- PROVIDER -------------------------------- */
final bleProvider = StateNotifierProvider<BLENotifier, BLEState>((ref) {
  final bleNotifier = BLENotifier(devices: PreferencesManager.getDevices());
  bleNotifier.startConnection();
  return bleNotifier;
});
