import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// SharedPreferences keys — must match auth_provider.dart's _tokenKey
const _tokenKey = 'driver_auth_token';
const _orderIdKey = 'bg_active_order_id';
const _baseUrl = 'https://dispatcher-dashboard.up.railway.app';

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

  /// Start tracking for the given orderId. Safe to call multiple times —
  /// if the service is already running it just updates the stored orderId.
  static Future<void> startTracking(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_orderIdKey, orderId);
    final isRunning = await _svc.isRunning();
    if (!isRunning) await _svc.startService();
  }

  /// Stop tracking. Clears the orderId so the background isolate stops itself
  /// on its next tick, and signals it via the stopService event.
  static Future<void> stopTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_orderIdKey);
    _svc.invoke('stopService');
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
    final token = prefs.getString(_tokenKey);
    final orderId = prefs.getString(_orderIdKey);

    // Stop if order is done or driver logged out
    if (token == null || orderId == null) {
      service.stopSelf();
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      await http.post(
        Uri.parse('$_baseUrl/api/drivers/me/orders/$orderId/location'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'latitude': position.latitude,
          'longitude': position.longitude,
        }),
      );
    } catch (_) {
      // Silent — a missed ping is acceptable
    }
  });
}
