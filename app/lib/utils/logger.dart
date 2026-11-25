/// To use the logger in other files, just import this file and get the
/// singleton instance of the logger.
///
/// Example:
///
/// ```dart
/// import 'package:tapdancer/utils/logger.dart';
/// Logger _logger = Logger.instance;
/// ```
/// Colors:
/// https://i.sstatic.net/KTSQa.png
///
library;

import 'dart:convert';
import 'package:logger/logger.dart';

class Log {
  static final Logger _logger = Logger(
    level: Level.debug,
    printer: CustomSimplePrinter(colors: true, printTime: true),
  );
  static Logger get instance => _logger;
}

class CustomSimplePrinter extends LogPrinter {
  static final levelPrefixes = {
    Level.trace: '[T]',
    Level.debug: '[D]',
    Level.info: '[I]',
    Level.warning: '[W]',
    Level.error: '[E]',
    Level.fatal: '[FATAL]',
  };

  static final levelColors = {
    Level.trace: AnsiColor.fg(AnsiColor.grey(0.5)),
    Level.debug: AnsiColor.fg(12),
    Level.info: AnsiColor.fg(15),
    Level.warning: AnsiColor.fg(11),
    Level.error: AnsiColor.fg(9),
    Level.fatal: const AnsiColor.fg(199),
  };

  final bool printTime;
  final bool colors;
  final bool printWholeModule;

  CustomSimplePrinter({this.printTime = false, this.colors = true, this.printWholeModule = false});

  @override
  List<String> log(LogEvent event) {
    var messageStr = _stringifyMessage(event.message);
    var errorStr = event.error != null ? '  ERROR: ${event.error}' : '';
    var timeStr = printTime ? "[${_formatTime(event.time)}] " : '';
    return ['$timeStr${_labelFor(event.level)} [${_currentModule()}] $messageStr$errorStr'];
  }

  String _labelFor(Level level) {
    var prefix = levelPrefixes[level]!;
    var color = levelColors[level]!;

    return colors ? color(prefix) : prefix;
  }

  String _formatTime(DateTime now) {
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}";
  }

  String _stringifyMessage(dynamic message) {
    final finalMessage = message is Function ? message() : message;
    if (finalMessage is Map || finalMessage is Iterable) {
      var encoder = const JsonEncoder.withIndent(null);
      return encoder.convert(finalMessage);
    } else {
      return finalMessage.toString();
    }
  }

  String _currentModule() {
    final trace = StackTrace.current;
    List<String> lines = trace.toString().split('\n');
    if (lines.length >= 5) {
      String module = lines[4].split("/").last.split(")").first.padRight(28, ' ');

      if (!printWholeModule) {
        module = module.split(".").first.padRight(15, ' ');
      }
      return module;
    } else {
      return "";
    }
  }
}
