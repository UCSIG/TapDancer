import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapdancer/providers/ble_provider.dart';
import 'package:tapdancer/utils/app_theme.dart';
import 'package:tapdancer/utils/ble_command.dart';
import 'package:tapdancer/widgets/misellaneous.dart';

/// How long the device should advertise (in seconds) when asked to become
/// discoverable. The firmware stops advertising shortly after the app connects,
/// so this gives a window to pair additional devices.
const int deviceAdvertisingTimeoutS = 60;

/// Popup-menu entries for the per-device actions (blink / make discoverable),
/// shared by the config and settings app-bar menus. Pair with
/// [handleDeviceAction] in the menu's `onSelected`.
List<PopupMenuEntry<String>> deviceActionMenuItems() => const [
      PopupMenuItem(
        value: 'blink',
        child: ListTile(
          leading: Icon(Icons.lightbulb),
          title: Text('Blink device'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: 'advertise',
        child: ListTile(
          leading: Icon(Icons.bluetooth_searching),
          title: Text('Make device discoverable'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ];

/// Runs the command for a [deviceActionMenuItems] selection. Returns true when
/// it handled [value], so callers can fall through to their own menu entries.
bool handleDeviceAction(WidgetRef ref, String deviceId, String value) {
  switch (value) {
    case 'blink':
      ref.read(bleProvider.notifier).sendCommand(deviceId, BLECommand.setBlinkDevice(), true);
      return true;
    case 'advertise':
      ref.read(bleProvider.notifier).sendCommand(deviceId, BLECommand.setStartAdvertising(deviceAdvertisingTimeoutS), true);
      return true;
  }
  return false;
}

class DeviceSelector extends ConsumerWidget {
  final bool showLabel;
  final bool showSignal;
  final void Function()? onRefreshConfig;

  const DeviceSelector({
    super.key,
    this.showLabel = true,
    this.showSignal = false,
    this.onRefreshConfig,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bleState = ref.watch(bleProvider);
    final connectedDevices = bleState.connectedDevices;

    if (connectedDevices.isEmpty) {
      return Row(
        children: const [
          Text('No device connected!', style: AppTextStyles.headerSmall),
        ],
      );
    }

    if (bleState.selectedDeviceId == "") {
      return const SizedBox.shrink();
    }

    // Guard the dropdown value: it must match one of the items or the
    // DropdownButton throws. The notifier keeps selectedDeviceId valid, but be
    // defensive against a transient mismatch during rebuilds.
    final selectedValue = connectedDevices.any((d) => d.id == bleState.selectedDeviceId) ? bleState.selectedDeviceId : connectedDevices.first.id;
    final device = bleState.selectedDevice;

    return Row(
      children: [
        if (showLabel) ...[
          Column(
            children: [
              Transform(
                transform: Matrix4.translationValues(0, 2, 0),
                child: Text(
                  'Select Device:',
                ),
              ),
              Text(
                '(${connectedDevices.length} connected)',
              ),
            ],
          ),
          const SizedBox(width: AppSizing.paddingMedium),
        ],
        DropdownButton<String>(
          isDense: true,
          value: selectedValue,
          items: connectedDevices
              .map((device) => DropdownMenuItem<String>(
                    value: device.id,
                    child: Text(
                      device.displayName,
                      style: AppTextStyles.bodyLarge,
                    ),
                  ))
              .toList(),
          onChanged: (String? selectedDeviceId) {
            if (selectedDeviceId == null) return;
            ref.read(bleProvider.notifier).setSelectedDeviceId(selectedDeviceId);
            ref.read(bleProvider.notifier).sendCommand(
                  selectedDeviceId,
                  BLECommand.setBlinkDevice(),
                  true,
                );
          },
        ),
        // Live signal strength of the selected device, next to the dropdown.
        if (showSignal && (device?.hasRssi ?? false)) ...[
          const SizedBox(width: AppSizing.paddingSmall),
          SignalBars(rssi: device!.rssi),
        ],
        // Battery level, on the same row as the selector.
        if (device?.batteryLevel != null) ...[
          const SizedBox(width: AppSizing.paddingMedium),
          _batteryChip(device!.batteryLevel!),
        ],

        // Push the actions to the right edge.
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh configuration',
          onPressed: () {
            ref.read(bleProvider.notifier).sendCommand(
                  bleState.selectedDeviceId,
                  BLECommand.getConfigurations(true),
                  true,
                );
            ref.read(bleProvider.notifier).sendCommand(
                  bleState.selectedDeviceId,
                  BLECommand.getConnections(),
                  true,
                );

            if (onRefreshConfig != null) {
              onRefreshConfig!();
            }
          },
        ),
      ],
    );
  }

  /// Compact battery readout (icon + percentage) shown inline in the header.
  Widget _batteryChip(int level) {
    final color = level <= 20 ? AppColor.error : AppColor.success;

    final IconData icon;
    if (level >= 90) {
      icon = Icons.battery_full;
    } else if (level >= 75) {
      icon = Icons.battery_6_bar;
    } else if (level >= 60) {
      icon = Icons.battery_5_bar;
    } else if (level >= 45) {
      icon = Icons.battery_4_bar;
    } else if (level >= 30) {
      icon = Icons.battery_3_bar;
    } else if (level >= 15) {
      icon = Icons.battery_2_bar;
    } else if (level >= 5) {
      icon = Icons.battery_1_bar;
    } else {
      icon = Icons.battery_alert;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppSizing.iconSmall, color: color),
        const SizedBox(width: 2),
        Text(
          '$level%',
          style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

}
