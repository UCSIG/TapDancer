import 'package:package_info_plus/package_info_plus.dart';

class ConsoleColor {
  static const String reset = '\x1B[0m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String magenta = '\x1B[35m';
  static const String cyan = '\x1B[36m';
  static const String white = '\x1B[37m';

  static String colorize(String text, String colorCode) {
    return '$colorCode$text$reset';
  }

  static String colorizeBool(bool input) {
    if (input) {
      return ConsoleColor.colorize("yes", ConsoleColor.green);
    } else {
      return ConsoleColor.colorize("no", ConsoleColor.red);
    }
  }
}

class PackageInformation {
  static PackageInfo? _info;
  static Future<PackageInfo> init() async => _info = await PackageInfo.fromPlatform();

  static String getAppVersionString() {
    return _info?.version ?? '';
  }
}
