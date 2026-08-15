import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/provider/current_location_provider.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/provider/order_focus_controller.dart';
import 'package:delivery_boy_app/services/google_maps_loader.dart';
import 'package:delivery_boy_app/utils/order_pins.dart';
import 'package:delivery_boy_app/utils/utils.dart';
import 'package:delivery_boy_app/widgets/swipeable_order_cards.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  GoogleMapController? _mapController;
  // Cache the future so it doesn't reset on every rebuild.
  late final Future<bool> _mapsLoadedFuture;
  // Whether the camera has already been put where it belongs, and whether the
  // orders it should have been framed around had arrived by then.
  //
  // The two are separate because the answers arrive at different times: GPS
  // resolves in a second or so, the orders take a network round trip. Framing
  // on the driver alone the moment GPS lands would open the map on the street
  // they are parked on — the thing this is meant to stop — so a location-only
  // framing is provisional and is redone once the orders are in.
  bool _hasFramedRun = false;
  bool _hasFramedWithOrders = false;

  // Set once the first orders request has come back, however it came back. A
  // driver with genuinely no orders has nothing to frame but themselves, and
  // this is what tells the camera to stop waiting for pins that are not coming.
  bool _ordersFetched = false;
  // Prevent the location-error toast from firing on every rebuild.
  bool _locationErrorShown = false;

  final String _webMapsKey = const String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  // Carries a tapped pin down to the cards, which bring that order to the
  // front. Owned here because this is where the two halves of the screen meet.
  final OrderFocusController _orderFocus = OrderFocusController();

  // Where the order pins were as of the last build, so the map can be framed
  // around them the moment it is ready — which may be before or after the
  // orders land, in either order.
  List<LatLng> _lastOrderPoints = const [];

  // Room left around the outermost pins when the camera is fitted to them, in
  // logical pixels. A marker is drawn upwards from its point and is about 40
  // tall, so anything less puts the top pin's head under the edge.
  static const double _framePaddingPx = 64;

  @override
  void initState() {
    super.initState();
    _mapsLoadedFuture = ensureGoogleMapsLoaded(apiKey: _webMapsKey);
    Future.microtask(() async {
      if (!mounted) return;
      final token = context.read<AuthProvider>().token;
      if (token != null && token.isNotEmpty) {
        final delivery = context.read<DeliveryProvider>();
        await delivery.refreshMyOrders(token: token);
        // The completed list used to be fetched only when the driver opened the
        // Done tab. The map's green pins are drawn from it, so the home screen
        // now asks for it too — otherwise a driver who never opens that tab
        // would see today's finished stops missing from the map rather than
        // done. Fetching it once also lets the background poll keep it fresh,
        // so a delivery marked on another device turns green here within the
        // poll interval.
        await delivery.refreshCompletedOrders(token: token, silent: true);
      }
      if (mounted) setState(() => _ordersFetched = true);
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // If the run is already known by the time the map is ready, frame it now.
    _maybeFrameRun(_lastOrderPoints);
  }

  // Opens the map on the whole run: the driver's own position and every pin,
  // far enough out that all of it is on screen at once.
  //
  // It used to drop straight onto the driver at zoom 15, which answers "which
  // street am I on" — a question the driver can answer by looking up. What
  // they cannot see from the cab is how the day is spread out, and that is
  // what the pins were added for, so that is what the camera opens on.
  //
  // Runs at most twice: once provisionally when GPS lands, and once more when
  // the orders arrive. After the orders have been framed it never moves the
  // camera again, because from then on the camera belongs to the driver — a
  // map that re-framed itself on every poll would drag them back out every
  // time they zoomed in on where they were going.
  Future<void> _maybeFrameRun(List<LatLng> orderPoints) async {
    if (_hasFramedWithOrders || _mapController == null) return;

    final loc = context.read<CurrentLocationProvider>();
    if (loc.isLoading) return;

    if (orderPoints.isEmpty) {
      // Still on their way: framing on the driver alone now would be the
      // street-level view all over again, so wait for them.
      if (!_ordersFetched) return;
      // Fetched and there are none. The driver alone is all there is to frame,
      // and having framed it once, doing it again on every rebuild would drag
      // the camera back from wherever they had moved it.
      if (_hasFramedRun) return;
    }

    // GPS failing leaves currentLocation on its San Francisco fallback, which
    // would stretch the box across the Atlantic. The orders alone are still
    // worth framing.
    final points = <LatLng>[
      if (loc.errorMessage.isEmpty) loc.currentLocation,
      ...orderPoints,
    ];
    if (points.isEmpty) return;

    _hasFramedRun = true;
    if (orderPoints.isNotEmpty) _hasFramedWithOrders = true;

    // Everything in one place — the driver standing in the town their only
    // order is in — has no box worth fitting, so it gets a plain zoom.
    final single = singlePointOf(points);
    final update = single != null
        ? CameraUpdate.newLatLngZoom(single, 14)
        : CameraUpdate.newLatLngBounds(boundsFor(points)!, _framePaddingPx);

    try {
      await _mapController!.animateCamera(update);
    } catch (_) {
      // newLatLngBounds throws on Android if the map has no size yet. Nothing
      // is worth showing the driver over it — the map is simply left where it
      // was, and the next attempt (or the driver's own finger) moves it.
      _hasFramedRun = false;
      _hasFramedWithOrders = false;
    }
  }

  // The driver's own position, plus a pin per order — red for the stops still
  // owed, green for the ones already delivered. See order_pins.dart for which
  // orders can be pinned and why an order never gets two pins.
  //
  // Delivered means today's deliveries, not every delivery ever made: the map
  // is a picture of the run the driver is on, and last month's completed orders
  // would bury this morning's under a field of green.
  Set<Marker> _buildMarkers(
    LatLng currentLocation,
    Set<Marker> orderMarkers,
  ) {
    final l10n = context.l10n;
    return {
      Marker(
        markerId: const MarkerId("current_location"),
        position: currentLocation,
        infoWindow: InfoWindow(
          title: l10n.currentLocation,
          snippet: l10n.youAreHere,
        ),
        // Blue, not red: red now means "order still to deliver", and the
        // driver's own position is the one pin on this map that is not a stop.
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      ...orderMarkers,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read: the pins have to be redrawn when an order is
    // delivered, when the dispatcher assigns a new one, and on every
    // background poll that changes either list.
    final delivery = context.watch<DeliveryProvider>();

    // Built once here rather than inside the map builder: the camera is framed
    // around the same pins the map is drawing, and building them twice would
    // let the two disagree.
    final orderMarkers = buildOrderMarkers(
      pending: delivery.orders,
      delivered: delivery.todaysCompletedOrders,
      onTap: _orderFocus.focus,
    );
    _lastOrderPoints = orderMarkers.map((m) => m.position).toList();

    // After the frame, because the map may not exist yet on this build and the
    // camera cannot be moved before it does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeFrameRun(_lastOrderPoints);
    });

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Consumer<CurrentLocationProvider>(
        builder: (context, locationProvider, child) {
          if (locationProvider.errorMessage.isNotEmpty &&
              !_locationErrorShown) {
            _locationErrorShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              showAppSnackbar(
                context: context,
                type: SnackbarType.error,
                description: locationProvider.errorMessage,
              );
            });
          }

          return FutureBuilder<bool>(
            future: _mapsLoadedFuture,
            builder: (context, snapshot) {
              final mapsOk = snapshot.data ?? true;

              return Stack(
                children: [
                  Column(
                    children: [
                      // Map fills the remaining space above the order widget.
                      Expanded(
                        child: mapsOk
                            ? GoogleMap(
                                onMapCreated: _onMapCreated,
                                markers: _buildMarkers(
                                  locationProvider.currentLocation,
                                  orderMarkers,
                                ),
                                // Wide from the very first frame. The camera is
                                // framed to the run a moment later, and
                                // opening at street level meanwhile would show
                                // the driver a zoom-out they did not ask for.
                                // It is also what they are left looking at if
                                // the framing cannot run at all.
                                initialCameraPosition: CameraPosition(
                                  target: locationProvider.currentLocation,
                                  zoom: 11.0,
                                ),
                                myLocationEnabled: true,
                                myLocationButtonEnabled: false,
                                mapType: MapType.normal,
                              )
                            : Container(
                                color: Colors.grey[200],
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  context.l10n.mapsNotConfigured,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                      ),

                      // Swipeable order cards embedded below the map.
                      SwipeableOrderCards(focus: _orderFocus),
                    ],
                  ),

                  // Loading overlay — map stays alive underneath.
                  if (locationProvider.isLoading)
                    Container(
                      color: Colors.white.withAlpha(200),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 15),
                            Text(context.l10n.gettingYourLocation),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
