import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/provider/current_location_provider.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/provider/order_focus_controller.dart';
import 'package:delivery_boy_app/services/google_maps_loader.dart';
import 'package:delivery_boy_app/utils/order_pins.dart';
import 'package:delivery_boy_app/utils/run_framer.dart';
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
  // Decides when the camera may move on its own and what it frames. The
  // decision lives outside this widget on purpose: it used to be woven into
  // the rebuild timing here, a refactor lost one of its triggers, and a driver
  // sat looking at the location provider's San Francisco fallback until the
  // 30-second poll happened to rebuild the screen. See run_framer.dart for
  // the policy; this screen only feeds it and animates what it returns.
  final RunFramer _framer = RunFramer();

  // Set once the first orders request has come back, however it came back. A
  // driver with genuinely no orders has nothing to frame but themselves, and
  // this is what tells the camera to stop waiting for pins that are not coming.
  bool _ordersFetched = false;

  // Guards against overlapping camera animations: decide() offers the same
  // move again until it is committed, and two in flight would fight.
  bool _framing = false;
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

  // Where the map opens before anything is known: the whole of Lebanon.
  //
  // The camera has to point somewhere before GPS or the orders have answered,
  // and it used to point at the location provider's fallback — which is San
  // Francisco, so every cold start opened on California until the framing ran.
  // Every order this system carries is delivered inside Lebanon (the whole
  // town-coordinate table is built on that), so the one thing known before
  // anything loads is the country, and that is what the first frame shows.
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(33.9, 35.8),
    zoom: 8.0,
  );

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
    _maybeFrameRun();
  }

  // Opens the map on the whole run — the pins and, once GPS lands, the driver
  // — far enough out that all of it is on screen at once. The pins are never
  // kept waiting for GPS: they are framed the moment they are known, and the
  // frame is upgraded once when the fix arrives. All of that policy lives in
  // RunFramer; what remains here is reading the providers and moving the
  // camera.
  Future<void> _maybeFrameRun() async {
    if (_framing || _framer.done || _mapController == null || !mounted) return;

    final loc = context.read<CurrentLocationProvider>();
    final settled = !loc.isLoading;
    final driverLocation =
        settled && loc.errorMessage.isEmpty ? loc.currentLocation : null;

    final decision = _framer.decide(
      orderPoints: _lastOrderPoints,
      driverLocation: driverLocation,
      locationSettled: settled,
      ordersFetched: _ordersFetched,
    );
    if (decision == null) return;

    // Everything in one place — the driver standing in the town their only
    // order is in — has no box worth fitting, so it gets a plain zoom.
    final single = singlePointOf(decision.points);
    final update = single != null
        ? CameraUpdate.newLatLngZoom(single, 14)
        : CameraUpdate.newLatLngBounds(
            boundsFor(decision.points)!,
            _framePaddingPx,
          );

    _framing = true;
    try {
      await _mapController!.animateCamera(update);
      _framer.commit(decision);
    } catch (_) {
      // newLatLngBounds throws on Android if the map has no size yet. The
      // decision is left uncommitted, so the next provider notification offers
      // the same move again; nothing is worth showing the driver over it.
    } finally {
      _framing = false;
    }
  }

  // The driver's own position, plus a pin per order — red for the stops still
  // owed, green for the ones already delivered. See order_pins.dart for which
  // orders can be pinned and why an order never gets two pins.
  //
  // Delivered means today's deliveries, not every delivery ever made: the map
  // is a picture of the run the driver is on, and last month's completed orders
  // would bury this morning's under a field of green.
  // [currentLocation] is null until GPS has actually resolved: the provider
  // starts on a San Francisco fallback, and drawing the driver's marker there
  // put a blue pin in California on every cold start until the fix landed.
  Set<Marker> _buildMarkers(
    LatLng? currentLocation,
    Set<Marker> orderMarkers,
  ) {
    final l10n = context.l10n;
    return {
      if (currentLocation != null)
        Marker(
          markerId: const MarkerId("current_location"),
          position: currentLocation,
          infoWindow: InfoWindow(
            title: l10n.currentLocation,
            snippet: l10n.youAreHere,
          ),
          // Blue, not red: red now means "order still to deliver", and the
          // driver's own position is the one pin on this map that is not a
          // stop.
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
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

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Consumer<CurrentLocationProvider>(
        builder: (context, locationProvider, child) {
          // The framing retry rides this builder and not the outer build: this
          // is the one place that reruns for BOTH inputs — the orders (through
          // the outer watch rebuilding the whole screen) and GPS resolving
          // (through this Consumer). Scheduling it outside missed the GPS
          // notification, and a driver whose orders beat their fix sat on the
          // fallback map until the 30-second poll rebuilt the screen.
          //
          // After the frame, because the map may not exist yet on this build
          // and the camera cannot be moved before it does.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _maybeFrameRun();
          });

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
                                  !locationProvider.isLoading &&
                                          locationProvider
                                              .errorMessage.isEmpty
                                      ? locationProvider.currentLocation
                                      : null,
                                  orderMarkers,
                                ),
                                initialCameraPosition: _initialCamera,
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

                  // Loading overlay — map stays alive underneath. Only while
                  // there is nothing to look at: once the pins are known the
                  // map is already useful, and GPS finishing its fix is not
                  // worth hiding them for ten seconds.
                  if (locationProvider.isLoading && _lastOrderPoints.isEmpty)
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
