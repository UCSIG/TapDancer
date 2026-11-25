import 'package:logger/logger.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapdancer/models/device_settings.dart';
import 'package:tapdancer/models/tapdancer_device.dart';
import 'package:tapdancer/providers/ble_provider.dart';
import 'package:tapdancer/screens/firmware_update_screen.dart';
import 'package:tapdancer/utils/app_theme.dart';
import 'package:tapdancer/utils/ble_command.dart';
import 'package:tapdancer/utils/firmware_info.dart';
import 'package:tapdancer/utils/logger.dart';
import 'package:tapdancer/utils/preferences.dart';
import 'package:tapdancer/utils/utils.dart';
import 'package:tapdancer/widgets/app_container.dart';
import 'package:tapdancer/widgets/gradient_scaffold.dart';
import 'package:tapdancer/widgets/app_bar.dart';
import 'package:tapdancer/widgets/device_selector.dart';
import 'package:tapdancer/widgets/misellaneous.dart';

/// Selectable values for the concurrent-connections setting. The firmware
/// supports up to 8, but the UI is capped at 4.
const _maxConnectionOptions = [1, 2, 3, 4];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final Logger _logger = Log.instance;

  // Locally-tracked selections for immediate dropdown feedback, until the device
  // echoes the new value back via G#CFGS. Reset when the selected device changes
  // (see build()).
  int? _selectedTxPower;
  int? _selectedMaxConnections;
  String? _txPowerDeviceId;

  // Global (not per-device) preference, loaded once in initState.
  bool _autoBackup = PreferencesManager.getAutoBackupEnabled();

  void _cancelSubscriptions() {}

  void _startSubscriptions() {
    _cancelSubscriptions();
  }

  @override
  void initState() {
    _logger.d("SettingsScreen: init");
    super.initState();
    _startSubscriptions();
  }

  @override
  void dispose() {
    _logger.d("SettingsScreen: dispose");
    super.dispose();
    _cancelSubscriptions();
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleProvider);
    final connectedDevices = bleState.connectedDevices;
    final setupOngoing = bleState.setupOngoing;
    final selectedDeviceId = bleState.selectedDeviceId;
    final selectedDevice = bleState.selectedDevice;

    if (connectedDevices.isEmpty && !setupOngoing) {
      return buildNoDeviceConnectedScreen();
    }

    // Drop the locally-tracked TX power when switching devices so the dropdown
    // shows the newly selected device's setting rather than a stale selection.
    if (_txPowerDeviceId != selectedDeviceId) {
      _txPowerDeviceId = selectedDeviceId;
      _selectedTxPower = null;
      _selectedMaxConnections = null;
    }

    return GradientScaffold(
      appBar: AppBarWidget(
        title: "Settings",
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Device actions',
            onSelected: (value) => handleDeviceAction(ref, selectedDeviceId, value),
            itemBuilder: (_) => deviceActionMenuItems(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: AppSizing.paddingSmall),

            // Settings tiles scroll when they don't fit; the version indicator
            // is pinned to the bottom of the screen, below the scroll area.
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingXLarge),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /* -------------------- DEVICE NAME --------------------- */
                      _buildSettingsTile(
                        title: "Device Name",
                        subtitle: selectedDevice?.customName != null ? "Custom name: ${selectedDevice!.displayName}" : "Tap to set a custom name for this device.",
                        icon: Icon(
                          Icons.edit_outlined,
                          color: selectedDevice?.customName != null ? Theme.of(context).colorScheme.primary : null,
                        ),
                        onTap: selectedDevice == null ? null : () => _promptRename(selectedDevice),
                      ),
                      /* ---------------- AUTO-CONNECT TOGGLE. ---------------- */
                      _buildSettingsTile(
                        title: "Auto-Connect Device",
                        subtitle: "Automatically try to connect to device on app startup.",
                        icon: Icon(
                          Icons.autorenew,
                          color: ref.read(bleProvider.notifier).getAutoConnectFlag(selectedDeviceId) ? Theme.of(context).colorScheme.primary : null,
                        ),
                        trailing: Switch(
                          value: ref.read(bleProvider.notifier).getAutoConnectFlag(selectedDeviceId),
                          onChanged: (val) => setState(() {
                            ref.read(bleProvider.notifier).setAutoConnectFlag(selectedDeviceId, val);
                          }),
                        ),
                        onTap: null,
                      ),
                      /* -------------------- AUTOMATIC BACKUPS --------------- */
                      _buildSettingsTile(
                        title: "Automatic Backups",
                        subtitle: "Save a backup of the configuration each time a device connects. Restore from the Button Configurations screen.",
                        icon: Icon(
                          Icons.backup_outlined,
                          color: _autoBackup ? Theme.of(context).colorScheme.primary : null,
                        ),
                        trailing: Switch(
                          value: _autoBackup,
                          onChanged: (val) {
                            setState(() => _autoBackup = val);
                            PreferencesManager.setAutoBackupEnabled(val);
                          },
                        ),
                        onTap: null,
                      ),
                      /* -------------------- FIRMWARE UPDATE ----------------- */
                      _buildFirmwareTile(selectedDevice),
                      /* -------------------- CONNECTIONS --------------------- */
                      _buildConnectionsCard(selectedDevice?.connections ?? const []),
                      /* ---------------- CONCURRENT CONNECTIONS -------------- */
                      _buildMaxConnectionsTile(selectedDevice, selectedDeviceId),
                      /* -------------------- BLE TX POWER -------------------- */
                      _buildTxPowerTile(selectedDevice, selectedDeviceId),
                      /* -------------------- RESTART DEVICE -------------------- */
                      _buildSettingsTile(
                        title: "Restart Device",
                        subtitle: "Restart the device without changing any settings.",
                        icon: Icon(
                          Icons.restart_alt,
                        ),
                        onTap: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => Dialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Container(
                                decoration: AppContainer.surface(),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.restart_alt, color: Theme.of(context).colorScheme.primary, size: 32),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              "Restart Device",
                                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 18),
                                      Text(
                                        "Are you sure you want to restart the device? This will restart the device but keep all your settings.",
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                      const SizedBox(height: 24),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () => Navigator.of(ctx).pop(false),
                                            child: const Text("Cancel"),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Theme.of(context).colorScheme.primary,
                                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                            onPressed: () => Navigator.of(ctx).pop(true),
                                            child: const Text("Restart"),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );

                          if (!mounted) return;
                          if (confirmed == true) {
                            ref.read(bleProvider.notifier).sendCommand(
                                  selectedDeviceId,
                                  BLECommand.setReset(false),
                                  true,
                                );
                            // ignore: use_build_context_synchronously
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Device restart done."),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                      /* ---------------- FACTORY RESET DEVICE ---------------- */
                      _buildSettingsTile(
                          title: "Factory Reset Device",
                          subtitle: "Restore all settings to factory defaults.",
                          icon: Icon(
                            Icons.restore,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => Dialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Container(
                                  decoration: AppContainer.surface(),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error, size: 32),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                "Factory Reset Device",
                                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 18),
                                        Text(
                                          "Are you sure you want to factory reset the device? You will lose your custom configuration.\nThis cannot be undone.",
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                        const SizedBox(height: 24),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(false),
                                              child: const Text("Cancel"),
                                            ),
                                            const SizedBox(width: 8),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Theme.of(context).colorScheme.error,
                                                foregroundColor: Theme.of(context).colorScheme.onError,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                              onPressed: () => Navigator.of(ctx).pop(true),
                                              child: const Text("Reset"),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );

                            if (!mounted) return;
                            if (confirmed == true) {
                              ref.read(bleProvider.notifier).sendCommand(
                                    selectedDeviceId,
                                    BLECommand.setFactoryReset(),
                                    true,
                                  );
                              // ignore: use_build_context_synchronously
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Factory reset done."),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          }),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: AppSizing.paddingSmall,
              ),
              child: _buildVersionIndicator(selectedDevice),
            ),
            const SizedBox(height: AppSizing.paddingSmall),
          ],
        ),
      ),
    );
  }

  /// Prompts for a custom device name. An empty value clears the custom name,
  /// reverting to the advertised name.
  Future<void> _promptRename(TapDancerDevice device) async {
    final controller = TextEditingController(text: device.customName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Custom name',
            hintText: device.name.isNotEmpty ? device.name : device.id,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null) return; // cancelled
    ref.read(bleProvider.notifier).setCustomName(device.id, newName);
  }

  /// Dropdown with connected devices
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingXLarge),
      child: DeviceSelector(
        showLabel: false,
        showSignal: true,
      ),
    );
  }

  /// Firmware update tile. Its subtitle reflects whether the bundled firmware
  /// is newer than what's installed on the device.
  Widget _buildFirmwareTile(TapDancerDevice? device) {
    final installed = device?.info['SOFT_VER'] as String?;
    final bundled = ref.watch(bundledFirmwareVersionProvider).asData?.value;
    final updateAvailable = firmwareUpdateAvailable(installed: installed, bundled: bundled);

    final String subtitle;
    if (updateAvailable) {
      subtitle = "Update available: $installed → $bundled";
    } else if (installed != null && bundled != null) {
      subtitle = "Up to date ($installed)";
    } else {
      subtitle = "Install firmware on this device over Bluetooth.";
    }

    return _buildSettingsTile(
      title: "Firmware Update",
      subtitle: subtitle,
      icon: Icon(
        Icons.system_update,
        color: updateAvailable ? AppColor.warning : null,
      ),
      trailing: updateAvailable
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingSmall, vertical: 2),
              decoration: AppContainer.statusBadge(AppColor.warning),
              child: Text('New', style: AppTextStyles.bodySmall.copyWith(color: AppColor.warning)),
            )
          : null,
      onTap: device == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FirmwareUpdateScreen(deviceId: device.id),
                ),
              ),
    );
  }

  /// Maximum simultaneous BLE host connections. Sends S#CFG_BLE_CONS (persisted
  /// to flash) and applies on the device. Capped at 4 in the UI.
  Widget _buildMaxConnectionsTile(TapDancerDevice? device, String selectedDeviceId) {
    final settingsValue = device?.settings?.bleConfig.maxConnections;
    var current = _selectedMaxConnections ?? settingsValue ?? _maxConnectionOptions.first;
    // Guard against an out-of-range value so the dropdown always has a match.
    if (!_maxConnectionOptions.contains(current)) {
      current = current < _maxConnectionOptions.first ? _maxConnectionOptions.first : _maxConnectionOptions.last;
    }
    final enabled = device?.connected ?? false;

    return _buildSettingsTile(
      title: "Concurrent Connections",
      subtitle: "Maximum number of hosts that can stay connected at the same time.",
      icon: Icon(
        Icons.lan_outlined,
      ),
      trailing: DropdownButton<int>(
        value: current,
        underline: const SizedBox.shrink(),
        onChanged: !enabled
            ? null
            : (value) {
                if (value == null) return;
                setState(() => _selectedMaxConnections = value);
                ref.read(bleProvider.notifier).sendCommand(
                      selectedDeviceId,
                      BLECommand.setMaxBleConnections(value, true),
                      true,
                    );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Concurrent connections set to $value."),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
        items: [
          for (final n in _maxConnectionOptions) DropdownMenuItem(value: n, child: Text("$n")),
        ],
      ),
      onTap: null,
    );
  }

  /// BLE TX power selector. Sends S#CFG_BLE_TX (persisted to flash) and applies
  /// immediately on the device. The available levels mirror the firmware's
  /// supported dBm values.
  Widget _buildTxPowerTile(TapDancerDevice? device, String selectedDeviceId) {
    final settingsTxPower = device?.settings?.bleConfig.txPower;
    var currentTxPower = _selectedTxPower ?? settingsTxPower ?? defaultBleTxPower;
    // Guard against an out-of-range value so the dropdown always has a match.
    if (!BLECommand.supportedTxPowers.contains(currentTxPower)) {
      currentTxPower = defaultBleTxPower;
    }
    final enabled = device?.connected ?? false;

    return _buildSettingsTile(
      title: "BLE TX Power",
      subtitle: "Radio transmit power. Higher means more range but more battery use.",
      icon: Icon(
        Icons.settings_input_antenna,
      ),
      trailing: DropdownButton<int>(
        value: currentTxPower,
        underline: const SizedBox.shrink(),
        onChanged: !enabled
            ? null
            : (value) {
                if (value == null) return;
                setState(() => _selectedTxPower = value);
                ref.read(bleProvider.notifier).sendCommand(
                      selectedDeviceId,
                      BLECommand.setTxPower(value, true),
                      true,
                    );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("TX power set to $value dBm."),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
        items: [
          for (final p in BLECommand.supportedTxPowers) DropdownMenuItem(value: p, child: Text("$p dBm")),
        ],
      ),
      onTap: null,
    );
  }

  /// Settings list tile.
  Widget _buildSettingsTile({
    required String title,
    required String subtitle,
    required Icon icon,
    void Function()? onTap,
    Widget? trailing,
  }) {
    return Card(
      color: AppColor.surfacePrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizing.radiusLarge),
        side: const BorderSide(color: AppColor.border, width: AppColor.borderWidth),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: icon,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  /// Read-only card listing the hosts currently connected to the device
  /// (from the last `G#CONS` request).
  Widget _buildConnectionsCard(List<DeviceConnection> connections) {
    return Card(
      color: AppColor.surfacePrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizing.radiusLarge),
        side: const BorderSide(color: AppColor.border, width: AppColor.borderWidth),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices_other),
                const SizedBox(width: 16),
                Text("Connected Hosts (${connections.length})", style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            if (connections.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("No hosts connected.", style: AppTextStyles.caption),
              ),
            for (final c in connections)
              Padding(
                padding: const EdgeInsets.only(top: AppSizing.paddingSmall),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name.isNotEmpty ? c.name : c.mac, style: AppTextStyles.bodyLarge),
                          if (c.name.isNotEmpty) Text(c.mac, style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                    if (c.bonded)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingSmall, vertical: 2),
                        decoration: AppContainer.statusBadge(AppColor.success),
                        child: Text('Bonded', style: AppTextStyles.bodySmall.copyWith(color: AppColor.success)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// App + connected-device firmware version indicator.
  Widget _buildVersionIndicator(TapDancerDevice? device) {
    final firmware = (device?.info['SOFT_VER'] as String?) ?? '';
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        );
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (firmware.isNotEmpty) Text("Firmware Version $firmware", style: style),
          Text("App Version ${PackageInformation.getAppVersionString()}", style: style),
        ],
      ),
    );
  }
}
