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
