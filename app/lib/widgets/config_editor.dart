import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapdancer/models/device_settings.dart';
import 'package:tapdancer/models/tapdancer_device.dart';
import 'package:tapdancer/providers/ble_provider.dart';
import 'package:tapdancer/utils/app_theme.dart';
import 'package:tapdancer/utils/ble_command.dart';
import 'package:tapdancer/utils/ble_hid.dart';
import 'package:tapdancer/widgets/app_container.dart';

/// Normal (keyboard) vs consumer (media) key.
enum KeyType { normal, consumer }

const _clickLabels = ['Single Click', 'Double Click', 'Triple Click', 'Long Press'];
const _buttonLabels = ['Button 1', 'Button 2', 'Button 3'];

/// Default consumer usage used when switching a binding to "Consumer" mode.
const _defaultConsumerCode = 0x00CD; // Play/Pause

/// Full-screen overlay editor for a single [UserConfig].
///
/// Edits the passed config object in place and pushes every change to the device
/// immediately (unsaved — committed to flash on Save, discarded on Cancel). All
/// transient UI state (selected button, expanded tile) lives here so it survives
/// parent rebuilds.
class ConfigEditor extends ConsumerStatefulWidget {
  final UserConfig config;
  final int configIndex;
  final bool isActive;
  final VoidCallback onClose;

  const ConfigEditor({
    super.key,
    required this.config,
    required this.configIndex,
    required this.isActive,
    required this.onClose,
  });

  @override
  ConsumerState<ConfigEditor> createState() => _ConfigEditorState();
}

class _ConfigEditorState extends ConsumerState<ConfigEditor> {
  int _button = 0;
  int _expandedClick = 0; // which click tile is open (accordion)

  UserConfig get _config => widget.config;
  String get _deviceId => ref.read(bleProvider).selectedDeviceId;

  void _send(Uint8List cmd) => ref.read(bleProvider.notifier).sendCommand(_deviceId, cmd, true);

  HIDKeyboardReport _report(int click) => _config.buttonConfigs[_button].keycodes[click];

  /// In direct mode the button reacts instantly on press, so only the single
  /// click binding is used. Signalled by a double-click timing of 0.
  bool get _directMode => _config.buttonConfigs[_button].timingDoubleClickMs == 0;

  void _setDirectMode(bool direct) {
    final cur = _config.buttonConfigs[_button];
    final dc = direct ? 0 : defaultDoubleClickMs;
    final lc = cur.timingLongClickMs == 0 ? defaultLongClickMs : cur.timingLongClickMs;

    _config.buttonConfigs[_button] = ButtonConfig(
      keycodes: cur.keycodes,
      timingDoubleClickMs: dc,
      timingLongClickMs: lc,
    );
    _config.inUse = true;
    _send(BLECommand.setButtonClickTiming(widget.configIndex, ButtonType.values[_button], dc, lc, false));

    setState(() => _expandedClick = 0); // single click is always valid
  }

  /// Replaces a click binding and pushes it to the device. Pads keycodes to the
  /// fixed 6-slot HID report the firmware expects.
  void _setReport(int click, {int? modifier, List<int>? keys}) {
    final cur = _config.buttonConfigs[_button].keycodes[click];
    final newMod = modifier ?? cur.modifier;
    final newKeys = keys ?? cur.keycodes;

    _config.buttonConfigs[_button].keycodes[click] = HIDKeyboardReport(modifier: newMod, keycodes: newKeys);
    _config.inUse = true;

    final padded = [...newKeys, 0, 0, 0, 0, 0, 0].sublist(0, 6);
    _send(BLECommand.setKeycodes(
      widget.configIndex,
      ButtonType.values[_button],
      ClickType.values[click],
      HIDKeyboardReport(modifier: newMod, keycodes: padded),
      false,
    ));
    setState(() {});
  }

  void _setMode(int click, KeyType mode) {
    final isConsumer = isKeyboardReportConsumerKey(_report(click).keycodes);
    if (mode == KeyType.consumer && !isConsumer) {
      _setReport(click, modifier: 0, keys: _consumerKeys(_defaultConsumerCode));
    } else if (mode == KeyType.normal && isConsumer) {
      _setReport(click, modifier: 0, keys: [0]);
    }
  }

  /// Encodes a consumer usage code into the 6-slot report (hi, lo, .., 0xFF).
  List<int> _consumerKeys(int code) => [(code >> 8) & 0xFF, code & 0xFF, 0, 0, 0, 0xFF];

  /// One-line summary of a binding for the collapsed tile.
  String _summary(HIDKeyboardReport r) => hidReportLabel(r);

  @override
  Widget build(BuildContext context) {
    final lastKeyEvent = ref.watch(bleProvider.select((s) => s.selectedDevice?.lastKeyEvent));

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizing.paddingMedium),
          child: Container(
            decoration: BoxDecoration(
              // Opaque surface: surfacePrimary is translucent and lets the
              // scrim and page behind bleed through, making text unreadable.
              color: AppColor.surfaceSecondary,
              borderRadius: BorderRadius.circular(AppSizing.radiusLarge),
              border: Border.all(
                color: AppColor.border,
                width: AppColor.borderWidth,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildTopBar(),
                const Divider(height: 1),
                _buildHeader(),
                const Divider(height: 1),
                _buildButtonSelector(),
                _buildDirectModeToggle(),
                _buildTimingControls(),
                _buildLastInput(lastKeyEvent),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSizing.paddingMedium,
                      0,
                      AppSizing.paddingMedium,
                      AppSizing.paddingMedium,
                    ),
                    children: [
                      // Direct mode uses only the single click binding.
                      for (int c = 0; c < (_directMode ? 1 : _clickLabels.length); c++) _buildClickTile(c),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /* ------------------------------- TOP BAR -------------------------------- */
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.only(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: () {
              // Discard unsaved changes by reloading from flash.
              _send(BLECommand.getConfigurations(true));
              widget.onClose();
            },
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(foregroundColor: AppColor.textSecondary),
          ),
          TextButton.icon(
            onPressed: _deleteConfig,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: AppColor.error),
          ),
          TextButton.icon(
            onPressed: () {
              _send(BLECommand.setSaveSettings());
              widget.onClose();
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Save'),
            style: TextButton.styleFrom(foregroundColor: AppColor.success),
          ),
        ],
      ),
    );
  }

  /* -------------------------------- HEADER -------------------------------- */
  Widget _buildHeader() {
    final autoOff = _config.timeAutoOffS == 0 ? 'Always on' : '${_config.timeAutoOffS ~/ 60} min${_config.timeAutoOffS % 60 > 0 ? ' ${_config.timeAutoOffS % 60} s' : ''}';

    return Padding(
      padding: const EdgeInsets.only(
        top: AppSizing.paddingSmall,
        left: AppSizing.paddingMedium,
        right: AppSizing.paddingMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _config.configName,
                style: AppTextStyles.headerMedium,
                overflow: TextOverflow.ellipsis,
              ),
              IconButton(
                tooltip: 'Rename',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit, size: 18),
                onPressed: _editName,
              ),
              if (widget.isActive) ...[
                Expanded(child: Container()),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingSmall, vertical: 2),
                  decoration: AppContainer.statusBadge(AppColor.success),
                  child: Text('Active', style: AppTextStyles.bodySmall.copyWith(color: AppColor.success)),
                ),
              ],
            ],
          ),
          // Auto-off as a tappable chip.
          InkWell(
            onTap: _editAutoOff,
            borderRadius: BorderRadius.circular(AppSizing.radiusMedium),
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 6, bottom: AppSizing.paddingSmall),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: AppColor.textSecondary),
                  const SizedBox(width: 6),
                  Text('Auto-off: $autoOff', style: AppTextStyles.bodyLarge.copyWith(color: AppColor.textSecondary)),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 14, color: AppColor.textTertiary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* --------------------------- BUTTON SELECTOR ---------------------------- */
  Widget _buildButtonSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSizing.paddingSmall, 0, 0),
      child: SegmentedButton<int>(
        segments: [
          for (int b = 0; b < _buttonLabels.length; b++) ButtonSegment(value: b, label: Text(_buttonLabels[b])),
        ],
        selected: {_button},
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity(horizontal: -2, vertical: -2)),
        onSelectionChanged: (s) => setState(() => _button = s.first),
      ),
    );
  }

  /* ------------------------------ LAST INPUT ------------------------------ */
  /// Subtle live readout of the most recent button event pushed by the device,
  /// resolved against the config being edited so the user can confirm which
  /// button/click was detected and what it currently fires.
  Widget _buildLastInput(LastKeyEvent? event) {
    if (event == null) return const SizedBox.shrink();

    const clickLabels = ['Single click', 'Double click', 'Triple click', 'Long press'];
    final detail = event.click != null ? clickLabels[event.click!.index] : (event.pressed == true ? 'Pressed' : 'Released');
    final color = event.click != null ? AppColor.clickType[event.click!.index] : AppColor.primary;

    // Press/release events fire the single-click binding on the firmware, so
    // resolve those to single click.
    final clickIndex = (event.click ?? ClickType.single).index;
    final resolved = hidReportLabel(_config.buttonConfigs[event.button.index].keycodes[clickIndex]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizing.paddingMedium, 0, AppSizing.paddingMedium, AppSizing.paddingSmall),
      child: Row(
        children: [
          Icon(Icons.radio_button_checked, size: AppSizing.iconSmall, color: color),
          const SizedBox(width: AppSizing.paddingSmall),
          Text('Last input: ', style: AppTextStyles.caption.copyWith(color: AppColor.textSecondary)),
          Expanded(
            child: Text(
              'Button ${event.button.index + 1} · $detail → $resolved',
              style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /* --------------------------- DIRECT MODE TOGGLE ------------------------- */
  Widget _buildDirectModeToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizing.paddingMedium, 0, AppSizing.paddingMedium, AppSizing.paddingSmall),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Direct mode', style: AppTextStyles.headerSmall),
                const SizedBox(height: 2),
                Text(
                  'Fires instantly on press — single click only.',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          Switch(
            value: _directMode,
            onChanged: _setDirectMode,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  /* --------------------------- TIMING CONTROLS ---------------------------- */
  Widget _buildTimingControls() {
    final cur = _config.buttonConfigs[_button];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizing.paddingMedium, 0, AppSizing.paddingMedium, AppSizing.paddingSmall),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          alignment: WrapAlignment.start,
          spacing: AppSizing.paddingMedium,
          runSpacing: 0,
          children: [
            // Double-click timing only applies when not in direct mode.
            if (!_directMode)
              _timingChip(
                icon: Icons.touch_app_outlined,
                label: 'Double-click: ${cur.timingDoubleClickMs} ms',
                onTap: () => _editTiming(
                  title: 'Double-click time',
                  currentMs: cur.timingDoubleClickMs,
                  onSet: (v) => _setTiming(doubleClickMs: v),
                ),
              ),
            _timingChip(
              icon: Icons.timer_outlined,
              label: 'Long-press: ${cur.timingLongClickMs} ms',
              onTap: () => _editTiming(
                title: 'Long-press time',
                currentMs: cur.timingLongClickMs,
                onSet: (v) => _setTiming(longClickMs: v),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timingChip({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizing.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColor.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.bodyLarge.copyWith(color: AppColor.textSecondary)),
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 14, color: AppColor.textTertiary),
          ],
        ),
      ),
    );
  }

  /// Updates the current button's click timings and pushes them to the device.
  void _setTiming({int? doubleClickMs, int? longClickMs}) {
    final cur = _config.buttonConfigs[_button];
    final dc = doubleClickMs ?? cur.timingDoubleClickMs;
    final lc = longClickMs ?? cur.timingLongClickMs;

    _config.buttonConfigs[_button] = ButtonConfig(
      keycodes: cur.keycodes,
      timingDoubleClickMs: dc,
      timingLongClickMs: lc,
    );
    _config.inUse = true;
    _send(BLECommand.setButtonClickTiming(widget.configIndex, ButtonType.values[_button], dc, lc, false));
    setState(() {});
  }

  /* ------------------------------ CLICK TILE ------------------------------ */
  Widget _buildClickTile(int click) {
    final report = _report(click);
    final expanded = _expandedClick == click;
    final isConsumer = isKeyboardReportConsumerKey(report.keycodes);

    // The firmware powers the device off when a long press has no key bound.
    final powersOff = click == ClickType.long.index && !isConsumer && report.keycodes.every((k) => k == 0);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSizing.paddingXSmall),
      decoration: AppContainer.surface(isActive: expanded),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header row — tap to expand/collapse.
          InkWell(
            onTap: () => setState(() => _expandedClick = expanded ? -1 : click),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingMedium, vertical: AppSizing.paddingSmall),
              child: Row(
                children: [
                  // Colored click-type badge, matching the config overview.
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.only(right: AppSizing.paddingSmall),
                    decoration: BoxDecoration(
                      color: AppColor.clickType[click].withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSizing.radiusSmall),
                    ),
                    child: Text(
                      _clickLabels[click][0],
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColor.clickType[click], fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_clickLabels[click], style: AppTextStyles.headerSmall),
                        const SizedBox(height: 2),
                        if (powersOff)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.power_settings_new, size: 12, color: AppColor.warning),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'No key — powers off the device',
                                  style: AppTextStyles.caption.copyWith(color: AppColor.warning),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(_summary(report), style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, color: AppColor.textSecondary),
                ],
              ),
            ),
          ),
          // Expanded editor.
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSizing.paddingMedium, 0, AppSizing.paddingMedium, AppSizing.paddingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<KeyType>(
                    segments: const [
                      ButtonSegment(value: KeyType.normal, label: Text('Keyboard')),
                      ButtonSegment(value: KeyType.consumer, label: Text('Media')),
                    ],
                    selected: {isConsumer ? KeyType.consumer : KeyType.normal},
                    showSelectedIcon: false,
                    style: ButtonStyle(visualDensity: VisualDensity.compact),
                    onSelectionChanged: (s) => _setMode(click, s.first),
                  ),
                  const SizedBox(height: AppSizing.paddingSmall),
                  if (isConsumer) _buildConsumerEditor(click, report) else _buildNormalEditor(click, report),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /* ----------------------------- NORMAL EDITOR ---------------------------- */
  Widget _buildNormalEditor(int click, HIDKeyboardReport report) {
    final keys = report.keycodes.isEmpty ? <int>[0] : List<int>.from(report.keycodes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Modifiers', style: AppTextStyles.caption),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: -2,
          children: hidKeyboardModifiers.entries.map((e) {
            final selected = (report.modifier & e.key) != 0;
            return FilterChip(
              label: Text(e.value),
              selected: selected,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (on) => _setReport(click, modifier: on ? report.modifier | e.key : report.modifier & ~e.key),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSizing.paddingSmall),
        Text('Keys', style: AppTextStyles.caption),
        const SizedBox(height: 4),
        ...List.generate(keys.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(),
            child: Row(
              children: [
                Expanded(
                  child: _keycodeDropdown(
                    value: keys[i],
                    map: hidKeycodes,
                    onChanged: (v) {
                      final next = List<int>.from(keys)..[i] = v;
                      _setReport(click, keys: next);
                    },
                  ),
                ),
                if (keys.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    color: AppColor.textSecondary,
                    onPressed: () => _setReport(click, keys: List<int>.from(keys)..removeAt(i)),
                  ),
              ],
            ),
          );
        }),
        if (keys.length < 6)
          TextButton.icon(
            onPressed: () => _setReport(click, keys: [...keys, 0]),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add key'),
            style: TextButton.styleFrom(foregroundColor: AppColor.primary, padding: EdgeInsets.zero),
          ),
      ],
    );
  }

  /* ---------------------------- CONSUMER EDITOR --------------------------- */
  Widget _buildConsumerEditor(int click, HIDKeyboardReport report) {
    final code = (report.keycodes[0] << 8) | report.keycodes[1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Media key', style: AppTextStyles.caption),
        const SizedBox(height: 4),
        _keycodeDropdown(
          value: consumerReportCodes.containsKey(code) ? code : consumerReportCodes.keys.first,
          map: consumerReportCodes,
          onChanged: (v) => _setReport(click, modifier: 0, keys: _consumerKeys(v)),
        ),
      ],
    );
  }

  Widget _keycodeDropdown({required int value, required Map<int, String> map, required ValueChanged<int> onChanged}) {
    final label = map[value] ?? '0x${value.toRadixString(16)}';
    return InkWell(
      onTap: () => _showKeycodePicker(map: map, selected: value, onChanged: onChanged),
      borderRadius: BorderRadius.circular(AppSizing.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingMedium, vertical: 10),
        decoration: BoxDecoration(
          color: AppColor.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppSizing.radiusMedium),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTextStyles.bodyLarge, overflow: TextOverflow.ellipsis)),
            Icon(Icons.arrow_drop_down, color: AppColor.textSecondary),
          ],
        ),
      ),
    );
  }

  /// Searchable key picker. Filters [map]'s labels by the typed query.
  Future<void> _showKeycodePicker({
    required Map<int, String> map,
    required int selected,
    required ValueChanged<int> onChanged,
  }) async {
    final entries = map.entries.toList();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty ? entries : entries.where((e) => e.value.toLowerCase().contains(q)).toList();
            return Dialog(
              backgroundColor: AppColor.surfaceSecondary,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480, maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSizing.paddingMedium),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search key…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setLocal(() => query = v),
                      ),
                    ),
                    Flexible(
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(AppSizing.paddingLarge),
                              child: Text('No matches', style: AppTextStyles.caption),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final e = filtered[i];
                                final isSel = e.key == selected;
                                return ListTile(
                                  dense: true,
                                  title: Text(e.value, style: AppTextStyles.bodyLarge),
                                  trailing: isSel ? Icon(Icons.check, size: 18, color: AppColor.primary) : null,
                                  onTap: () => Navigator.pop(ctx, e.key),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (result != null) onChanged(result);
  }

  /* ------------------------------- DIALOGS -------------------------------- */
  /// Prompts for a timing value in milliseconds.
  Future<void> _editTiming({
    required String title,
    required int currentMs,
    required ValueChanged<int> onSet,
  }) async {
    final controller = TextEditingController(text: currentMs.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int? parse() {
          final v = int.tryParse(controller.text.trim());
          return (v == null || v < 0) ? null : v;
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Milliseconds',
              suffixText: 'ms',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              final v = parse();
              if (v != null) Navigator.pop(ctx, v);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final v = parse();
                if (v != null) Navigator.pop(ctx, v);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (result != null) onSet(result);
  }

  Future<void> _deleteConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete configuration'),
        content: Text('Delete "${_config.configName}"? This resets the slot to defaults and removes it from the list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColor.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final notifier = ref.read(bleProvider.notifier);

    // The device always reports its active config, so deleting the active one
    // would leave it stuck in the list. Switch to another in-use config first.
    if (widget.isActive) {
      final settings = ref.read(bleProvider).selectedDevice?.settings;
      final next = settings == null ? null : _firstOtherInUseConfig(settings, widget.configIndex);
      if (next != null) {
        await notifier.sendCommand(_deviceId, BLECommand.setConfigIndex(next, false), true);
      }
    }

    // Reset the slot on the device (committed immediately), then refresh local
    // state so the config object matches the firmware's defaults.
    await notifier.sendCommand(_deviceId, BLECommand.deleteConfig(widget.configIndex, true), true);
    await notifier.sendCommand(_deviceId, BLECommand.getConfigurations(false), true);

    _config.inUse = false; // immediate feedback; refresh will overwrite shortly
    widget.onClose();
  }

  /// First in-use config other than [exclude], or null if none remain.
  int? _firstOtherInUseConfig(DeviceSettings settings, int exclude) {
    for (int i = 0; i < settings.configs.length; i++) {
      if (i != exclude && settings.configs[i].inUse) return i;
    }
    return null;
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _config.configName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename configuration'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxConfigNameLen,
          inputFormatters: [LengthLimitingTextInputFormatter(maxConfigNameLen)],
          decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (name == null) return;
    setState(() {
      _config.configName = name;
      _config.inUse = true;
    });
    _send(BLECommand.setConfigName(widget.configIndex, name, false));
  }

  Future<void> _editAutoOff() async {
    Duration picked = Duration(seconds: _config.timeAutoOffS);
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auto-off time'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 180,
                child: CupertinoTheme(
                  data: const CupertinoThemeData(brightness: Brightness.dark),
                  child: CupertinoTimerPicker(
                    mode: CupertinoTimerPickerMode.hms,
                    backgroundColor: Colors.transparent,
                    initialTimerDuration: picked,
                    onTimerDurationChanged: (d) => picked = d,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('Set to zero to keep the device always on.', style: AppTextStyles.caption),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, picked.inSeconds),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      _config.timeAutoOffS = result;
      _config.inUse = true;
    });
    _send(BLECommand.setAutoOffTime(widget.configIndex, result, false));
  }
}
