import 'package:flutter_test/flutter_test.dart';
import 'package:tapdancer/models/device_settings.dart';
import 'package:tapdancer/utils/config_io.dart';

/// Builds a config with distinctive values per button/click so a round-trip can
/// be checked exactly, including a consumer-key report ([hi, lo, 0,0,0, 0xFF]).
UserConfig _sampleConfig(String name) {
  ButtonConfig button(int base, {bool consumer = false}) => ButtonConfig(
        timingDoubleClickMs: base == 0 ? 0 : 200 + base, // button 0 = direct mode
        timingLongClickMs: 3000 + base,
        keycodes: [
          HIDKeyboardReport(modifier: 1, keycodes: [base + 1]),
          HIDKeyboardReport(modifier: 2, keycodes: [base + 2, base + 3]),
          HIDKeyboardReport(modifier: 0, keycodes: const []),
          consumer
              ? HIDKeyboardReport(modifier: 0, keycodes: const [0x00, 0xCD, 0, 0, 0, 0xFF]) // play/pause
              : HIDKeyboardReport(modifier: 4, keycodes: [base + 4]),
        ],
      );

  return UserConfig(
    timeAutoOffS: 600,
    configName: name,
    inUse: true,
    buttonConfigs: [button(0), button(1, consumer: true), button(2)],
  );
}

void _expectConfigEquals(UserConfig actual, UserConfig expected) {
  expect(actual.configName, expected.configName);
  expect(actual.timeAutoOffS, expected.timeAutoOffS);
  expect(actual.inUse, expected.inUse);
  expect(actual.buttonConfigs.length, buttonNum);
  for (var b = 0; b < buttonNum; b++) {
    final a = actual.buttonConfigs[b];
    final e = expected.buttonConfigs[b];
    expect(a.timingDoubleClickMs, e.timingDoubleClickMs, reason: 'button $b dc');
    expect(a.timingLongClickMs, e.timingLongClickMs, reason: 'button $b lc');
    expect(a.keycodes.length, clickNum);
    for (var c = 0; c < clickNum; c++) {
      expect(a.keycodes[c].modifier, e.keycodes[c].modifier, reason: 'button $b click $c modifier');
      expect(a.keycodes[c].keycodes, e.keycodes[c].keycodes, reason: 'button $b click $c keycodes');
    }
  }
}

void main() {
  group('config_io round-trip', () {
    test('single config survives encode -> decode exactly', () {
      final original = _sampleConfig('My Preset');
      final json = encodeSingle(original, appVersion: '1.2.0', settingsVersion: 7);

      final imported = decode(json);

      expect(imported.kind, ImportKind.single);
      expect(imported.settingsVersion, 7);
      expect(imported.configs.length, 1);
      _expectConfigEquals(imported.configs.first, original);
    });

    test('consumer-key padding is preserved through the round-trip', () {
      final original = _sampleConfig('Media');
      final json = encodeSingle(original, appVersion: '1.2.0', settingsVersion: 1);

      final imported = decode(json);

      // Button 1, long-press (click index 3) is the consumer key.
      expect(imported.configs.first.buttonConfigs[1].keycodes[3].keycodes,
          const [0x00, 0xCD, 0, 0, 0, 0xFF]);
    });

    test('all-configs file decodes back to the same set', () {
      final configs = List<UserConfig>.generate(configNum, (i) => _sampleConfig('Slot $i'));
      final json = encodeAll(configs, appVersion: '1.2.0', settingsVersion: 3);

      final imported = decode(json);

      expect(imported.kind, ImportKind.all);
      expect(imported.configs.length, configNum);
      for (var i = 0; i < configNum; i++) {
        _expectConfigEquals(imported.configs[i], configs[i]);
      }
    });
  });

  group('config_io validation', () {
    test('garbled text throws ConfigImportException', () {
      expect(() => decode('not json at all {'), throwsA(isA<ConfigImportException>()));
    });

    test('foreign JSON (wrong format marker) is rejected', () {
      expect(() => decode('{"format":"something.else","configs":[]}'),
          throwsA(isA<ConfigImportException>()));
    });

    test('single file missing its config payload is rejected', () {
      expect(() => decode('{"format":"tapdancer.config","formatVersion":1,"kind":"single"}'),
          throwsA(isA<ConfigImportException>()));
    });

    test('short button/keycode lists are padded to fixed lengths', () {
      // A single config with only one button and one keycode entry.
      const json = '{'
          '"format":"tapdancer.config","formatVersion":1,"kind":"single",'
          '"config":{"configName":"Short","timeAutoOffS":0,"inUse":true,'
          '"buttonConfigs":[{"dc":250,"lc":4000,"keycodes":[{"modifier":0,"keycodes":[4]}]}]}'
          '}';

      final imported = decode(json);
      final cfg = imported.configs.first;

      expect(cfg.buttonConfigs.length, buttonNum);
      expect(cfg.buttonConfigs[0].keycodes.length, clickNum);
      expect(cfg.buttonConfigs[0].keycodes[0].keycodes, const [4]);
      // Padded entries are empty reports.
      expect(cfg.buttonConfigs[0].keycodes[1].keycodes, const <int>[]);
    });
  });
}
