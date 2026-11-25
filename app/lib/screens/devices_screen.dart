import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tapdancer/models/tapdancer_device.dart';
import 'package:tapdancer/providers/ble_provider.dart';
import 'package:tapdancer/screens/firmware_update_screen.dart';
import 'package:tapdancer/utils/app_theme.dart';
import 'package:tapdancer/utils/logger.dart';
import 'package:tapdancer/widgets/app_container.dart';
import 'package:tapdancer/widgets/gradient_scaffold.dart';
import 'package:tapdancer/widgets/app_bar.dart';
import 'package:tapdancer/widgets/misellaneous.dart';

/* -------------------------------- SETTINGS -------------------------------- */
const deviceScanInactiveTimeMs = 3000;

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  final Logger _logger = Log.instance;

  Timer? _redrawTimer;

  void _cancelSubscriptions() {
    _redrawTimer?.cancel();
  }

  void _startSubscriptions() {
    _cancelSubscriptions();
    _redrawTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void initState() {
    _logger.d("DevicesScreen: init");
    super.initState();
    _startSubscriptions();
  }

  @override
  void dispose() {
    _logger.d("DevicesScreen: dispose");
    super.dispose();
    _cancelSubscriptions();
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleProvider);

    final now = DateTime.now().millisecondsSinceEpoch;
    bool isActive(TapDancerDevice d) => d.scantimeMs != 0 && (now - d.scantimeMs) <= deviceScanInactiveTimeMs;

    // Group devices into intuitive buckets:
    //  - Connected: currently connected (or mid connect/disconnect).
    //  - Saved:     bookmarked devices not currently connected.
    //  - Available: nearby devices seen in a recent scan that aren't saved.
    // Stale, unsaved devices (not seen recently) are dropped entirely.
    final connected = <TapDancerDevice>[];
    final saved = <TapDancerDevice>[];
    final available = <TapDancerDevice>[];
    for (final d in bleState.devices) {
      if (d.connected || d.setupOngoing || d.disconnecting) {
        connected.add(d);
      } else if (d.saved) {
        saved.add(d);
      } else if (isActive(d)) {
        available.add(d);
      }
    }

    final sections = <Widget>[];
    void addSection(String title, List<TapDancerDevice> devices) {
      if (devices.isEmpty) return;
      sections.add(_buildSectionHeader(title, devices.length));
      for (final d in devices) {
        sections.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSizing.paddingSmall),
          child: _deviceCard(d, active: isActive(d)),
        ));
      }
    }

    addSection('Connected', connected);
    addSection('Saved', saved);
    addSection('Available', available);

    final bleUnavailable = bleState.bleOff || bleState.blePermissionDenied || bleState.bleUnsupported;

    return GradientScaffold(
      appBar: AppBarWidget(
        title: "Devices",
      ),
      body: bleUnavailable
          ? _buildBleUnavailable(bleState)
          : RefreshIndicator(
              onRefresh: () async {
                setState(() {}); // Redraw UI on pull-to-refresh
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: LayoutBuilder(
                builder: (context, constraints) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSizing.paddingMedium, 0, AppSizing.paddingMedium, AppSizing.paddingMedium),
                  children: sections.isEmpty ? [SizedBox(height: constraints.maxHeight, child: _buildEmptyState())] : sections,
                ),
              ),
            ),
    );
  }

  /// Shown when the Bluetooth adapter is off, permission was denied, or the
  /// platform has no BLE support — with an action to resolve it where possible.
  Widget _buildBleUnavailable(BLEState bleState) {
    final String title;
    final String message;
    Widget? action;

    if (bleState.bleUnsupported) {
      title = 'Bluetooth not supported';
      message = 'This device has no Bluetooth LE support, so TapDancers can\'t be connected.';
    } else if (bleState.blePermissionDenied) {
      title = 'Bluetooth permission needed';
      message = 'Allow Bluetooth access so the app can find and connect to your TapDancer.';
      action = FilledButton.icon(
        onPressed: openAppSettings,
        icon: const Icon(Icons.settings),
        label: const Text('Open settings'),
      );
    } else {
      title = 'Bluetooth is off';
      message = Platform.isAndroid ? 'Turn Bluetooth on to find and connect to your TapDancer.' : 'Turn Bluetooth on in your system settings to find and connect to your TapDancer.';
      if (Platform.isAndroid) {
        action = FilledButton.icon(
          onPressed: () => ref.read(bleProvider.notifier).enableBluetooth(),
          icon: const Icon(Icons.bluetooth),
          label: const Text('Turn on Bluetooth'),
        );
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizing.paddingXLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 64, color: AppColor.textTertiary),
            const SizedBox(height: AppSizing.paddingMedium),
            Text(title, style: AppTextStyles.headerMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSizing.paddingSmall),
            Text(message, style: AppTextStyles.bodyLarge.copyWith(color: AppColor.textSecondary), textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: AppSizing.paddingLarge),
              action,
            ],
          ],
        ),
      ),
    );
  }

  /// Uppercase group label with a count badge, e.g. "CONNECTED  1".
  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizing.paddingSmall, AppSizing.paddingSmall, AppSizing.paddingSmall, AppSizing.paddingSmall),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: AppTextStyles.caption.copyWith(color: AppColor.textSecondary, fontWeight: FontWeight.w700, letterSpacing: 1.0),
          ),
          const SizedBox(width: AppSizing.paddingSmall),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColor.surfaceSecondary,
              borderRadius: BorderRadius.circular(AppSizing.radiusSmall),
            ),
            child: Text('$count', style: AppTextStyles.caption.copyWith(color: AppColor.textSecondary)),
          ),
        ],
      ),
    );
  }

  /// Shown when no device is connected, saved or nearby.
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_searching, size: 64, color: AppColor.textTertiary),
          const SizedBox(height: AppSizing.paddingMedium),
          Text('Scanning for devices…', style: AppTextStyles.headerMedium),
          const SizedBox(height: AppSizing.paddingSmall),
          Text('Make sure your TapDancer is powered on.', style: AppTextStyles.bodyLarge, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _deviceCard(TapDancerDevice device, {required bool active}) {
    final isConnected = device.connected;
    final setupOngoing = device.setupOngoing;
    final disconnecting = device.disconnecting;
    final deviceId = device.id;

    // A device stuck in the bootloader: it can't be connected/configured, only
    // recovered with a firmware flash.
    final isDfu = device.isDfuMode;

    // A saved device we can't currently reach (not connected, not in range).
    final deviceInactive = !isConnected && !active;

    return Container(
      padding: const EdgeInsets.all(AppSizing.paddingLarge),
      decoration: AppContainer.surface(isActive: isConnected),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left side: device information
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isDfu ? 'Device in update mode' : device.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: deviceInactive ? AppTextStyles.headerMedium.copyWith(color: AppColor.textSecondary) : AppTextStyles.headerMedium,
                          ),
                        ),
                        SizedBox(width: 8),
                        SignalBars(rssi: device.rssi),
                      ],
                    ),

                    // A device in the bootloader can't be used until its
                    // firmware is (re)installed.
                    if (isDfu)
                      Row(
                        children: [
                          Icon(Icons.system_update, size: 14, color: AppColor.warning),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Firmware update required',
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyMedium.copyWith(color: AppColor.warning),
                            ),
                          ),
                        ],
                      ),

                    // Advertised name, shown below when a custom name overrides it.
                    if (!isDfu && device.customName != null && device.name.isNotEmpty)
                      Text(
                        device.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColor.textSecondary),
                      ),

                    // Device id + saved marker
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          deviceId.toUpperCase(),
                          style: AppTextStyles.caption,
                        ),
                        Text(
                          device.autoConnect ? "  (Auto-Connect)" : "",
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Right side: connect button (or an "out of range" hint when a
              // saved device can't be reached).
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDfu)
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FirmwareUpdateScreen(deviceId: deviceId),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColor.warning,
                        padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingLarge, vertical: AppSizing.paddingSmall),
                      ),
                      child: Text(
                        'Update',
                        style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: AppColor.warning),
                      ),
                    )
                  else if (!deviceInactive)
                    Builder(builder: (context) {
                      // Disconnect → red, Connect → green, transitional → white.
                      final Color color = (setupOngoing || disconnecting)
                          ? AppColor.textPrimary
                          : isConnected
                              ? AppColor.error
                              : AppColor.success;
                      return TextButton(
                        onPressed: (setupOngoing || disconnecting)
                            ? null
                            : () {
                                if (isConnected) {
                                  ref.read(bleProvider.notifier).disconnectDevice(deviceId);
                                } else {
                                  ref.read(bleProvider.notifier).connectDevice(deviceId);
                                }
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: color,
                          disabledForegroundColor: color,
                          padding: const EdgeInsets.symmetric(horizontal: AppSizing.paddingLarge, vertical: AppSizing.paddingSmall),
                        ),
                        child: Text(
                          disconnecting
                              ? 'Disconnecting...'
                              : setupOngoing
                                  ? 'Connecting...'
                                  : isConnected
                                      ? 'Disconnect'
                                      : 'Connect',
                          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: color),
                        ),
                      );
                    }),
                  if (deviceInactive)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSizing.paddingSmall),
                      child: Text(
                        "Out of range",
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColor.textSecondary),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TapDancerAlertDialog extends StatefulWidget {
  const TapDancerAlertDialog({
    super.key,
  });

  @override
  State<TapDancerAlertDialog> createState() => _TapDancerAlertDialogState();
}

class _TapDancerAlertDialogState extends State<TapDancerAlertDialog> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('TapDancer Setup'),
      content: const Text('Please wait until the TapDancer setup has finished!'),
      actions: <Widget>[
        ElevatedButton(
          onPressed: () => Navigator.pop(context, 'OK'),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
