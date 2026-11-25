import 'package:material_ui/material_ui.dart';
import 'package:tapdancer/utils/app_theme.dart';

/// Four ascending bars visualising BLE signal strength from an RSSI value in
/// dBm. Shared by the devices list and the config screen so signal strength is
/// rendered identically everywhere.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.rssi});

  /// Signal strength in dBm (e.g. -65). Lower (more negative) is weaker.
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final int bars;
    if (rssi < -90) {
      bars = 0;
    } else if (rssi < -80) {
      bars = 1;
    } else if (rssi < -70) {
      bars = 2;
    } else if (rssi < -60) {
      bars = 3;
    } else {
      bars = 4;
    }

    // Colour-code the active bars by strength: strong → green, medium → amber,
    // weak → red. Keyed off the same thresholds as the bar count.
    final Color color;
    if (bars >= 3) {
      color = AppColor.success;
    } else if (bars == 2) {
      color = AppColor.warning;
    } else {
      color = AppColor.error;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        final isActive = index < bars;
        return Container(
          width: 3,
          height: 6 + (index * 4.0), // grows upward
          margin: const EdgeInsets.only(right: 2, bottom: 4),
          decoration: BoxDecoration(
            color: isActive ? color : AppColor.surfaceSecondary,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

Widget buildNoDeviceConnectedScreen() {
  return Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_searching, size: 64, color: AppColor.textTertiary),
          const SizedBox(height: AppSizing.paddingMedium),
          Text('No device connected!', style: AppTextStyles.headerMedium),
          const SizedBox(height: AppSizing.paddingSmall),
          Text('Please connect your device to begin.', style: AppTextStyles.bodyLarge, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
