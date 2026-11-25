import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapdancer/providers/ble_provider.dart';

/// Flutter asset keys for the bundled DFU package and its version manifest,
/// kept in sync with ../firmware/release by scripts/sync_firmware.ps1.
const firmwareDfuAsset = 'assets/firmware/firmware_tapdancer.zip';
const _versionAsset = 'assets/firmware/version.json';

/// Bundled firmware version string (e.g. "1.4.2.182"), or null if the manifest
/// is missing or malformed. Loaded once and cached by Riverpod.
final bundledFirmwareVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final raw = await rootBundle.loadString(_versionAsset);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final v = json['version'] as String?;
    return (v != null && v.isNotEmpty) ? v : null;
  } catch (_) {
    return null;
  }
});

/// Segment-wise numeric compare of dotted versions like "1.4.2.182".
/// Returns <0 if [a] < [b], 0 if equal, >0 if [a] > [b]. Missing or
/// non-numeric segments count as 0, so "1.4.2" == "1.4.2.0".
int compareFirmwareVersions(String a, String b) {
  final pa = a.split('.');
  final pb = b.split('.');
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? int.tryParse(pa[i].trim()) ?? 0 : 0;
    final y = i < pb.length ? int.tryParse(pb[i].trim()) ?? 0 : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// The semantic part ("major.minor.patch") of a version, dropping the trailing
/// build count, e.g. "1.4.3.186" -> "1.4.3".
String _semanticVersion(String v) => v.split('.').take(3).join('.');

/// True only when [bundled] is a newer *major.minor.patch* than [installed].
/// The trailing build-count segment is ignored, so e.g. 1.4.3.5 -> 1.4.3.40 is
/// not flagged but 1.4.2.x -> 1.4.3.x is. Returns false if either version is
/// unknown (so we never nag without solid information).
bool firmwareUpdateAvailable({required String? installed, required String? bundled}) {
  if (installed == null || installed.isEmpty) return false;
  if (bundled == null || bundled.isEmpty) return false;
  return compareFirmwareVersions(_semanticVersion(bundled), _semanticVersion(installed)) > 0;
}

/// Whether a firmware update is available for the currently selected device.
/// Drives both the Settings tile and the nav-bar badge.
final firmwareUpdateAvailableProvider = Provider<bool>((ref) {
  final bundled = ref.watch(bundledFirmwareVersionProvider).asData?.value;
  final installed = ref.watch(bleProvider).selectedDevice?.info['SOFT_VER'] as String?;
  return firmwareUpdateAvailable(installed: installed, bundled: bundled);
});
