/// Automatic, per-device backups of a device's configurations.
///
/// Each backup is a normal `.tdcfg` "all" envelope (the same format the manual
/// "Export all" produces), written under
/// `<appSupport>/config_backups/<deviceName>/<epochMs>.tdcfg`. Folders are keyed
/// by the device's advertised name (e.g. "TapDancer 6523") rather than its BLE
/// id, because the id is a per-connection UUID on iOS/macOS — see
/// [TapDancerDevice.backupKey]. The newest [maxBackupsPerDevice] are kept; older
/// ones are pruned. Restore reuses the regular import path (decode →
/// applyUserConfigs), so backups and exported files are interchangeable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:tapdancer/models/device_settings.dart';
import 'package:tapdancer/utils/config_io.dart';

/// Maximum number of automatic backups retained per device. Older backups are
/// pruned on each new write.
const int maxBackupsPerDevice = 20;

/// Subdirectory (under the app support dir) that holds all device backups.
const String _backupRootDir = 'config_backups';

/// A single stored backup, surfaced to the restore UI.
class BackupEntry {
  final File file;

  /// When the backup was taken (derived from the file name).
  final DateTime time;

  /// Number of configurations stored in the backup.
  final int configCount;

  const BackupEntry({required this.file, required this.time, required this.configCount});
}

/// Filesystem-safe folder name for a device key (names can contain spaces and
/// other characters that are awkward or invalid in paths).
String _safeKey(String deviceKey) => deviceKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

/// The (created-on-demand) backup directory for [deviceKey] (the device's
/// stable [TapDancerDevice.backupKey]).
Future<Directory> _deviceBackupDir(String deviceKey) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/$_backupRootDir/${_safeKey(deviceKey)}');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Epoch-ms encoded in a backup file's name, or 0 if unparseable.
int _msFromFile(File f) {
  final stem = f.uri.pathSegments.last.replaceAll('.$configFileExtension', '');
  return int.tryParse(stem) ?? 0;
}

/// All backup files in [dir], newest first.
Future<List<File>> _sortedBackupFiles(Directory dir) async {
  if (!await dir.exists()) return [];
  final files = await dir
      .list()
      .where((e) => e is File && e.path.endsWith('.$configFileExtension'))
      .cast<File>()
      .toList();
  files.sort((a, b) => _msFromFile(b).compareTo(_msFromFile(a)));
  return files;
}

/// Canonical string for comparing two config sets, ignoring envelope metadata
/// (timestamp/appVersion) so unchanged configs don't produce redundant backups.
String _payloadKey(List<UserConfig> configs) => jsonEncode(configs.map((c) => c.toJson()).toList());

/// Writes a backup of [settings]' in-use configurations for [deviceKey] (the
/// device's stable [TapDancerDevice.backupKey]).
///
/// A backup is always written on connect, so the newest entry's timestamp
/// reflects the last time the device connected. When the configs are
/// byte-for-byte identical to the most recent backup, the old identical entry
/// is removed first — its timestamp is effectively refreshed rather than kept
/// as a duplicate. Returns the written file, or null only when there are no
/// configurations to back up. Prunes old backups down to [maxBackupsPerDevice].
Future<File?> saveBackup(
  String deviceKey,
  DeviceSettings settings, {
  required String appVersion,
}) async {
  final inUse = settings.configs.where((c) => c.inUse).toList();
  if (inUse.isEmpty) return null;

  final dir = await _deviceBackupDir(deviceKey);
  final existing = await _sortedBackupFiles(dir);

  // If unchanged since the newest backup, drop the old identical entry and
  // rewrite below with a fresh timestamp, so we never keep two identical
  // backups under different timestamps.
  if (existing.isNotEmpty) {
    try {
      final prev = decode(await existing.first.readAsString());
      if (_payloadKey(prev.configs) == _payloadKey(inUse)) {
        await existing.first.delete();
      }
    } catch (_) {
      // Corrupt newest backup — leave it and write a fresh one alongside.
    }
  }

  final json = encodeAll(inUse, appVersion: appVersion, settingsVersion: settings.version);
  final file = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$configFileExtension');
  await file.writeAsString(json, flush: true);

  await _prune(dir);
  return file;
}

/// Lists the backups for [deviceKey], newest first. Corrupt files are skipped.
Future<List<BackupEntry>> listBackups(String deviceKey) async {
  final dir = await _deviceBackupDir(deviceKey);
  final files = await _sortedBackupFiles(dir);

  final entries = <BackupEntry>[];
  for (final f in files) {
    final int count;
    try {
      count = decode(await f.readAsString()).configs.length;
    } catch (_) {
      continue; // skip unreadable / corrupt backups
    }
    entries.add(BackupEntry(
      file: f,
      time: DateTime.fromMillisecondsSinceEpoch(_msFromFile(f)),
      configCount: count,
    ));
  }
  return entries;
}

/// Deletes a single backup file. Missing files are ignored.
Future<void> deleteBackup(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {/* best-effort */}
}

/// Removes backups beyond the newest [maxBackupsPerDevice].
Future<void> _prune(Directory dir) async {
  final files = await _sortedBackupFiles(dir);
  for (final f in files.skip(maxBackupsPerDevice)) {
    try {
      await f.delete();
    } catch (_) {/* best-effort */}
  }
}
