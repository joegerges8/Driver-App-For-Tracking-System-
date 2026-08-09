import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/screen/driver_home_screen.dart';
import 'package:delivery_boy_app/screen/orders_screen.dart';
import 'package:delivery_boy_app/screen/profile_screen.dart';
import 'package:delivery_boy_app/screen/shipment_screen.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoRefresh());
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
  }

  @override
  Widget build(BuildContext context) {
    final labels = _labels(context);
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
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
