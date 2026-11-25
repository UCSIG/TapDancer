import 'package:tapdancer/models/device_settings.dart';

/* -------------------------------- KEYCODES -------------------------------- */
const Map<int, String> hidKeycodes = {
  0x00: 'None',
  0x04: 'A',
  0x05: 'B',
  0x06: 'C',
  0x07: 'D',
  0x08: 'E',
  0x09: 'F',
  0x0A: 'G',
  0x0B: 'H',
  0x0C: 'I',
  0x0D: 'J',
  0x0E: 'K',
  0x0F: 'L',
  0x10: 'M',
  0x11: 'N',
  0x12: 'O',
  0x13: 'P',
  0x14: 'Q',
  0x15: 'R',
  0x16: 'S',
  0x17: 'T',
  0x18: 'U',
  0x19: 'V',
  0x1A: 'W',
  0x1B: 'X',
  0x1C: 'Y',
  0x1D: 'Z',
  0x1E: '1',
  0x1F: '2',
  0x20: '3',
  0x21: '4',
  0x22: '5',
  0x23: '6',
  0x24: '7',
  0x25: '8',
  0x26: '9',
  0x27: '0',
  0x28: 'Enter',
  0x29: 'Escape',
  0x2A: 'Backspace',
  0x2B: 'Tab',
  0x2C: 'Space',
  0x2D: 'Minus',
  0x2E: 'Equal',
  0x2F: 'Bracket Left',
  0x30: 'Bracket Right',
  0x31: 'Backslash',
  0x32: 'Europe 1',
  0x33: 'Semicolon',
  0x34: 'Apostrophe',
  0x35: 'Grave',
  0x36: 'Comma',
  0x37: 'Period',
  0x38: 'Slash',
  0x39: 'Caps Lock',
  0x3A: 'F1',
  0x3B: 'F2',
  0x3C: 'F3',
  0x3D: 'F4',
  0x3E: 'F5',
  0x3F: 'F6',
  0x40: 'F7',
  0x41: 'F8',
  0x42: 'F9',
  0x43: 'F10',
  0x44: 'F11',
  0x45: 'F12',
  0x46: 'Print Screen',
  0x47: 'Scroll Lock',
  0x48: 'Pause',
  0x49: 'Insert',
  0x4A: 'Home',
  0x4B: 'Page Up',
  0x4C: 'Delete',
  0x4D: 'End',
  0x4E: 'Page Down',
  0x4F: 'Arrow Right',
  0x50: 'Arrow Left',
  0x51: 'Arrow Down',
  0x52: 'Arrow Up',
  0x53: 'Num Lock',
  0x54: 'Keypad Divide',
  0x55: 'Keypad Multiply',
  0x56: 'Keypad Subtract',
  0x57: 'Keypad Add',
  0x58: 'Keypad Enter',
  0x59: 'Keypad 1',
  0x5A: 'Keypad 2',
  0x5B: 'Keypad 3',
  0x5C: 'Keypad 4',
  0x5D: 'Keypad 5',
  0x5E: 'Keypad 6',
  0x5F: 'Keypad 7',
  0x60: 'Keypad 8',
  0x61: 'Keypad 9',
  0x62: 'Keypad 0',
  0x63: 'Keypad Decimal',
  0x64: 'Europe 2',
  0x65: 'Application',
  0x66: 'Power',
  0x67: 'Keypad Equal',
  0x68: 'F13',
  0x69: 'F14',
  0x6A: 'F15',
  0x6B: 'F16',
  0x6C: 'F17',
  0x6D: 'F18',
  0x6E: 'F19',
  0x6F: 'F20',
  0x70: 'F21',
  0x71: 'F22',
  0x72: 'F23',
  0x73: 'F24',
  0x74: 'Execute',
  0x75: 'Help',
  0x76: 'Menu',
  0x77: 'Select',
  0x78: 'Stop',
  0x79: 'Again',
  0x7A: 'Undo',
  0x7B: 'Cut',
  0x7C: 'Copy',
  0x7D: 'Paste',
  0x7E: 'Find',
  0x7F: 'Mute',
  0x80: 'Volume Up',
  0x81: 'Volume Down',
  0x82: 'Locking Caps Lock',
  0x83: 'Locking Num Lock',
  0x84: 'Locking Scroll Lock',
  0x85: 'Keypad Comma',
  0x86: 'Keypad Equal Sign',
  0x87: 'Kanji1',
  0x88: 'Kanji2',
  0x89: 'Kanji3',
  0x8A: 'Kanji4',
  0x8B: 'Kanji5',
  0x8C: 'Kanji6',
  0x8D: 'Kanji7',
  0x8E: 'Kanji8',
  0x8F: 'Kanji9',
  0x90: 'Lang1',
  0x91: 'Lang2',
  0x92: 'Lang3',
  0x93: 'Lang4',
  0x94: 'Lang5',
  0x95: 'Lang6',
  0x96: 'Lang7',
  0x97: 'Lang8',
  0x98: 'Lang9',
  0x99: 'Alternate Erase',
  0x9A: 'Sysreq Attention',
  0x9B: 'Cancel',
  0x9C: 'Clear',
  0x9D: 'Prior',
  0x9E: 'Return',
  0x9F: 'Separator',
  0xA0: 'Out',
  0xA1: 'Oper',
  0xA2: 'Clear Again',
  0xA3: 'Crsel Props',
  0xA4: 'Exsel',
  0xE0: 'Control Left',
  0xE1: 'Shift Left',
  0xE2: 'Alt Left',
  0xE3: 'Gui Left',
  0xE4: 'Control Right',
  0xE5: 'Shift Right',
  0xE6: 'Alt Right',
  0xE7: 'Gui Right',
};

bool isKeyboardReportConsumerKey(List<int> keycodes) {
  if (keycodes.length != 6) return false;
  return (keycodes[5] == 0xFF);
}

/* -------------------------------- MODIFIERS ------------------------------- */
/// HID keyboard modifier bitmasks
const Map<int, String> hidKeyboardModifiers = {
  0x01: 'L. Ctrl',
  0x02: 'L. Shift',
  0x04: 'L. Alt',
  0x08: 'L. GUI',
  0x10: 'R. Ctrl',
  0x20: 'R. Shift',
  0x40: 'R. Alt',
  0x80: 'R. GUI',
};

/// Reverse map for modifier bitmask to string
final Map<String, int> hidKeyboardModifiersReverse = {
  for (var entry in hidKeyboardModifiers.entries) entry.value: entry.key,
};

String hidModifierBitmaskList(int modifier) {
  // Use hidKeyboardModifiers from ble_hid.dart
  return hidKeyboardModifiersReverse.entries.where((entry) => (modifier & entry.value) != 0).map((entry) => entry.key).join(' + ');
}

/* ---------------------------- CONSUMER REPORTS ---------------------------- */
const Map<int, String> consumerReportCodes = {
  // Generic Control
  0x0001: "Consumer Control",

  // Power Control
  0x0030: "Power",
  0x0031: "Reset",
  0x0032: "Sleep",

  // Screen Brightness
  0x006F: "Brightness Increment",
  0x0070: "Brightness Decrement",

  // Mobile System Controls (Windows 8+)
  0x000C: "Wireless Radio Controls",
  0x00C6: "Wireless Radio Buttons",
  0x00C7: "Wireless Radio LED",
  0x00C8: "Wireless Radio Slider/Switch",

  // Media Control
  0x00CD: "Play/Pause",
  0x00B5: "Scan Next",
  0x00B6: "Scan Previous",
  0x00B7: "Stop",
  0x00E0: "Volume",
  0x00E2: "Mute",
  0x00E3: "Bass",
  0x00E4: "Treble",
  0x00E5: "Bass Boost",
  0x00E9: "Volume Up",
  0x00EA: "Volume Down",
  0x0152: "Bass Increment",
  0x0153: "Bass Decrement",
  0x0154: "Treble Increment",
  0x0155: "Treble Decrement",

  // Application Launcher
  0x0183: "Consumer Control Configuration",
  0x018A: "Email Reader",
  0x0192: "Calculator",
  0x0194: "Local Browser",

  // Browser/Explorer Specific
  0x0221: "Search",
  0x0223: "Home",
  0x0224: "Back",
  0x0225: "Forward",
  0x0226: "Stop",
  0x0227: "Refresh",
  0x022A: "Bookmarks",

  // Mouse Horizontal Scroll
  0x0238: "Pan",
};

/* --------------------------------- LABELS --------------------------------- */
/// Human-readable label for a single HID report — a media key, or the keyboard
/// modifier(s) + key(s). Returns 'None' when nothing is bound.
String hidReportLabel(HIDKeyboardReport report) {
  if (isKeyboardReportConsumerKey(report.keycodes)) {
    final code = (report.keycodes[0] << 8) | report.keycodes[1];
    return consumerReportCodes[code] ?? 'Media 0x${code.toRadixString(16)}';
  }
  final names = report.keycodes.where((k) => k != 0).map((k) => hidKeycodes[k] ?? '0x${k.toRadixString(16)}');
  final mod = hidModifierBitmaskList(report.modifier);
  final base = names.isEmpty ? 'None' : names.join(' + ');
  return mod.isEmpty ? base : '$mod + $base';
}
