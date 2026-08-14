import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/services/device_power_settings.dart';
import 'package:delivery_boy_app/services/tracking_permissions.dart';
import 'package:delivery_boy_app/utils/colors.dart';

/// Walks the driver through the phone settings their location needs in order to
/// keep reporting once they leave the app.
///
/// Every step here is one Android will not let an app set for itself. Vendors
/// on top of Android — Transsion's HiOS and XOS on Infinix and Tecno above all
/// — freeze backgrounded apps within minutes unless the driver has excused this
/// one by hand, which is why one driver on a Samsung stays on the dispatcher's
/// map all shift while the other two disappear the moment they open Maps. The
/// most an app can do is check what it can, explain the rest in the driver's own
/// language, and open the exact screen the setting lives on.
class TrackingSetupScreen extends StatefulWidget {
  const TrackingSetupScreen({super.key});

  @override
  State<TrackingSetupScreen> createState() => _TrackingSetupScreenState();
}

// The vendor screens are separate apps, so coming back from one is the moment
// to re-read what changed. WidgetsBindingObserver is what makes the checklist
// tick itself off as the driver returns, instead of making them find a refresh
// button.
class _TrackingSetupScreenState extends State<TrackingSetupScreen>
    with WidgetsBindingObserver {
  TrackingReadiness? _state;
  String _manufacturer = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final readiness = await TrackingPermissions.check();
    final manufacturer = await DevicePowerSettings.manufacturer();
    if (!mounted) return;
    setState(() {
      _state = readiness;
      _manufacturer = manufacturer;
    });
  }

  // Asks for "Allow all the time" where a dialog is still possible, and sends
  // the driver to the settings page where it is not — from Android 11 the
  // always grant simply cannot be requested in-app.
  Future<void> _handleLocation() async {
    final permission = await TrackingPermissions.requestLocation();
    if (permission != LocationPermission.always) {
      await TrackingPermissions.openAppSettings();
    }
    await _refresh();
  }

  Future<void> _handleBattery() async {
    await TrackingPermissions.requestBatteryExemption();
    await _refresh();
  }

  Future<void> _handleAutoStart() async {
    await TrackingPermissions.openAutoStartSettings();
    await _refresh();
  }

  // The vendor steps cannot be verified — nothing reports back whether an app
  // is on Transsion's auto-start list — so finishing is the driver's word for
  // it. The failure streak is cleared at the same time so the warning that
  // brought them here reflects what happens from now on.
  Future<void> _finish() async {
    await TrackingPermissions.markVendorStepsDone();
    await TrackingPermissions.clearFailureStreak();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = _state;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(l10n.trackingSetupTitle),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: state == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  l10n.trackingSetupIntro,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
                if (_manufacturer.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _manufacturer.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // GPS off is its own failure and hides every other one, so it
                // is shown first and only when it applies.
                if (!state.locationServiceEnabled)
                  _StepCard(
                    done: false,
                    title: l10n.trackingStepGpsTitle,
                    body: l10n.trackingStepGpsBody,
                    actionLabel: l10n.trackingOpenSettings,
                    onAction: () async {
                      await Geolocator.openLocationSettings();
                      await _refresh();
                    },
                  ),

                _StepCard(
                  done: state.hasBackgroundLocation,
                  title: l10n.trackingStepLocationTitle,
                  body: l10n.trackingStepLocationBody,
                  actionLabel: state.mustGrantFromSettings
                      ? l10n.trackingOpenSettings
                      : l10n.trackingGrant,
                  onAction: _handleLocation,
                ),

                _StepCard(
                  done: state.ignoringBatteryOptimizations,
                  title: l10n.trackingStepBatteryTitle,
                  body: l10n.trackingStepBatteryBody,
                  actionLabel: l10n.trackingGrant,
                  onAction: _handleBattery,
                ),

                // Only phones with a vendor power manager get the last two
                // steps. On stock Android and Samsung the two above are enough,
                // and inventing settings that do not exist on the driver's phone
                // would just teach them to ignore the screen.
                if (state.vendorKey != null) ...[
                  _StepCard(
                    done: false,
                    showCheck: false,
                    title: l10n.trackingStepAutostartTitle,
                    body: l10n.trackingStepAutostartBody(state.vendorKey),
                    actionLabel: l10n.trackingOpenSettings,
                    onAction: _handleAutoStart,
                  ),
                  _StepCard(
                    done: false,
                    showCheck: false,
                    title: l10n.trackingStepRecentsTitle,
                    body: l10n.trackingStepRecentsBody,
                  ),
                ],

                const SizedBox(height: 8),

                if (state.isReady)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: iconColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.trackingAllSet,
                            style: const TextStyle(
                              color: iconColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _refresh,
                        child: Text(l10n.trackingRecheck),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: buttonMainColor,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _finish,
                        child: Text(l10n.trackingFinish),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// One row of the checklist.
///
/// [showCheck] is false for the steps the app cannot verify — the vendor
/// screens report nothing back — so they are never drawn as satisfied. Showing
/// a green tick the app is only guessing at would be worse than showing none:
/// the driver would trust it, and the tracking would still be dead.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.done,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.showCheck = true,
  });

  final bool done;
  final bool showCheck;
  final String title;
  final String body;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: showCheck && done ? iconColor : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                showCheck && done
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 20,
                color: showCheck && done ? iconColor : Colors.grey.shade400,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.grey.shade800,
            ),
          ),
          if (actionLabel != null && onAction != null && !(showCheck && done))
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    color: buttonMainColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
