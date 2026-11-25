# Vendored universal_ble 3.4.1 (patched)

Copy of pub.dev `universal_ble` 3.4.1 (BSD-3-Clause, see LICENSE), without
the example, tests, assets and tooling folders.

## Patch

`windows/src/universal_ble_plugin.cpp`, `ConnectAsync`: services whose
characteristics query returns `AccessDenied` are skipped instead of failing
the connection (search for `TAPDANCER PATCH`).

Windows protects the HID service (0x1812), so without this every TapDancer
connect on Windows fails with
`Failed to get characteristics for service 00001812-...: AccessDenied`.
Broken upstream since 2.2.0 (2.1.0 skipped such services).

## Removing

Once upstream ships the fix: delete this folder and the `dependency_overrides`
entry in `pubspec.yaml`, then bump `universal_ble` to the fixed version.

[issue link](https://github.com/Navideck/universal_ble/issues/400)
