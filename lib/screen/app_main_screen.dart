import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/screen/driver_home_screen.dart';
import 'package:delivery_boy_app/screen/orders_screen.dart';
import 'package:delivery_boy_app/screen/profile_screen.dart';
import 'package:delivery_boy_app/screen/shipment_screen.dart';
import 'package:delivery_boy_app/screen/tracking_setup_screen.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/services/background_location_service.dart';
import 'package:delivery_boy_app/services/tracking_permissions.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

class AppMainScreen extends StatefulWidget {
  const AppMainScreen({super.key});

  @override
  State<AppMainScreen> createState() => _AppMainScreenState();
}

// WidgetsBindingObserver lets this screen hear about the app being sent to the
// background and brought back, which is when the driver's order list is most
// likely to be out of date with the dashboard.
class _AppMainScreenState extends State<AppMainScreen>
    with WidgetsBindingObserver {
  // IndexedStack keeps all pages alive so state (map, orders) is preserved on tab switch.
  // ProfileScreen replaces the old Center(child: Text("Profile")) placeholder.
  final List<Widget> pages = [
     DriverHomeScreen(),
  OrdersScreen(),
      ShipmentScreen(),
      ProfileScreen(),
  ];
  // initially display the index of the pages list
  int _currentIndex = 0;
  final List<IconData> _icons = [
    FontAwesomeIcons.house,
    FontAwesomeIcons.boxOpen,
    FontAwesomeIcons.truckFast,
    FontAwesomeIcons.solidCircleUser,
  ];
  // Labels are resolved inside build() rather than stored in a field so they
  // follow the language toggle instead of freezing at whatever was active when
  // the state object was first created.
  List<String> _labels(BuildContext context) {
    final l10n = context.l10n;
    return [l10n.navHome, l10n.navOrders, l10n.navShipment, l10n.navProfile];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start polling after the first frame, once providers can be read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutoRefresh();
      _refreshTrackingReadiness();
    });
  }

  // Held so dispose can stop the timer without reading a provider off a
  // context that is already being torn down (logout unmounts this screen).
  DeliveryProvider? _delivery;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _delivery = context.read<DeliveryProvider>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _delivery?.stopAutoRefresh();
    super.dispose();
  }

  // Polls only while the app is actually on screen. Coming back from the
  // background refreshes immediately, so an order deleted from the dashboard
  // while the driver was in Maps is gone the moment they switch back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      _startAutoRefresh();
      // Coming back is also when the answer is most likely to have changed:
      // the driver may have just been in Android's settings, or may have been
      // away long enough for the service to have been killed and started
      // failing.
      _refreshTrackingReadiness();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _delivery?.stopAutoRefresh();
    }
  }

  void _startAutoRefresh() {
    if (!mounted) return;
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) return;
    context.read<DeliveryProvider>().startAutoRefresh(token: token);

    // The polling above stops the moment this screen leaves the driver's
    // display. The service is the half that keeps watching while the app is
    // merely put away — it is what keeps a started delivery streaming to the
    // customer while the driver is in Maps, and what keeps the driver on the
    // dispatcher's map the rest of the time. Starting it here covers logging in
    // and reopening alike, and does nothing if it already runs.
    BackgroundLocationService.startWatching();
  }

  // ── Tracking health ───────────────────────────────────────────────────────
  // Whether the phone is set up to let a backgrounded delivery keep reporting,
  // and whether it has in fact stopped. Null until the first check comes back,
  // which is what keeps the banner from flashing on at launch.
  TrackingReadiness? _tracking;

  Future<void> _refreshTrackingReadiness() async {
    final readiness = await TrackingPermissions.check();
    if (!mounted) return;
    setState(() => _tracking = readiness);
  }

  Future<void> _openTrackingSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TrackingSetupScreen()),
    );
    await _refreshTrackingReadiness();
  }

  @override
  Widget build(BuildContext context) {
    final labels = _labels(context);
    return Scaffold(
      body: Column(
        children: [
          _TrackingBanner(
            readiness: _tracking,
            onTap: _openTrackingSetup,
          ),
          Expanded(
            child: IndexedStack(index: _currentIndex, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(top: 10, bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 5,
              offset: Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_icons.length, (index) {
            final bool isSelected = _currentIndex == index;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // Pages are kept alive in `pages`, so initState won't re-run.
                // Refresh orders when entering Home/Orders tabs.
                if (index == 0 || index == 1) {
                  final token = context.read<AuthProvider>().token;
                  final delivery = context.read<DeliveryProvider>();
                  if (!delivery.isLoadingOrders && token != null && token.isNotEmpty) {
                    delivery.refreshMyOrders(token: token);
                  }
                }
                setState(() {
                  _currentIndex = index;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    decoration: isSelected
                        ? BoxDecoration(
                            color: buttonSecondaryColor,
                            borderRadius: BorderRadius.circular(15),
                          )
                        : null,
                    child: Icon(
                      _icons[index],
                      size: 18,
                      color: isSelected ? buttonMainColor : Colors.black,
                    ),
                  ),
                  Text(
                    labels[index],
                    style: TextStyle(
                      color: isSelected ? buttonMainColor : Colors.black,
                    ),
                  ),
                ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Sits above every tab whenever the driver's location is at risk of stopping,
/// or has already stopped.
///
/// It is deliberately unmissable and deliberately not a dialog. The failure it
/// warns about is silent by nature — the app keeps working, the orders keep
/// listing, and the only symptom is a dispatcher who cannot see the driver and
/// a customer watching a marker that never moves. A driver who does not know
/// something is wrong cannot go and fix it, and nobody else can fix it for them.
class _TrackingBanner extends StatelessWidget {
  const _TrackingBanner({required this.readiness, required this.onTap});

  final TrackingReadiness? readiness;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final state = readiness;
    if (state == null || !state.needsAttention) return const SizedBox.shrink();

    final l10n = context.l10n;

    // Two different messages for two different situations. "Might stop" is a
    // setup the driver has not finished; "has stopped" is the service having
    // actually gone quiet, which is more urgent and worth the stronger colour.
    final stopped = state.isFailing;
    final background = stopped ? buttonMainColor : pickedUpColor;

    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  stopped ? Icons.location_off : Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    stopped
                        ? l10n.trackingBannerStopped
                        : l10n.trackingBannerIncomplete,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.trackingBannerFix,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
