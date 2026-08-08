import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// SharedPreferences keys — must match auth_provider.dart's _tokenKey
const _tokenKey = 'driver_auth_token';

// The set of orders the driver has started and not yet finished. A driver can
// carry several orders at once (a batch run), and every one of them needs its
// own stream of GPS pings — each order has its own customer watching its own
// tracking page. Storing a list rather than a single id is what makes that
// possible: the previous single-id key meant starting a second delivery
// silently replaced the first, freezing the first customer's map.
const _orderIdsKey = 'bg_active_order_ids';

// The single-order key used before batch delivery existed. Read once on
// startup so an app upgrade mid-delivery keeps sharing location instead of
// going dark, then cleared.
const _legacyOrderIdKey = 'bg_active_order_id';

const _baseUrl = 'https://dispatcher-dashboard.up.railway.app';

// Reads the active order ids, migrating the legacy single-id key if present.
// Shared by the UI isolate and the background isolate — both need the same
// view of which orders are active, and only SharedPreferences is visible to both.
Future<List<String>> _readActiveOrderIds(SharedPreferences prefs) async {
  final ids = prefs.getStringList(_orderIdsKey);
  if (ids != null) return ids;

  final legacy = prefs.getString(_legacyOrderIdKey);
  if (legacy != null && legacy.isNotEmpty) {
    await prefs.setStringList(_orderIdsKey, [legacy]);
    await prefs.remove(_legacyOrderIdKey);
    return [legacy];
  }

  return const [];
}

class BackgroundLocationService {
  static final _svc = FlutterBackgroundService();

  /// Call once from main() before runApp to register the service configuration.
  static Future<void> initialize() async {
    await _svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'driver_location_channel',
        initialNotificationTitle: 'Driver App – Location Active',
        initialNotificationContent: 'Sharing your location with the dispatcher',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// Adds an order to the tracked set and starts the service if it is not
  /// already running. Safe to call multiple times for the same order.
  static Future<void> startTracking(String orderId) async {
    if (orderId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final ids = await _readActiveOrderIds(prefs);
    if (!ids.contains(orderId)) {
      await prefs.setStringList(_orderIdsKey, [...ids, orderId]);
    }

    final isRunning = await _svc.isRunning();
    if (!isRunning) await _svc.startService();
  }

  /// Removes a single order from the tracked set, leaving the driver's other
  /// deliveries streaming. Stops the service entirely once the last one is done.
  static Future<void> stopTrackingOrder(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await _readActiveOrderIds(prefs);
    final remaining = ids.where((id) => id != orderId).toList();

    if (remaining.isEmpty) {
      await stopTracking();
      return;
    }

    await prefs.setStringList(_orderIdsKey, remaining);
  }

  /// Stops tracking every order. Clears the stored ids so the background
  /// isolate stops itself on its next tick, and signals it via stopService.
  static Future<void> stopTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_orderIdsKey);
    await prefs.remove(_legacyOrderIdKey);
    _svc.invoke('stopService');
  }

  /// The orders currently being tracked. Used on app start to restore the
  /// in-progress deliveries after the app was killed mid-run.
  static Future<List<String>> activeOrderIds() async {
    final prefs = await SharedPreferences.getInstance();
    return _readActiveOrderIds(prefs);
  }

  static Future<bool> isRunning() => _svc.isRunning();
}

// ── Background isolate entry points ──────────────────────────────────────────
// These functions run in a separate Dart isolate with no access to Provider,
// BuildContext, or any Flutter UI. They communicate only via SharedPreferences
// and the ServiceInstance event bus.

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {

  // Allow the main isolate to stop the service via invoke('stopService')
  service.on('stopService').listen((_) => service.stopSelf());

  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'Driver App – Location Active',
      content: 'Sharing your location with the dispatcher',
    );
  }

  // Post GPS to the backend every 15 seconds.
  // Using a timer (instead of a stream) is more reliable in background isolates.
  Timer.periodic(const Duration(seconds: 15), (_) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // pick up ids written by the UI isolate
    final token = prefs.getString(_tokenKey);
    final orderIds = await _readActiveOrderIds(prefs);

    // Stop if every order is done or the driver logged out
    if (token == null || orderIds.isEmpty) {
      service.stopSelf();
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      // One GPS read, fanned out to every active order. The driver has a single
      // position; each order simply records it against its own tracking token.
      await Future.wait(
        orderIds.map(
          (orderId) => http.post(
            Uri.parse('$_baseUrl/api/drivers/me/orders/$orderId/location'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'latitude': position.latitude,
              'longitude': position.longitude,
            }),
          ),
        ),
      );
    } catch (_) {
      // Silent — a missed ping is acceptable
    }
  });
}
