import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapdancer/models/device_settings.dart';
import 'package:tapdancer/models/tapdancer_device.dart';
import 'package:tapdancer/utils/app_theme.dart';
import 'package:tapdancer/utils/backup_manager.dart';
import 'package:tapdancer/utils/ble_command.dart';
import 'package:tapdancer/utils/ble_hid.dart';
import 'package:tapdancer/utils/config_io.dart';
import 'package:tapdancer/utils/logger.dart';
import 'package:tapdancer/utils/utils.dart';
import 'package:tapdancer/widgets/app_bar.dart';
import 'package:tapdancer/widgets/app_container.dart';
import 'package:tapdancer/widgets/config_editor.dart';
import 'package:tapdancer/widgets/gradient_scaffold.dart';
import 'package:tapdancer/providers/ble_provider.dart';
import 'package:tapdancer/widgets/device_selector.dart';
import 'package:tapdancer/widgets/misellaneous.dart';

/// Factory name for an unconfigured config slot. A config counts as "used" (and
/// is shown in the grid) only once it's been given a different name.
const _defaultConfigName = 'Default';

/// Whether [name] marks a configured slot (named something other than the
/// factory default / empty).
bool _isNamedConfig(String name) {
  final trimmed = name.trim();
  return trimmed.isNotEmpty && trimmed != _defaultConfigName;
}

/// Single-letter labels per click type (Single/Double/Triple/Long), used with
/// AppColor.clickType so each click type is easy to spot at a glance.
const _clickAbbrev = ['S', 'D', 'T', 'L'];

class ConfigScreen extends ConsumerStatefulWidget {
  const ConfigScreen({super.key});

  @override
  ConsumerState<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends ConsumerState<ConfigScreen> {
  final Logger _logger = Log.instance;

  // Keep track of the currently active config.
  int _configIdx = 0;
  int _zoomedConfigIdx = -1;

  DeviceSettings? deviceSettings;
  bool settingsChanged = false;
  int deviceSettingsTimestamp = 0;

  /// The device id the local [deviceSettings] copy belongs to. Used to detect
  /// when the user switches devices so we reload that device's config instead
  /// of keeping the previous one (timestamps are per-device, so a timestamp
  /// comparison alone can't tell devices apart).
  String _loadedDeviceId = '';

  void _cancelSubscriptions() {}

  void _startSubscriptions() {
    _cancelSubscriptions();
  }

  @override
  void initState() {
    _logger.d("ConfigScreen: init");
    super.initState();
    _startSubscriptions();
  }

  @override
  void dispose() {
    _logger.d("ConfigScreen: dispose");
    super.dispose();
    _cancelSubscriptions();
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleProvider);
    final connectedDevices = bleState.connectedDevices;
    final setupOngoing = bleState.setupOngoing;

    // Wait for the setup to finish before allowing settings changes.
    if (setupOngoing) {
      settingsChanged = false;
    }

    // Update the deviceSettings object if it has changed externally.
    final selectedId = bleState.selectedDeviceId;
    final selectedSettings = bleState.selectedDevice?.settings;

    // User switched devices — always load the newly selected device's config
    // (its timestamp is unrelated to the previous device's).
    if (selectedId != _loadedDeviceId) {
      _logger.d("Selected device changed to '$selectedId', loading its config.");
      _loadedDeviceId = selectedId;
      deviceSettings = selectedSettings;
      deviceSettingsTimestamp = selectedSettings?.timestamp ?? 0;
      _configIdx = selectedSettings?.configIdx ?? 0;
      _zoomedConfigIdx = -1;
      settingsChanged = false;
    } else if (selectedSettings != null && selectedSettings.timestamp > deviceSettingsTimestamp) {
      _logger.d("Device settings updated externally, refreshing local copy.");
      deviceSettings = selectedSettings;
      deviceSettingsTimestamp = selectedSettings.timestamp;
      _configIdx = selectedSettings.configIdx;
    } else if (selectedSettings == null && deviceSettings != null) {
      _logger.d("Device config cleared, dropping local copy.");
      deviceSettings = null;
      deviceSettingsTimestamp = 0;
      _zoomedConfigIdx = -1;
      settingsChanged = false;
    }

    // Any device connected?
    if (connectedDevices.isEmpty && !setupOngoing) {
      return buildNoDeviceConnectedScreen();
    }

    // While the device is connecting and its configuration is still being
    // fetched, show only a loading indicator rather than the (empty) config UI.
    if (deviceSettings == null) {
      return GradientScaffold(
        appBar: AppBarWidget(title: "Button Configurations"),
        body: SafeArea(child: _buildLoading(setupOngoing)),
      );
    }

    return Stack(
      children: [
        GradientScaffold(
          appBar: AppBarWidget(
            title: "Button Configurations",
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Actions',
                onSelected: (value) {
                  if (value == 'import') {
                    _importConfig(deviceSettings!);
                  } else if (value == 'exportAll') {
                    _exportAll(deviceSettings!);
                  } else if (value == 'restoreBackup') {
                    _restoreFromBackup(deviceSettings!);
                  } else {
                    handleDeviceAction(ref, selectedId, value);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                      leading: Icon(Icons.file_download_outlined),
                      title: Text('Import configuration'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'exportAll',
                    child: ListTile(
                      leading: Icon(Icons.file_upload_outlined),
                      title: Text('Export all configurations'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'restoreBackup',
                    child: ListTile(
                      leading: Icon(Icons.history),
                      title: Text('Restore from backup'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuDivider(),
                  ...deviceActionMenuItems(),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                _buildLastInput(bleState.selectedDevice?.lastKeyEvent),
                const SizedBox(height: AppSizing.paddingSmall),
                Expanded(child: _buildConfigGrid(deviceSettings!)),
              ],
            ),
          ),
        ),
        // User tapped a config's edit button — show the full editor overlay.
        if (_zoomedConfigIdx != -1 && deviceSettings != null)
          ConfigEditor(
            key: ValueKey(_zoomedConfigIdx),
            config: deviceSettings!.configs[_zoomedConfigIdx],
            configIndex: _zoomedConfigIdx,
            isActive: _configIdx == _zoomedConfigIdx,
            onClose: () => setState(() => _zoomedConfigIdx = -1),
          ),
      ],
    );
  }

  /// Full-screen loading state shown while the device connects and its
  /// configuration is fetched, before [deviceSettings] arrives.
  Widget _buildLoading(bool setupOngoing) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingXLarge),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            setupOngoing ? Icons.bluetooth : Icons.settings,
            size: 48,
            color: AppColor.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            setupOngoing ? 'Connecting device...' : 'Fetching configuration...',
            style: AppTextStyles.headerMedium,
          ),
          const SizedBox(height: 24),
          LinearProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColor.primary),
            backgroundColor: AppColor.surfaceSecondary.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  /// Dropdown with connected devices
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingXLarge),
      child: DeviceSelector(
        showLabel: false,
        showSignal: true,
        onRefreshConfig: () {
          setState(() {
            // Allow the config to be updated again.
            settingsChanged = false;
          });
        },
      ),
    );
  }

  /// A subtle live readout of the most recent button event pushed by the
  /// device, so the user can confirm which button/click was detected.
  Widget _buildLastInput(LastKeyEvent? event) {
    if (event == null) return const SizedBox.shrink();

    const clickLabels = ['Single click', 'Double click', 'Triple click', 'Long press'];
    final detail = event.click != null ? clickLabels[event.click!.index] : (event.pressed == true ? 'Pressed' : 'Released');
    final color = event.click != null ? AppColor.clickType[event.click!.index] : AppColor.primary;

    // Resolve the event to the keycode bound for it in the active config. Click
    // events use their own click type; press/release events fire the
    // single-click keycode on the firmware, so resolve those to single click.
    String? resolved;
    if (deviceSettings != null) {
      final clickIndex = (event.click ?? ClickType.single).index;
      resolved = hidReportLabel(
        deviceSettings!.configs[_configIdx].buttonConfigs[event.button.index].keycodes[clickIndex],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizing.paddingXLarge,
        vertical: AppSizing.paddingXSmall,
      ),
      child: Row(
        children: [
          Icon(Icons.radio_button_checked, size: AppSizing.iconSmall, color: color),
          const SizedBox(width: AppSizing.paddingSmall),
          Text(
            'Last input: ',
            style: AppTextStyles.caption.copyWith(color: AppColor.textSecondary),
          ),
          Expanded(
            child: Text(
              'Button ${event.button.index + 1} · $detail'
              '${resolved != null ? ' → $resolved' : ''}',
              style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Grid of the configs that are in use (named) plus the currently active one,
  /// followed by an "+ Add configuration" tile when free slots remain.
  Widget _buildConfigGrid(DeviceSettings settings) {
    final configs = settings.configs;
    final visibleIndices = [
      for (int i = 0; i < configs.length; i++)
        if (configs[i].inUse || i == _configIdx) i,
    ];
    final freeIndex = _firstFreeConfigIndex(configs);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingXLarge),
      children: [
        for (final i in visibleIndices)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizing.paddingMedium),
            child: _buildConfigCard(
              name: configs[i].configName,
              bindings: _configSummary(configs[i]),
              isActive: _configIdx == i,
              index: i,
            ),
          ),
        if (freeIndex != null) _buildAddConfigCard(freeIndex),
      ],
    );
  }

  /// Per-button summary of every click type that is set, as (clickIndex, label)
  /// entries. Unset click types are skipped, and in direct mode (double-click
  /// timing 0) only the single click is shown.
  List<List<MapEntry<int, String>>> _configSummary(UserConfig config) {
    return config.buttonConfigs.map((b) {
      final directMode = b.timingDoubleClickMs == 0;
      final entries = <MapEntry<int, String>>[];
      for (int c = 0; c < b.keycodes.length; c++) {
        if (directMode && c != ClickType.single.index) continue;
        final label = hidReportLabel(b.keycodes[c]);
        if (label == 'None') continue;
        entries.add(MapEntry(c, label));
      }
      return entries;
    }).toList();
  }

  /// Lowest non-active slot that is not yet in use, or null when every slot is
  /// in use.
  int? _firstFreeConfigIndex(List<UserConfig> configs) {
    for (int i = 0; i < configs.length; i++) {
      if (i != _configIdx && !configs[i].inUse) return i;
    }
    return null;
  }

  /// "Add configuration" tile — prompts for a name, then opens the editor on the
  /// next free slot.
  Widget _buildAddConfigCard(int freeIndex) {
    return GestureDetector(
      onTap: () => _addConfiguration(freeIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizing.paddingMedium,
          vertical: AppSizing.paddingSmall,
        ),
        decoration: BoxDecoration(
          color: AppColor.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppSizing.radiusLarge),
          border: Border.all(color: AppColor.primary.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: AppSizing.iconLarge, color: AppColor.primary),
            const SizedBox(width: AppSizing.paddingSmall),
            Flexible(
              child: Text(
                'Add configuration',
                style: AppTextStyles.bodyLarge.copyWith(color: AppColor.primary, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Names a free slot and opens its editor so the user can assign keycodes.
  Future<void> _addConfiguration(int freeIndex) async {
    final newName = await _promptForConfigName(context);
    if (newName == null || !mounted) return;

    setState(() {
      deviceSettings!.configs[freeIndex].configName = newName;
      deviceSettings!.configs[freeIndex].inUse = true;
      _zoomedConfigIdx = freeIndex;
    });

    // Sending the name marks the slot in use on the firmware too (see in_use).
    ref.read(bleProvider.notifier).sendCommand(
          ref.read(bleProvider).selectedDeviceId,
          BLECommand.setConfigName(freeIndex, newName, false),
          true,
        );
  }

  /* --------------------------- EXPORT / IMPORT --------------------------- */

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// Runs [task] while showing a blocking progress dialog (writing configs over
  /// BLE takes a few seconds). The dialog is dismissed when the task finishes.
  Future<T> _runWithProgress<T>(String message, Future<T> Function() task) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: SizedBox(
            width: 240,
            child: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      return await task();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Strips characters that aren't valid in file names across platforms.
  String _safeFileName(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.isEmpty ? 'config' : cleaned;
  }

  Future<void> _saveExport({required String suggestedName, required String json}) async {
    try {
      final path = await exportToFile(suggestedName: suggestedName, json: json);
      if (!mounted || path == null) return;
      _showSnack('Configuration exported.');
    } catch (e) {
      _logger.e('Export failed: $e');
      if (!mounted) return;
      _showSnack('Export failed.');
    }
  }

  /// Exports a single config slot to a file.
  Future<void> _exportSingle(int index) async {
    final settings = deviceSettings;
    if (settings == null) return;
    final config = settings.configs[index];
    final baseName = _isNamedConfig(config.configName) ? config.configName : 'config-${index + 1}';
    final json = encodeSingle(
      config,
      appVersion: PackageInformation.getAppVersionString(),
      settingsVersion: settings.version,
    );
    await _saveExport(suggestedName: _safeFileName(baseName), json: json);
  }

  /// Exports the in-use config slots to a single file (skips empty slots).
  Future<void> _exportAll(DeviceSettings settings) async {
    final inUseConfigs = settings.configs.where((c) => c.inUse).toList();
    if (inUseConfigs.isEmpty) {
      _showSnack('No configurations to export.');
      return;
    }
    final json = encodeAll(
      inUseConfigs,
      appVersion: PackageInformation.getAppVersionString(),
      settingsVersion: settings.version,
    );
    await _saveExport(suggestedName: 'tapdancer-all', json: json);
  }

  /// Picks a file, decodes it, and writes the imported config(s) to the device.
  Future<void> _importConfig(DeviceSettings settings) async {
    String? raw;
    try {
      raw = await pickAndReadConfigFile();
    } on ConfigImportException catch (e) {
      if (mounted) _showSnack(e.message);
      return;
    } catch (e) {
      _logger.e('Import read failed: $e');
      if (mounted) _showSnack('Could not read the file.');
      return;
    }
    if (raw == null || !mounted) return;

    final ImportedConfig imported;
    try {
      imported = decode(raw);
    } on ConfigImportException catch (e) {
      if (mounted) _showSnack(e.message);
      return;
    }
    if (!mounted) return;

    await _applyImported(imported, settings);
  }

  /// Writes a decoded [imported] config set onto the device, after a soft
  /// version-mismatch warning. Shared by file import and backup restore.
  Future<void> _applyImported(ImportedConfig imported, DeviceSettings settings) async {
    // Soft warning when the file came from a device on a different settings
    // version — keycode semantics could differ. Let the user decide.
    if (imported.settingsVersion != null && imported.settingsVersion != settings.version) {
      final proceed = await _confirm(
        title: 'Different device version',
        message: 'This file was exported from settings version ${imported.settingsVersion}, '
            'but this device is on version ${settings.version}. Import anyway?',
        confirmLabel: 'Import',
      );
      if (proceed != true || !mounted) return;
    }

    final deviceId = ref.read(bleProvider).selectedDeviceId;
    final notifier = ref.read(bleProvider.notifier);

    if (imported.kind == ImportKind.single) {
      final slot = await _pickSlot(settings);
      if (slot == null || !mounted) return;
      final ok = await _runWithProgress(
        'Importing configuration…',
        () => notifier.applyUserConfig(deviceId, slot, imported.configs.first),
      );
      if (!mounted) return;
      setState(() => settingsChanged = false);
      _showSnack(ok ? 'Imported into slot ${slot + 1}.' : 'Import failed.');
    } else {
      final proceed = await _confirm(
        title: 'Overwrite all configurations?',
        message: 'This will replace all ${imported.configs.length} configurations on the device.',
        confirmLabel: 'Overwrite',
      );
      if (proceed != true || !mounted) return;
      final map = <int, UserConfig>{
        for (int i = 0; i < imported.configs.length && i < configNum; i++) i: imported.configs[i],
      };
      final ok = await _runWithProgress(
        'Importing ${map.length} configurations…',
        () => notifier.applyUserConfigs(deviceId, map),
      );
      if (!mounted) return;
      setState(() => settingsChanged = false);
      _showSnack(ok ? 'All configurations imported.' : 'Import failed.');
    }
  }

  /* ------------------------------- BACKUPS -------------------------------- */

  /// Lists the automatic backups for the selected device, lets the user pick
  /// one, and writes it back to the device (reusing the import apply path).
  Future<void> _restoreFromBackup(DeviceSettings settings) async {
    final device = ref.read(bleProvider).selectedDevice;
    if (device == null) return;

    List<BackupEntry> backups;
    try {
      backups = await listBackups(device.backupKey);
    } catch (e) {
      _logger.e('Listing backups failed: $e');
      if (mounted) _showSnack('Could not read backups.');
      return;
    }
    if (!mounted) return;
    if (backups.isEmpty) {
      _showSnack('No backups yet for this device.');
      return;
    }

    final chosen = await _pickBackup(backups);
    if (chosen == null || !mounted) return;

    final String raw;
    try {
      raw = await chosen.file.readAsString();
    } catch (e) {
      _logger.e('Reading backup failed: $e');
      if (mounted) _showSnack('Could not read the backup.');
      return;
    }

    final ImportedConfig imported;
    try {
      imported = decode(raw);
    } on ConfigImportException catch (e) {
      if (mounted) _showSnack(e.message);
      return;
    }
    if (!mounted) return;

    await _applyImported(imported, settings);
  }

  /// Backup chooser — one row per stored backup, newest first.
  Future<BackupEntry?> _pickBackup(List<BackupEntry> backups) {
    return showDialog<BackupEntry>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from backup'),
        content: SizedBox(
          width: 340,
          height: 360,
          child: ListView.separated(
            itemCount: backups.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final b = backups[i];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.history),
                title: Text(_formatBackupTime(b.time)),
                subtitle: Text(
                  '${b.configCount} configuration${b.configCount == 1 ? '' : 's'}'
                  '${i == 0 ? ' · latest' : ''}',
                  style: AppTextStyles.caption,
                ),
                onTap: () => Navigator.pop(ctx, b),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  /// Local date+time, e.g. `23.06.26 14:05`.
  String _formatBackupTime(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${two(l.year % 100)} ${two(l.hour)}:${two(l.minute)}';
  }

  /// Lets the user choose which slot an imported config should overwrite.
  Future<int?> _pickSlot(DeviceSettings settings) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose a slot'),
        content: SizedBox(
          width: 320,
          height: 360,
          child: ListView.builder(
            itemCount: configNum,
            itemBuilder: (_, i) {
              final c = settings.configs[i];
              final named = _isNamedConfig(c.configName);
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: named ? AppColor.primary : AppColor.surfaceTertiary,
                  child: Text(
                    '${i + 1}',
                    style: AppTextStyles.caption.copyWith(
                      color: named ? Colors.white : AppColor.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(named ? c.configName : 'Empty slot'),
                subtitle: named ? Text('Will be overwritten', style: AppTextStyles.caption) : null,
                onTap: () => Navigator.pop(ctx, i),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  /// Generic yes/no confirmation dialog. Returns true if confirmed.
  Future<bool?> _confirm({required String title, required String message, required String confirmLabel}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
        ],
      ),
    );
  }

  /// Prompts for a config name, rejecting empty and the reserved "Default".
  /// Returns null if cancelled.
  Future<String?> _promptForConfigName(BuildContext context, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Config Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              maxLength: maxConfigNameLen,
              inputFormatters: [
                LengthLimitingTextInputFormatter(maxConfigNameLen),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (_isNamedConfig(trimmed) && trimmed.length <= maxConfigNameLen) {
                Navigator.pop(context, trimmed);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Renders one button's bindings with a colored letter per click type, e.g.
  /// a blue "S" then the key, a green "D" then the key, etc.
  Widget _buildBindingText(List<MapEntry<int, String>> entries) {
    if (entries.isEmpty) {
      return Text('–', style: AppTextStyles.caption);
    }
    final spans = <InlineSpan>[];
    for (var i = 0; i < entries.length; i++) {
      final click = entries[i].key;
      if (i > 0) {
        spans.add(TextSpan(text: '  ·  ', style: AppTextStyles.caption.copyWith(color: AppColor.textTertiary)));
      }
      spans.add(TextSpan(
        text: _clickAbbrev[click],
        style: AppTextStyles.caption.copyWith(color: AppColor.clickType[click], fontWeight: FontWeight.w700),
      ));
      spans.add(TextSpan(text: ' ${entries[i].value}', style: AppTextStyles.caption));
    }
    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildConfigCard({
    required String name,
    List<List<MapEntry<int, String>>> bindings = const [],
    bool isActive = false,
    int index = 0,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (index != _configIdx) {
            settingsChanged = true;
            _configIdx = index;
          }
        });

        // Set the config on the device. Immediately save to flash.
        ref.read(bleProvider.notifier).sendCommand(
              ref.read(bleProvider).selectedDeviceId,
              BLECommand.setConfigIndex(index, true),
              true,
            );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizing.paddingMedium,
          vertical: AppSizing.paddingSmall,
        ),
        decoration: AppContainer.surface(isActive: isActive),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: index badge + name + edit.
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isActive ? AppColor.primary : AppColor.surfaceTertiary,
                    borderRadius: BorderRadius.circular(AppSizing.radiusMedium),
                  ),
                  child: Text(
                    "${index + 1}",
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isActive ? Colors.white : AppColor.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSizing.paddingSmall),
                Expanded(
                  child: Text(
                    name,
                    style: AppTextStyles.headerSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _exportSingle(index),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSizing.paddingXSmall),
                    child: Icon(
                      Icons.file_upload_outlined,
                      size: AppSizing.iconLarge,
                      color: AppColor.textTertiary,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _zoomedConfigIdx = index),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSizing.paddingXSmall),
                    child: Icon(
                      Icons.edit_outlined,
                      size: AppSizing.iconLarge,
                      color: isActive ? AppColor.primary : AppColor.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizing.paddingXSmall),
            // One line per button listing its set click types.
            ...List.generate(
              bindings.length,
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        "B${b + 1}",
                        style: AppTextStyles.caption.copyWith(
                          color: AppColor.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildBindingText(bindings[b]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
