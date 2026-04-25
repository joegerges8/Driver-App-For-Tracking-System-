import 'dart:async';

import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/current_location_provider.dart';
import 'package:delivery_boy_app/screen/app_main_screen.dart';
import 'package:delivery_boy_app/services/api_client.dart';
import 'package:delivery_boy_app/services/google_maps_loader.dart';
import 'package:delivery_boy_app/services/navigation_launcher.dart';
import 'package:delivery_boy_app/services/polyline_decoder.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/widgets/custom_button.dart';
import 'package:delivery_boy_app/widgets/order_on_the_way.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

class DeliveryMapScreen extends StatefulWidget {
  const DeliveryMapScreen({super.key});

  @override
  State<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends State<DeliveryMapScreen> {
  GoogleMapController? _mapController;
  bool _shownDirectionsError = false;
  bool _isFetchingRoute = false;

  // Route metadata shown in the info card.
  String _distanceText = '';
  String _durationText = '';
  String _durationInTrafficText = '';
  Color _trafficColor = Colors.green;

  // Points waiting to be fitted once the map controller is ready.
  List<LatLng> _pendingBoundsPoints = [];

  // Debounce route refresh when origin updates.
  Timer? _routeRefreshDebounce;

  StreamSubscription<Position>? _positionSubscription;
  LatLng? _lastOriginForRoute;
  DateTime? _lastRouteFetchAt;

  // The same key used by Maps SDK for Android — works on-device for Directions API too.
  static const String _androidMapsKey = 'AIzaSyDQ2c_pOSOFYSjxGMwkFvCVWKjYOM9siow';

  final String _webMapsKey = const String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  late final Future<bool> _mapsLoadedFuture;

  @override
  void initState() {
    super.initState();
    _mapsLoadedFuture = ensureGoogleMapsLoaded(apiKey: _webMapsKey);
    Future.microtask(_fetchDirections);
    Future.microtask(_startLiveLocationUpdates);
  }

  @override
  void dispose() {
    _routeRefreshDebounce?.cancel();
    _positionSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // Awaits a status-update Future and shows a snackbar when it fails.
  // Written as a proper async method so mounted/context/ScaffoldMessenger
  // are in scope as normal State members, not inside a closure.
  Future<void> _syncStatus(Future<void> update) async {
    try {
      await update;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status sync failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  static bool _isValidLatLng(LatLng? p) {
    if (p == null) return false;
    if (p.latitude.abs() < 0.001 || p.longitude.abs() < 0.001) return false;
    return p.latitude >= -90 &&
        p.latitude <= 90 &&
        p.longitude >= -180 &&
        p.longitude <= 180;
  }

  List<LatLng> _sanitizeRoutePoints({
    required List<LatLng> points,
    required LatLng origin,
    required LatLng destination,
  }) {
    // 1) Remove invalid coordinates.
    final valid = points.where(_isValidLatLng).toList(growable: false);
    if (valid.length < 2) return const <LatLng>[];

    // 2) Remove extreme outliers (these cause the "world laser lines").
    final straightMeters = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );

    // Allow generous slack for detours, but still reject absurd points.
    final cutoffMeters = straightMeters.isFinite && straightMeters > 0
        ? (straightMeters * 10).clamp(300000.0, 2000000.0)
        : 800000.0;

    final filtered = <LatLng>[];
    for (final p in valid) {
      final d1 = Geolocator.distanceBetween(
        origin.latitude,
        origin.longitude,
        p.latitude,
        p.longitude,
      );
      final d2 = Geolocator.distanceBetween(
        destination.latitude,
        destination.longitude,
        p.latitude,
        p.longitude,
      );

      // Keep points that are reasonably close to either end.
      if (d1 <= cutoffMeters || d2 <= cutoffMeters) {
        filtered.add(p);
      }
    }

    // If filtering was too aggressive, fall back to just-valid points.
    if (filtered.length >= 2) return filtered;
    return valid;
  }

  LatLng? _currentOrigin() {
    final delivery = context.read<DeliveryProvider>();
    if (_isValidLatLng(delivery.currentDeliveryBoyPosition)) {
      return delivery.currentDeliveryBoyPosition;
    }

    final loc = context.read<CurrentLocationProvider>();
    if (!loc.isLoading && loc.errorMessage.isEmpty) {
      return loc.currentLocation;
    }

    return null;
  }

  Future<void> _startLiveLocationUpdates() async {
    if (_positionSubscription != null) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
      );

      _positionSubscription =
          Geolocator.getPositionStream(locationSettings: settings).listen(
        (pos) {
          if (!mounted) return;
          final origin = LatLng(pos.latitude, pos.longitude);
          if (!_isValidLatLng(origin)) return;

          final delivery = context.read<DeliveryProvider>();
          delivery.updateDriverPosition(origin);

          if (!_shouldFetchRouteForOrigin(origin)) return;

          _routeRefreshDebounce?.cancel();
          _routeRefreshDebounce = Timer(const Duration(milliseconds: 600), () {
            if (!mounted) return;
            _lastOriginForRoute = origin;
            _lastRouteFetchAt = DateTime.now();
            _fetchDirections();
          });
        },
        onError: (_) {
          // Ignore streaming errors; the map still works with last known origin.
        },
      );
    } catch (_) {
      // Ignore; location stream is best-effort.
    }
  }

  bool _shouldFetchRouteForOrigin(LatLng origin) {
    final now = DateTime.now();

    // Hard throttle to avoid spamming the Directions API.
    final lastAt = _lastRouteFetchAt;
    if (lastAt != null && now.difference(lastAt).inSeconds < 5) {
      return false;
    }

    final order = context.read<DeliveryProvider>().currentOrder;
    final dest = order?.deliveryLocation;
    if (!_isValidLatLng(dest)) return false;

    final lastOrigin = _lastOriginForRoute;
    if (lastOrigin == null) return true;

    final movedMeters = Geolocator.distanceBetween(
      lastOrigin.latitude,
      lastOrigin.longitude,
      origin.latitude,
      origin.longitude,
    );

    // Refresh when driver moved enough, or periodically to keep ETA fresh.
    if (movedMeters >= 30) return true;
    if (lastAt != null && now.difference(lastAt).inSeconds >= 25) return true;
    return false;
  }

  Future<void> _fetchDirections() async {
    if (_isFetchingRoute) return;
    _isFetchingRoute = true;

    // Capture coords early so we can still fit bounds even if directions fail.
    LatLng? origin;
    LatLng? dest;

    try {
      final token = context.read<AuthProvider>().token;
      final delivery = context.read<DeliveryProvider>();
      final order = delivery.currentOrder;
      if (token == null || token.isEmpty || order == null) return;

      origin = _currentOrigin() ?? delivery.currentDeliveryBoyPosition ?? order.pickupLocation;
      dest = order.deliveryLocation;

      // Skip routing when coords are missing or clearly invalid (equator/prime meridian).
      if (!_isValidLatLng(origin)) return;
      if (dest.latitude.abs() < 0.001 || dest.longitude.abs() < 0.001) return;

      // Try calling Google Directions API directly from the device first.
      // This avoids the backend API key restriction issues that cause
      // "No route returned from Google Directions API" on Railway.
      // If the direct call fails, fall back to the backend proxy.
      DirectionsResult result;
      try {
        result = await ApiClient.getDirectionsDirect(
          origin: origin,
          destination: dest,
          apiKey: _androidMapsKey,
        );
      } catch (_) {
        result = await ApiClient.getDirections(
          token: token,
          origin: origin,
          destination: dest,
        );
      }

      final points = decodePolyline(result.polyline);
      if (points.length < 2) return;

      final sanitized = _sanitizeRoutePoints(
        points: points,
        origin: origin,
        destination: dest,
      );
      if (sanitized.length < 2) return;

      delivery.setRoutePoints(sanitized);

      if (!mounted) return;
      setState(() {
        _distanceText = result.distanceText;
        _durationText = result.durationText;
        _durationInTrafficText = result.durationInTrafficText.isNotEmpty
            ? result.durationInTrafficText
            : result.durationText;
        _trafficColor = _computeTrafficColor(
          result.durationSeconds,
          result.durationInTrafficSeconds,
        );
      });

      // Include endpoints to stabilize bounds even if the polyline starts/ends slightly off.
      _fitBoundsOrDefer([origin, ...sanitized, dest]);
    } catch (e) {
      // Even when directions fail, zoom the camera out to show both the driver
      // and the destination marker so the driver can still see where to go.
      if (origin != null && dest != null &&
          _isValidLatLng(origin) && _isValidLatLng(dest)) {
        _fitBoundsOrDefer([origin, dest]);
      }

      if (!_shownDirectionsError && mounted) {
        _shownDirectionsError = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      _isFetchingRoute = false;
    }
  }

  // Fit the camera to show the whole route. If the map isn't ready yet, defer.
  void _fitBoundsOrDefer(List<LatLng> pts) {
    if (_mapController != null) {
      _fitBounds(pts);
    } else {
      _pendingBoundsPoints = pts;
    }
  }

  Future<void> _fitBounds(List<LatLng> pts) async {
    final controller = _mapController;
    if (controller == null || pts.isEmpty) return;

    // If bounds look absurdly large, don't zoom out to the whole world.
    final valid = pts.where(_isValidLatLng).toList(growable: false);
    if (valid.length < 2) return;

    double minLat = valid.first.latitude;
    double maxLat = valid.first.latitude;
    double minLng = valid.first.longitude;
    double maxLng = valid.first.longitude;

    for (final p in valid) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Rough sanity: if the polyline spans huge degrees, it's probably broken.
    if ((maxLat - minLat) > 20 || (maxLng - minLng) > 40) {
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          80,
        ),
      );
    } catch (_) {}
  }

  Color _computeTrafficColor(int durationSec, int trafficSec) {
    if (durationSec == 0) return Colors.green;
    final ratio = trafficSec / durationSec;
    if (ratio <= 1.15) return Colors.green;
    if (ratio <= 1.5) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Consumer<DeliveryProvider>(
        builder: (context, provider, child) {
          return FutureBuilder<bool>(
            future: _mapsLoadedFuture,
            builder: (context, snapshot) {
              final mapsOk = snapshot.data ?? true;

              return Stack(
                children: [
                  // ── Map ──────────────────────────────────────────────────
                  if (mapsOk)
                    _buildGoogleMap(provider)
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

                  // ── Route info card (distance / time / traffic) ──────────
                  if (_distanceText.isNotEmpty)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 12,
                      right: 12,
                      child: _buildRouteInfoCard(),
                    ),

                  // ── Order status + action buttons ────────────────────────
                  if (provider.currentOrder != null &&
                      provider.status != DeliveryStatus.rejected)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(1),
                        child: OrderOnTheWay(
                          order: provider.currentOrder!,
                          status: provider.status,
                          onButtonPressed: () {
                            final authToken = context.read<AuthProvider>().token ?? '';
                            switch (provider.status) {
                              case DeliveryStatus.pickingUp:
                                _syncStatus(provider.markPickedUp(token: authToken));
                                // Open external turn-by-turn navigation to the customer's location.
                                final dest = provider.currentOrder?.deliveryLocation;
                                if (dest != null) {
                                  NavigationLauncher.openGoogleMapsNavigation(
                                    destination: dest,
                                  );
                                }
                                break;
                              case DeliveryStatus.destinationReached:
                                provider.markAdDelivered();
                                break;
                              case DeliveryStatus.markingAsDelivered:
                                _syncStatus(provider.markDelivered(token: authToken));
                                break;
                              default:
                                break;
                            }
                          },
                        ),
                      ),
                    ),

                  // ── Delivery completed overlay ───────────────────────────
                  if (provider.status == DeliveryStatus.delivered)
                    _buildDeliveryCompletedCard(provider),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRouteInfoCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Traffic dot
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _trafficColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          // ETA with traffic
          Expanded(
            child: Text(
              _durationInTrafficText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Distance
          Text(
            _distanceText,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          // Normal duration (no traffic)
          if (_durationText != _durationInTrafficText)
            Text(
              '($_durationText no traffic)',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
        ],
      ),
    );
  }

  Widget _buildGoogleMap(DeliveryProvider provider) {
    final order = provider.currentOrder;
    final fallback = const LatLng(37.7749, -122.4194);

    final target = _isValidLatLng(provider.currentDeliveryBoyPosition)
      ? provider.currentDeliveryBoyPosition!
      : _isValidLatLng(order?.deliveryLocation)
        ? order!.deliveryLocation
        : _isValidLatLng(context.read<CurrentLocationProvider>().currentLocation)
          ? context.read<CurrentLocationProvider>().currentLocation
          : fallback;

    return GoogleMap(
      onMapCreated: (GoogleMapController controller) {
        _mapController = controller;
        // If directions were already fetched before the map was ready, fit now.
        if (_pendingBoundsPoints.isNotEmpty) {
          _fitBounds(_pendingBoundsPoints);
          _pendingBoundsPoints = [];
        }
      },
      initialCameraPosition: CameraPosition(target: target, zoom: 14.0),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + (_distanceText.isNotEmpty ? 90 : 12),
        bottom: provider.currentOrder != null ? 260 : 12,
        left: 12,
        right: 12,
      ),
      markers: _buildMarkers(provider),
      polylines: _buildPolylines(provider),
      zoomControlsEnabled: false,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
    );
  }

  Set<Marker> _buildMarkers(DeliveryProvider provider) {
    final markers = <Marker>{};
    if (provider.currentOrder == null) return markers;

    final origin = _currentOrigin();
    if (_isValidLatLng(origin)) {
      markers.add(Marker(
        markerId: const MarkerId('origin'),
        position: origin!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Your location'),
      ));
    }

    final dest = provider.currentOrder!.deliveryLocation;
    if (dest.latitude.abs() > 0.001 && dest.longitude.abs() > 0.001) {
      markers.add(Marker(
        markerId: const MarkerId('delivery'),
        position: dest,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Delivery location'),
      ));
    }

    return markers;
  }

  Set<Polyline> _buildPolylines(DeliveryProvider provider) {
    if (provider.routePoints.length < 2 ||
        provider.status == DeliveryStatus.waitingForAcceptance ||
        provider.status == DeliveryStatus.rejected) {
      return {};
    }

    // Draw an outline polyline first, then the main one on top.
    return {
      Polyline(
        polylineId: const PolylineId('route_outline'),
        points: provider.routePoints,
        color: routeOutlineColor,
        width: 10,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        geodesic: false,
      ),
      Polyline(
        polylineId: const PolylineId('route_main'),
        points: provider.routePoints,
        color: routeMainColor,
        width: 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        geodesic: false,
      ),
    };
  }


  Widget _buildDeliveryCompletedCard(DeliveryProvider provider) {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(15),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: NetworkImage(
                        'https://media.tenor.com/bm8Q6yAlsPsAAAAj/verified.gif',
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Delivery Completed',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Great Job! Your delivery has been successfully completed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: CustomButton(
                    title: 'Go Home',
                    onPressed: () {
                      Navigator.of(context).pop();
                      provider.reseDelivery();
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AppMainScreen(),
                        ),
                        (route) => false,
                      );
                    },
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
