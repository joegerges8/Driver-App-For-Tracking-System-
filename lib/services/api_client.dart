import 'dart:convert';

import 'package:delivery_boy_app/services/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Added in this change:
// Minimal HTTP client for the Node backend driver auth endpoints.
// - POST /api/drivers/signup
// - POST /api/drivers/login
// - GET  /api/drivers/me
class ApiClient {
  static Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  static Future<Map<String, dynamic>> signupDriver({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    http.Response res;
    try {
      res = await http.post(
        _uri('/api/drivers/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'full_name': fullName,
          'email': email,
          'phone': phone,
          'password': password,
        }),
      );
    } catch (e) {
      throw ApiException('Network error: $e');
    }

    final body = _decodeJson(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }

    throw ApiException(_errorMessage(body) ?? 'Signup failed (HTTP ${res.statusCode})');
  }

  static Future<Map<String, dynamic>> loginDriver({
    required String email,
    required String password,
  }) async {
    http.Response res;
    try {
      res = await http.post(
        _uri('/api/drivers/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );
    } catch (e) {
      throw ApiException('Network error: $e');
    }

    final body = _decodeJson(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }

    throw ApiException(_errorMessage(body) ?? 'Login failed (HTTP ${res.statusCode})');
  }

  // Added to fix the change-password feature.
  // Previously the profile screen had a TODO stub that faked a success after 800 ms
  // without calling any API — the password was never changed in the database.
  //
  // This method sends a POST to /api/drivers/me/password with the driver's current
  // password (so the backend can verify it) and the new password they want to set.
  // The JWT token is included in the Authorization header so the backend knows which
  // driver is making the request without needing them to send their email again.
  //
  // Error handling wraps _decodeJson in a try/catch because if the server is not yet
  // deployed or the route doesn't exist, it returns an HTML page instead of JSON —
  // without the guard, jsonDecode throws a FormatException with a confusing message.
  static Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {
    http.Response res;
    try {
      res = await http.post(
        _uri('/api/drivers/me/password'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );
    } catch (e) {
      throw ApiException('Network error: $e');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return;

    // Guard against non-JSON responses (e.g. HTML 404 page from Railway when the
    // backend endpoint hasn't been deployed yet) so the user sees a clean error.
    String? message;
    try {
      final body = _decodeJson(res);
      message = _errorMessage(body);
    } catch (_) {}
    throw ApiException(message ?? 'Failed to change password (HTTP ${res.statusCode})');
  }

  static Future<Map<String, dynamic>> getMe({required String token}) async {
    http.Response res;
    try {
      res = await http.get(
        _uri('/api/drivers/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      throw ApiException('Network error: $e');
    }

    final body = _decodeJson(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }

    throw ApiException(
      _errorMessage(body) ?? 'Failed to fetch profile (HTTP ${res.statusCode})',
    );
  }

  static Future<List<dynamic>> getMyOrders({required String token}) async {
    http.Response res;
    try {
      res = await http.get(
        _uri('/api/drivers/me/orders'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      throw ApiException('Network error: $e');
    }

    final decoded = _decodeJsonAny(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (decoded is List) return decoded;
      return [];
    }

    final body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    throw ApiException(
      _errorMessage(body) ?? 'Failed to fetch orders (HTTP ${res.statusCode})',
    );
  }

  // Calls Google Directions API directly from the device, bypassing the backend.
  // This avoids backend API key restriction issues (e.g. Android-restricted keys
  // being rejected for server-side HTTP calls on Railway).
  static Future<DirectionsResult> getDirectionsDirect({
    required LatLng origin,
    required LatLng destination,
    required String apiKey,
  }) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'departure_time': 'now',
      'key': apiKey,
    });

    http.Response res;
    try {
      res = await http.get(uri);
    } catch (e) {
      throw ApiException('Network error: $e');
    }

    final body = _decodeJson(res);
    final googleStatus = body['status'] as String? ?? '';
    if (googleStatus == 'OK') {
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) throw ApiException('No route found');
      final route = routes[0] as Map<String, dynamic>;
      final polyline = (route['overview_polyline'] as Map?)?['points'] as String? ?? '';
      final leg = ((route['legs'] as List?)?.first) as Map<String, dynamic>? ?? {};
      final dist = leg['distance'] as Map? ?? {};
      final dur = leg['duration'] as Map? ?? {};
      final durTraffic = (leg['duration_in_traffic'] as Map?) ?? dur;
      return DirectionsResult(
        polyline: polyline,
        distanceText: dist['text'] as String? ?? '',
        distanceMeters: (dist['value'] as num?)?.toInt() ?? 0,
        durationText: dur['text'] as String? ?? '',
        durationSeconds: (dur['value'] as num?)?.toInt() ?? 0,
        durationInTrafficText: durTraffic['text'] as String? ?? '',
        durationInTrafficSeconds: (durTraffic['value'] as num?)?.toInt() ?? 0,
      );
    }

    final googleMsg = body['error_message'] as String? ?? googleStatus;
    throw ApiException('Directions: $googleMsg');
  }

  static Future<DirectionsResult> getDirections({
    required String token,
    required LatLng origin,
    required LatLng destination,
  }) async {
    http.Response res;
    try {
      final u = _uri('/api/maps/directions').replace(queryParameters: {
        'originLat': origin.latitude.toString(),
        'originLng': origin.longitude.toString(),
        'destLat': destination.latitude.toString(),
        'destLng': destination.longitude.toString(),
      });

      res = await http.get(
        u,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      throw ApiException('Network error: $e');
    }

    final body = _decodeJson(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final poly = body['polyline'];
      if (poly is String && poly.isNotEmpty) {
        return DirectionsResult.fromJson(body);
      }
      throw ApiException('Directions response missing polyline');
    }

    throw ApiException(
      _errorMessage(body) ?? 'Failed to fetch directions (HTTP ${res.statusCode})',
    );
  }

  static Map<String, dynamic> _decodeJson(http.Response res) {
    if (res.body.isEmpty) return {};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  static dynamic _decodeJsonAny(http.Response res) {
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  static String? _errorMessage(Map<String, dynamic> body) {
    final err = body['error'];
    if (err is String && err.trim().isNotEmpty) return err;
    return null;
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class DirectionsResult {
  final String polyline;
  final String distanceText;
  final int distanceMeters;
  final String durationText;
  final int durationSeconds;
  final String durationInTrafficText;
  final int durationInTrafficSeconds;

  DirectionsResult({
    required this.polyline,
    required this.distanceText,
    required this.distanceMeters,
    required this.durationText,
    required this.durationSeconds,
    required this.durationInTrafficText,
    required this.durationInTrafficSeconds,
  });

  factory DirectionsResult.fromJson(Map<String, dynamic> json) {
    return DirectionsResult(
      polyline: json['polyline'] as String,
      distanceText: (json['distanceText'] as String?) ?? '',
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
      durationText: (json['durationText'] as String?) ?? '',
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      durationInTrafficText: (json['durationInTrafficText'] as String?) ?? '',
      durationInTrafficSeconds: (json['durationInTrafficSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}
