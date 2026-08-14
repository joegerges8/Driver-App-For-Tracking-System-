import 'dart:async';
import 'dart:convert';

import 'package:delivery_boy_app/services/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ApiClient
//
// A static HTTP client that communicates with the Node.js backend.
// Every method corresponds to one backend endpoint. The class uses the
// http package to make network requests and throws an ApiException with a
// human-readable message whenever a request fails, so callers (providers)
// can display the error to the driver without crashing the app.
//
// Authentication: protected endpoints include an "Authorization: Bearer <token>"
// header. The token is a JWT issued by the backend on login and stored in
// AuthProvider.
//
// Endpoints covered:
//   POST /api/drivers/signup
//   POST /api/drivers/login
//   POST /api/drivers/me/password
//   GET  /api/drivers/me
//   GET  /api/drivers/me/orders                    — active assigned orders
//   GET  /api/drivers/me/orders/completed          — completed (delivered) orders
//   GET  /api/drivers/me/orders/returned           — returned orders
//   POST /api/drivers/me/orders/:id/location       — GPS ping for customer tracking
//   PATCH /api/drivers/me/orders/:id/note          — save the driver's own note
//   GET  /api/maps/directions                      — route between two coordinates
class ApiClient {
  static Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  // How long any one request is given before it is called a failure.
  //
  // The http package sets no deadline of its own, so a request whose
  // connection dies without being closed — a phone going into a lift, or being
  // put away with a request in flight — never completes and never throws. The
  // callers are written around requests that finish one way or the other: the
  // order poll waits on one before starting the next, so a single hung request
  // stopped the driver's list refreshing until the app was restarted. Twenty
  // seconds is far longer than any of these endpoints needs and short enough
  // that the driver is told rather than left waiting.
  static const Duration _timeout = Duration(seconds: 20);

  // Runs a request under that deadline and turns anything that goes wrong at
  // the network layer into an ApiException the caller can show.
  static Future<http.Response> _send(Future<http.Response> request) async {
    try {
      return await request.timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Network timed out — check your connection');
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> signupDriver({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final res = await _send(http.post(
      _uri('/api/drivers/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'password': password,
      }),
    ));

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
    final res = await _send(http.post(
      _uri('/api/drivers/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    ));

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
    final res = await _send(http.post(
      _uri('/api/drivers/me/password'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    ));

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
    final res = await _send(http.get(
      _uri('/api/drivers/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ));

    final body = _decodeJson(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }

    throw ApiException(
      _errorMessage(body) ?? 'Failed to fetch profile (HTTP ${res.statusCode})',
    );
  }

  // Fetches the list of completed (DELIVERED) orders for the authenticated driver.
  // Called lazily when the driver first opens the "Done" tab, so we avoid an
  // unnecessary network request on every app start.
  // Returns an empty list (not an error) if the driver has no completed orders yet.
  static Future<List<dynamic>> getCompletedOrders({required String token}) async {
    final res = await _send(http.get(
      _uri('/api/drivers/me/orders/completed'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ));

    final decoded = _decodeJsonAny(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (decoded is List) return decoded;
      return [];
    }

    final body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    throw ApiException(
      _errorMessage(body) ?? 'Failed to fetch completed orders (HTTP ${res.statusCode})',
    );
  }

  // Fetches the orders this driver brought back (RETURNED) from
  // GET /api/drivers/me/orders/returned.
  //
  // The Returned tab used to be kept in memory only, so closing the app emptied
  // it. This is where it is read back from.
  //
  // Returns an empty list (not an error) if the driver has returned nothing.
  static Future<List<dynamic>> getReturnedOrders({required String token}) async {
    final res = await _send(http.get(
      _uri('/api/drivers/me/orders/returned'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ));

    final decoded = _decodeJsonAny(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (decoded is List) return decoded;
      return [];
    }

    final body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    throw ApiException(
      _errorMessage(body) ?? 'Failed to fetch returned orders (HTTP ${res.statusCode})',
    );
  }

  // Fire-and-forget GPS ping so the customer tracking page can show the
  // driver's current position. Errors are swallowed — a missed ping just
  // means the customer sees a slightly stale marker, which is acceptable.
  static Future<void> postLocation({
    required String token,
    required String orderId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _send(http.post(
        _uri('/api/drivers/me/orders/$orderId/location'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
      ));
    } catch (_) {
      // Silent — never interrupt the driver's map experience over a ping failure.
    }
  }

  // Tells the backend the driver has set off with this order, which is what
  // the dispatcher's "avg to deliver" is measured from — without it the only
  // start time the dashboard had was when Shopify created the order, so an
  // order that sat at the shop overnight read as an overnight delivery.
  //
  // Sends the time only: the order's status is the dispatcher's to move, and
  // starting a delivery has never changed it. Failures are swallowed for the
  // same reason GPS pings are — the driver is on their way either way, and one
  // missing stamp costs one order's place in an average, nothing more.
  static Future<void> startOrderDelivery({
    required String token,
    required String orderId,
  }) async {
    try {
      await _send(http.post(
        _uri('/api/drivers/me/orders/$orderId/start'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ));
    } catch (_) {
      // Silent by design — see above.
    }
  }

  static Future<void> updateOrderStatus({
    required String token,
    required String orderId,
    required String status,
  }) async {
    final res = await _send(http.patch(
      _uri('/api/drivers/me/orders/$orderId/status'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'status': status}),
    ));

    if (res.statusCode >= 200 && res.statusCode < 300) return;

    String? message;
    try {
      final body = _decodeJson(res);
      message = _errorMessage(body);
    } catch (_) {}
    throw ApiException(message ?? 'Failed to update order status (HTTP ${res.statusCode})');
  }

  // Saves the driver's own note on one of their orders. An empty note clears
  // whatever was there, which is how the driver deletes a note.
  static Future<void> updateOrderNote({
    required String token,
    required String orderId,
    required String note,
  }) async {
    final res = await _send(http.patch(
      _uri('/api/drivers/me/orders/$orderId/note'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'note': note}),
    ));

    if (res.statusCode >= 200 && res.statusCode < 300) return;

    String? message;
    try {
      final body = _decodeJson(res);
      message = _errorMessage(body);
    } catch (_) {}
    throw ApiException(message ?? 'Failed to save note (HTTP ${res.statusCode})');
  }

  static Future<List<dynamic>> getMyOrders({required String token}) async {
    final res = await _send(http.get(
      _uri('/api/drivers/me/orders'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ));

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

    final res = await _send(http.get(uri));

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
    final u = _uri('/api/maps/directions').replace(queryParameters: {
      'originLat': origin.latitude.toString(),
      'originLng': origin.longitude.toString(),
      'destLat': destination.latitude.toString(),
      'destLng': destination.longitude.toString(),
    });

    final res = await _send(http.get(
    u,
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    ));

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
