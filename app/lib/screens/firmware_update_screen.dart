import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:nordic_dfu/nordic_dfu.dart';
import 'package:tapdancer/models/tapdancer_device.dart';
import 'package:tapdancer/providers/ble_provider.dart';
import 'package:tapdancer/utils/app_theme.dart';
import 'package:tapdancer/utils/firmware_info.dart';
import 'package:tapdancer/utils/logger.dart';
import 'package:tapdancer/widgets/app_bar.dart';
import 'package:tapdancer/widgets/app_container.dart';
import 'package:tapdancer/widgets/gradient_scaffold.dart';

enum _DfuStage { idle, preparing, uploading, success, error }

/// Over-the-air firmware update screen. Flashes the bundled DFU package to the
/// given device using the Nordic buttonless secure DFU service (Android/iOS).
class FirmwareUpdateScreen extends ConsumerStatefulWidget {
  const FirmwareUpdateScreen({super.key, required this.deviceId});

  /// Id (MAC on Android) of the device to update.
  final String deviceId;

  @override
  ConsumerState<FirmwareUpdateScreen> createState() => _FirmwareUpdateScreenState();
}

class _FirmwareUpdateScreenState extends ConsumerState<FirmwareUpdateScreen> {
  final Logger _logger = Log.instance;

  _DfuStage _stage = _DfuStage.idle;
  int _percent = 0;
  String? _error;

  /// nordic_dfu ships native implementations for these platforms only.
  bool get _supported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  bool get _busy => _stage == _DfuStage.preparing || _stage == _DfuStage.uploading;

  Future<void> _startUpdate() async {
    setState(() {
      _stage = _DfuStage.preparing;
      _percent = 0;
      _error = null;
    });

    try {
      // A device already sitting in the bootloader (advertising as AdaDFU) is
      // not connected through us, so there's no GATT link to free and no
      // buttonless jump to trigger — the DFU library can flash it directly.
      // For a normal, connected device we first free the GATT connection so the
      // library can take over and trigger the buttonless jump into the
      // bootloader. Either way, suppress our own scan-driven reconnect so it
      // doesn't fight the update.
      final device = ref.read(bleProvider).deviceById(widget.deviceId);
      if (device != null && device.connected) {
        await ref.read(bleProvider.notifier).disconnectDevice(widget.deviceId, stopReconnect: true);
      }

      // Flutter assets aren't real files; copy the bundled package out to a
      // temp file so nordic_dfu can read it by path on every platform.
      final data = await rootBundle.load(firmwareDfuAsset);
      final tmp = File('${Directory.systemTemp.path}/tapdancer_firmware.zip');
      await tmp.writeAsBytes(data.buffer.asUint8List(), flush: true);

      if (!mounted) return;
      setState(() => _stage = _DfuStage.uploading);

      await NordicDfu().startDfu(
        widget.deviceId,
        tmp.path,
        dfuEventHandler: DfuEventHandler(
          onProgressChanged: (address, percent, speed, avgSpeed, currentPart, partsTotal) {
            if (mounted) setState(() => _percent = percent);
          },
          onError: (address, error, errorType, message) {
            _logger.e('DFU error $error/$errorType: $message');
          },
        ),
      );

      if (!mounted) return;
      setState(() => _stage = _DfuStage.success);
    } catch (e, st) {
      _logger.e('Firmware update failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _stage = _DfuStage.error;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(bleProvider).deviceById(widget.deviceId);
    final isDfu = device?.isDfuMode ?? false;

    return PopScope(
      // Block accidental back-navigation while flashing — interrupting DFU can
      // brick the device.
      canPop: !_busy,
      child: GradientScaffold(
        appBar: AppBarWidget(title: "Firmware Update"),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSizing.paddingXLarge),
            child: _supported ? _buildBody(device, isDfu) : _buildUnsupported(),
          ),
        ),
      ),
    );
  }

  Widget _buildUnsupported() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.system_update_alt, size: 64, color: AppColor.textTertiary),
          const SizedBox(height: AppSizing.paddingMedium),
          Text('Not available on this platform', style: AppTextStyles.headerMedium, textAlign: TextAlign.center),
          const SizedBox(height: AppSizing.paddingSmall),
          Text(
            'Firmware updates can only be installed from the Android or iOS app.',
            style: AppTextStyles.bodyLarge.copyWith(color: AppColor.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(TapDancerDevice? device, bool isDfu) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoCard(device, isDfu),
        const SizedBox(height: AppSizing.paddingLarge),
        Expanded(child: _buildStatus(isDfu)),
        _buildActions(),
      ],
    );
  }

  Widget _buildInfoCard(TapDancerDevice? device, bool isDfu) {
    final installed = (device?.info['SOFT_VER'] as String?);
    final bundled = ref.watch(bundledFirmwareVersionProvider).asData?.value;
    // In bootloader/recovery mode we can't read the installed version (the
    // device exposes no UART service), so an update is always "available".
    final updateAvailable = isDfu || firmwareUpdateAvailable(installed: installed, bundled: bundled);
    final upToDate = !isDfu && installed != null && bundled != null && !updateAvailable;

    return Container(
      padding: const EdgeInsets.all(AppSizing.paddingLarge),
      decoration: AppContainer.surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.system_update, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isDfu ? 'Device in update mode' : (device?.displayName ?? widget.deviceId),
                  style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizing.paddingSmall),
          if (!isDfu) ...[
            Text('Installed version: ${installed ?? '—'}', style: AppTextStyles.caption),
            const SizedBox(height: 2),
          ],
          Text('Bundled version: ${bundled ?? '—'}', style: AppTextStyles.caption),
          if (isDfu) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.new_releases, size: 14, color: AppColor.warning),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('In bootloader — reinstall firmware to recover.',
                      style: AppTextStyles.caption.copyWith(color: AppColor.warning, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ] else if (updateAvailable) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.new_releases, size: 14, color: AppColor.warning),
                const SizedBox(width: 4),
                Text('Firmware update available.',
                    style: AppTextStyles.caption.copyWith(color: AppColor.warning, fontWeight: FontWeight.w600)),
              ],
            ),
          ] else if (upToDate) ...[
            const SizedBox(height: 2),
            Text('This device is already up to date.',
                style: AppTextStyles.caption.copyWith(color: AppColor.success)),
          ],
        ],
      ),
    );
  }

  Widget _buildStatus(bool isDfu) {
    switch (_stage) {
      case _DfuStage.idle:
        return _centered(
          icon: Icons.info_outline,
          color: AppColor.textSecondary,
          title: isDfu ? 'Device is in update mode' : 'Keep the device close and powered',
          message: isDfu
              ? 'This device is in the bootloader and needs its firmware '
                  'reinstalled. Keep it close and powered, then install the '
                  'firmware below. Do not turn off the device or close the app '
                  'while it is running.'
              : 'The update takes about a minute. Do not turn off the device '
                  'or close the app while it is running.',
        );
      case _DfuStage.preparing:
        return _progress('Preparing…', null);
      case _DfuStage.uploading:
        // There's a multi-second gap after start while the device reboots into
        // the bootloader before progress callbacks begin — show an
        // indeterminate bar with a clearer label until the first percent.
        if (_percent <= 0) {
          return _progress('Starting update… this can take a few seconds', null);
        }
        return _progress('Installing… $_percent%', _percent / 100.0);
      case _DfuStage.success:
        return _centered(
          icon: Icons.check_circle,
          color: AppColor.success,
          title: 'Update complete',
          message: 'The new firmware was installed. The device now powers off — '
              'turn it back on manually using the hardware switch to use it again.',
        );
      case _DfuStage.error:
        return _centered(
          icon: Icons.error_outline,
          color: AppColor.error,
          title: 'Update failed',
          message: _error ?? 'Something went wrong during the update.',
        );
    }
  }

  Widget _progress(String label, double? value) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 10,
                backgroundColor: AppColor.surfaceSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSizing.paddingMedium),
          Text(label, style: AppTextStyles.bodyLarge),
        ],
      ),
    );
  }

  Widget _centered({required IconData icon, required Color color, required String title, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: color),
          const SizedBox(height: AppSizing.paddingMedium),
          Text(title, style: AppTextStyles.headerMedium, textAlign: TextAlign.center),
          const SizedBox(height: AppSizing.paddingSmall),
          Text(
            message,
            style: AppTextStyles.bodyLarge.copyWith(color: AppColor.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    if (_stage == _DfuStage.success) {
      return ElevatedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Done'),
      );
    }

    // While an update is running the button is disabled so it can't be tapped
    // again mid-flash.
    if (_busy) {
      return const ElevatedButton(
        onPressed: null,
        child: Text('Updating…'),
      );
    }

    return ElevatedButton.icon(
      onPressed: _startUpdate,
      icon: const Icon(Icons.download, size: 20),
      label: Text(_stage == _DfuStage.error ? 'Retry update' : 'Install update'),
    );
  }
}
