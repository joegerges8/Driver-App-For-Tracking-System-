import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_boy_app/services/device_power_settings.dart';

// Set once the driver has been through the vendor steps on the tracking setup
// screen. Those steps cannot be verified from code — nothing reports back
// whether an app is on Transsion's autostart list — so an acknowledgement is
// the best signal available, and it is only ever used to decide whether to keep
// showing the reminder.
const _vendorStepsKey = 'tracking_vendor_steps_done';

// How many ticks in a row the background service has failed to report a
// position. Written by the background isolate (see background_location_service
// .dart), read here so a driver whose tracking has actually broken is asked to
// check their settings again even if they went through the screen months ago.
const kPingFailureStreakKey = 'bg_ping_failure_streak';

// Two consecutive misses is 30 seconds of silence, which is already halfway to
// the dispatcher greying the driver out. Three keeps a single tunnel or a
// momentary GPS glitch from putting a warning in front of the driver.
const _failureStreakForWarning = 3;

/// Everything that has to be true for a backgrounded delivery to keep
/// reporting, and which of it currently is.
class TrackingReadiness {
  const TrackingReadiness({
    required this.permission,
    required this.locationServiceEnabled,
    required this.ignoringBatteryOptimizations,
    required this.vendorKey,
    required this.vendorStepsAcknowledged,
    required this.failureStreak,
  });

  final LocationPermission permission;
  final bool locationServiceEnabled;
  final bool ignoringBatteryOptimizations;

  /// The phone's power-manager family, or null on stock Android and Samsung,
  /// where no vendor screen needs visiting. See [DevicePowerSettings.vendorKey].
  final String? vendorKey;
  final bool vendorStepsAcknowledged;

  /// Consecutive failed ticks reported by the background service.
  final int failureStreak;

  bool get hasBackgroundLocation => permission == LocationPermission.always;

  bool get hasAnyLocation =>
      permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;

  /// True when Android will not show the "Allow all the time" prompt again and
  /// the driver has to grant it from the settings app instead.
  bool get mustGrantFromSettings =>
      permission == LocationPermission.deniedForever ||
      permission == LocationPermission.whileInUse;

  bool get needsVendorSteps => vendorKey != null && !vendorStepsAcknowledged;

  /// Tracking is currently failing in the field, whatever the settings say.
  bool get isFailing => failureStreak >= _failureStreakForWarning;

  /// Nothing left to ask the driver for.
  bool get isReady =>
      locationServiceEnabled &&
      hasBackgroundLocation &&
      ignoringBatteryOptimizations &&
      !needsVendorSteps;

  /// Whether to put the reminder banner in front of the driver: either setup is
  /// incomplete, or it looked complete and stopped working anyway.
  bool get needsAttention => !isReady || isFailing;
}

/// Gets and keeps the permissions a delivery needs in order to keep reporting
/// while the driver is doing something else with their phone.
///
/// Declaring `ACCESS_BACKGROUND_LOCATION` in the manifest does not grant it —
/// an earlier build declared it and never asked, so every driver was running on
/// "while in use", which the phone is entitled to revoke the moment the app
/// leaves the screen.
class TrackingPermissions {
  TrackingPermissions._();

  /// Reads the current state without prompting for anything.
  static Future<TrackingReadiness> check() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // the failure streak is written by the other isolate

    return TrackingReadiness(
      permission: await Geolocator.checkPermission(),
      locationServiceEnabled: await Geolocator.isLocationServiceEnabled(),
      ignoringBatteryOptimizations:
          await DevicePowerSettings.isIgnoringBatteryOptimizations(),
      vendorKey: await DevicePowerSettings.vendorKey(),
      vendorStepsAcknowledged: prefs.getBool(_vendorStepsKey) ?? false,
      failureStreak: prefs.getInt(kPingFailureStreakKey) ?? 0,
    );
  }

  /// Asks for location, escalating to "Allow all the time" where Android still
  /// allows a prompt.
  ///
  /// Android 10 grants background location through the same dialog; from
  /// Android 11 the dialog only ever offers "While using the app", and the
  /// always grant has to come from the settings screen. So this asks twice and
  /// then stops: the caller checks [TrackingReadiness.mustGrantFromSettings]
  /// and sends the driver to [openAppSettings] rather than prompting into a
  /// dialog that will not appear.
  static Future<LocationPermission> requestLocation() async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // A second request is what upgrades whileInUse to always on the versions
    // that permit it at all. Harmless where it does not: it returns the
    // existing grant without showing anything.
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }

    return permission;
  }

  /// Shows the system battery-optimisation dialog.
  static Future<void> requestBatteryExemption() =>
      DevicePowerSettings.requestIgnoreBatteryOptimizations();

  /// Opens the vendor's autostart / background-app list.
  static Future<void> openAutoStartSettings() =>
      DevicePowerSettings.openAutoStartSettings();

  /// Opens this app's page in Android Settings, where "Allow all the time"
  /// lives on Android 11+.
  static Future<void> openAppSettings() => DevicePowerSettings.openAppSettings();

  /// Records that the driver has been through the vendor steps. Not a promise
  /// that they were completed — only that we have stopped asking.
  static Future<void> markVendorStepsDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vendorStepsKey, true);
  }

  /// Clears the failure streak after the driver has been back through setup, so
  /// the warning reflects what has happened since rather than before.
  static Future<void> clearFailureStreak() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kPingFailureStreakKey, 0);
  }
}
