import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/provider/current_location_provider.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
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
  // Track whether we've already moved the camera to the real GPS location.
  bool _hasCenteredOnLocation = false;
  // Prevent the location-error toast from firing on every rebuild.
  bool _locationErrorShown = false;

  final String _webMapsKey = const String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
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
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // If location is already resolved by the time the map is ready, center now.
    _maybeCenterOnLocation();
  }

  // Move the camera to the real GPS location once — avoids repeated animations.
  // Skip when GPS failed so we don't pan to the San Francisco fallback.
  void _maybeCenterOnLocation() {
    if (_hasCenteredOnLocation || _mapController == null) return;
    final loc = context.read<CurrentLocationProvider>();
    if (!loc.isLoading && loc.errorMessage.isEmpty) {
      _hasCenteredOnLocation = true;
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(loc.currentLocation, 15),
      );
    }
  }

  // The driver's own position, plus a pin per order — red for the stops still
  // owed, green for the ones already delivered. See order_pins.dart for which
  // orders can be pinned and why an order never gets two pins.
  //
  // Delivered means today's deliveries, not every delivery ever made: the map
  // is a picture of the run the driver is on, and last month's completed orders
  // would bury this morning's under a field of green.
  Set<Marker> _buildMarkers(LatLng currentLocation, DeliveryProvider delivery) {
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
      ...buildOrderMarkers(
        pending: delivery.orders,
        delivered: delivery.todaysCompletedOrders,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read: the pins have to be redrawn when an order is
    // delivered, when the dispatcher assigns a new one, and on every
    // background poll that changes either list.
    final delivery = context.watch<DeliveryProvider>();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Consumer<CurrentLocationProvider>(
        builder: (context, locationProvider, child) {
          // Once location resolves, move the camera (handled after the frame).
          if (!locationProvider.isLoading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _maybeCenterOnLocation();
            });
          }

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
                                  delivery,
                                ),
                                initialCameraPosition: CameraPosition(
                                  target: locationProvider.currentLocation,
                                  zoom: 15.0,
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
                      const SwipeableOrderCards(),
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
