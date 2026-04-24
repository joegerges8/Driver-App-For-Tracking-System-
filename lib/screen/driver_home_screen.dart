import 'package:delivery_boy_app/provider/current_location_provider.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/services/google_maps_loader.dart';
import 'package:delivery_boy_app/utils/utils.dart';
import 'package:delivery_boy_app/widgets/order_card.dart';
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
  bool isOnline = true;
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
    Future.microtask(() {
      if (!mounted) return;
      final token = context.read<AuthProvider>().token;
      if (token != null && token.isNotEmpty) {
        context.read<DeliveryProvider>().refreshMyOrders(token: token);
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
  void _maybeCenterOnLocation() {
    if (_hasCenteredOnLocation || _mapController == null) return;
    final loc = context.read<CurrentLocationProvider>();
    if (!loc.isLoading) {
      _hasCenteredOnLocation = true;
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(loc.currentLocation, 15),
      );
    }
  }

  Set<Marker> _buildMarkers(LatLng currentLocation) {
    return {
      Marker(
        markerId: const MarkerId("current_location"),
        position: currentLocation,
        infoWindow: const InfoWindow(
          title: "Current Location",
          snippet: "You are here!",
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
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

          if (locationProvider.errorMessage.isNotEmpty && !_locationErrorShown) {
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

          final Size size = MediaQuery.of(context).size;

          return FutureBuilder<bool>(
            future: _mapsLoadedFuture,
            builder: (context, snapshot) {
              final mapsOk = snapshot.data ?? true;

              return Stack(
                children: [
                  // Map is always in the tree so it initializes immediately.
                  if (mapsOk)
                    GoogleMap(
                      onMapCreated: _onMapCreated,
                      markers: _buildMarkers(locationProvider.currentLocation),
                      initialCameraPosition: CameraPosition(
                        target: locationProvider.currentLocation,
                        zoom: 15.0,
                      ),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      mapType: MapType.normal,
                    )
                  else
                    Container(
                      color: Colors.grey[200],
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(16),
                      child: const Text(
                        'Google Maps is not configured for web.\n'
                        'Run with --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY',
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // Loading overlay — map stays alive underneath.
                  if (locationProvider.isLoading)
                    Container(
                      color: Colors.white.withAlpha(200),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 15),
                            Text("Getting your location...."),
                          ],
                        ),
                      ),
                    ),

                  // Order card at the bottom.
                  if (locationProvider.errorMessage.isEmpty)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Consumer<DeliveryProvider>(
                          builder: (context, delivery, child) {
                            if (delivery.currentOrder == null) {
                              return const SizedBox.shrink();
                            }
                            return const OrderCard();
                          },
                        ),
                      ),
                    ),

                  // Online indicator at the top.
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: size.height * 0.12,
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Center(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 200,
                              height: 38,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.red, width: 2),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(2.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(30),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Text(
                                          "Online",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(child: SizedBox()),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
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
