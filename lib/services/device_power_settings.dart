import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The phone's own power management, which Flutter has no plugin-free view of.
///
/// Android's documented API stops at the battery-optimisation exemption. Every
/// vendor then adds a second layer on top of it — Transsion's "Power Marathon"
/// and app freezer on Infinix and Tecno, MIUI's autostart list on Xiaomi, and so
/// on — and none of them can be switched on from code. What this class can do is
/// tell the app which vendor it is running on and put the driver on the right
/// settings screen; the tap has to be theirs.
///
/// This is the difference between the Samsung driver staying on the dispatcher's
/// map and the Infinix and Tecno drivers dropping off it a few minutes after
/// they switch to Google Maps.
class DevicePowerSettings {
  DevicePowerSettings._();

  // Must match POWER_CHANNEL in MainActivity.kt.
  static const _channel = MethodChannel('delivery_boy_app/power');

  /// True on anything that is not Android, where none of this applies and the
  /// callers should treat the device as already set up rather than nag.
  static bool get _unsupported =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.android;

  /// Raw `Build.MANUFACTURER`, for display ("Infinix", "Samsung").
  static Future<String> manufacturer() async {
    if (_unsupported) return '';
    return await _invoke<String>('manufacturer') ?? '';
  }

  /// Which family of power manager this phone has, or null for stock Android
  /// and vendors that need no special handling — Samsung included.
  ///
  /// One of: `transsion` (Infinix/Tecno/itel), `xiaomi`, `oppo`, `vivo`,
  /// `huawei`. The setup screen keys its instructions off this.
  static Future<String?> vendorKey() async {
    if (_unsupported) return null;
    return _invoke<String>('vendorKey');
  }

  /// Whether the app is exempt from Doze. False is the single most common
  /// reason a backgrounded delivery stops reporting.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (_unsupported) return true;
    return await _invoke<bool>('isIgnoringBatteryOptimizations') ?? false;
  }

  /// Shows the system "allow this app to run in the background?" dialog.
  /// Returns false only if nothing could be opened at all.
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (_unsupported) return true;
    return await _invoke<bool>('requestIgnoreBatteryOptimizations') ?? false;
  }

  /// Opens the vendor's autostart / background-app list, falling back to this
  /// app's settings page when the vendor screen cannot be found.
  static Future<bool> openAutoStartSettings() async {
    if (_unsupported) return false;
    return await _invoke<bool>('openAutoStartSettings') ?? false;
  }

  /// Opens the battery-usage screen for this app.
  static Future<bool> openBatterySettings() async {
    if (_unsupported) return false;
    return await _invoke<bool>('openBatterySettings') ?? false;
  }

  /// Opens this app's entry in Android Settings.
  static Future<bool> openAppSettings() async {
    if (_unsupported) return false;
    return await _invoke<bool>('openAppSettings') ?? false;
  }

  // Every one of these is advisory. A phone that answers none of them should
  // leave the driver looking at a setup screen that still works, not a crash,
  // so a missing channel or a vendor throwing on an intent reads as "unknown".
  static Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
