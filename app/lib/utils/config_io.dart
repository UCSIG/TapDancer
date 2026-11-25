import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:tapdancer/models/device_settings.dart';

/// On-disk format identifier and version for exported configuration files. Bump
/// [_formatVersion] only on a breaking change to the envelope shape.
const String _formatId = 'tapdancer.config';
const int _formatVersion = 1;

/// File extension used for exported configurations (content is JSON).
const String configFileExtension = 'tdcfg';

/// What an exported file holds: a single preset or the whole device set.
enum ImportKind { single, all }

/// Thrown when an imported file is not a valid TapDancer configuration. The
/// [message] is safe to surface directly to the user.
class ConfigImportException implements Exception {
  final String message;
  const ConfigImportException(this.message);

  @override
  String toString() => message;
}

/// Result of decoding an imported file. [configs] always holds at least one
/// entry; for [ImportKind.single] it holds exactly one.
class ImportedConfig {
  final ImportKind kind;
  final List<UserConfig> configs;

  /// The `settingsVersion` recorded in the file (the firmware settings version
  /// of the device it was exported from), or null if absent. Used for the soft
  /// version-mismatch warning on import.
  final int? settingsVersion;

  const ImportedConfig({
    required this.kind,
    required this.configs,
    this.settingsVersion,
  });
}

/// Serializes one configuration into the export envelope (pretty JSON).
String encodeSingle(UserConfig config, {required String appVersion, required int settingsVersion}) {
  return _encode(
    kind: ImportKind.single,
    appVersion: appVersion,
    settingsVersion: settingsVersion,
    payload: {'config': config.toJson()},
  );
}

/// Serializes the full set of configurations into the export envelope.
String encodeAll(List<UserConfig> configs, {required String appVersion, required int settingsVersion}) {
  return _encode(
    kind: ImportKind.all,
    appVersion: appVersion,
    settingsVersion: settingsVersion,
    payload: {'configs': configs.map((c) => c.toJson()).toList()},
  );
}

String _encode({
  required ImportKind kind,
  required String appVersion,
  required int settingsVersion,
  required Map<String, dynamic> payload,
}) {
  final envelope = <String, dynamic>{
    'format': _formatId,
    'formatVersion': _formatVersion,
    'appVersion': appVersion,
    'settingsVersion': settingsVersion,
    'kind': kind == ImportKind.single ? 'single' : 'all',
    ...payload,
  };
  return const JsonEncoder.withIndent('  ').convert(envelope);
}

/// Parses and validates an exported file's contents. Throws
/// [ConfigImportException] (with a user-readable message) on anything that
/// isn't a well-formed TapDancer configuration file.
ImportedConfig decode(String raw) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    throw const ConfigImportException("This file isn't a valid configuration file.");
  }

  if (decoded is! Map) {
    throw const ConfigImportException("This file isn't a valid configuration file.");
  }
  final json = Map<String, dynamic>.from(decoded);

  if (json['format'] != _formatId) {
    throw const ConfigImportException('Unrecognized file — this is not a TapDancer configuration.');
  }
  final fileFormatVersion = (json['formatVersion'] as num?)?.toInt() ?? 0;
  if (fileFormatVersion > _formatVersion) {
    throw const ConfigImportException('This file was made with a newer app version. Please update the app.');
  }

  final settingsVersion = (json['settingsVersion'] as num?)?.toInt();
  final kindStr = json['kind'] as String?;

  try {
    if (kindStr == 'single') {
      final cfg = json['config'];
      if (cfg is! Map) throw const ConfigImportException('The configuration in this file is missing or corrupt.');
      return ImportedConfig(
        kind: ImportKind.single,
        configs: [UserConfig.fromJson(Map<String, dynamic>.from(cfg))],
        settingsVersion: settingsVersion,
      );
    } else if (kindStr == 'all') {
      final list = json['configs'];
      if (list is! List || list.isEmpty) {
        throw const ConfigImportException('This file contains no configurations.');
      }
      return ImportedConfig(
        kind: ImportKind.all,
        configs: list.map((e) => UserConfig.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        settingsVersion: settingsVersion,
      );
    } else {
      throw const ConfigImportException('This configuration file is missing its type marker.');
    }
  } on ConfigImportException {
    rethrow;
  } catch (_) {
    throw const ConfigImportException('The configuration data in this file is corrupt.');
  }
}

/// Opens a save dialog and writes [json] to the chosen location. Returns the
/// saved location (a file path where available), or null if the user
/// cancelled. file_picker writes the bytes itself on every platform.
Future<String?> exportToFile({required String suggestedName, required String json}) async {
  final fileName = suggestedName.toLowerCase().endsWith('.$configFileExtension') ? suggestedName : '$suggestedName.$configFileExtension';
  final bytes = Uint8List.fromList(utf8.encode(json));

  final uri = await FilePicker.saveFile(
    dialogTitle: 'Export configuration',
    fileName: fileName,
    mimeType: 'application/json',
    bytes: bytes,
  );
  if (uri == null) return null;
  return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
}

/// Opens a file picker and returns the selected file's text contents, or null
/// if the user cancelled. Throws [ConfigImportException] if the file can't be
/// read.
Future<String?> pickAndReadConfigFile() async {
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Import configuration',
    type: FileType.custom,
    allowedExtensions: [configFileExtension],
  );
  if (files.isEmpty) return null;

  try {
    return utf8.decode(await files.first.readAsBytes());
  } catch (_) {
    throw const ConfigImportException("Couldn't read the selected file.");
  }
}
