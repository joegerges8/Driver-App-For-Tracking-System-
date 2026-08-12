import 'dart:async';

import 'package:delivery_boy_app/services/api_client.dart';
import 'package:delivery_boy_app/services/background_location_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Holds authentication state for the driver:
// - JWT token persisted in SharedPreferences so the driver stays logged in across app restarts
// - driver profile map populated from login/signup response, and refreshable via GET /api/drivers/me
class AuthProvider extends ChangeNotifier {
  static const _tokenKey = 'driver_auth_token';

  bool _initialized = false;
  bool _isBusy = false;
  // Separate flag from _isBusy so the profile screen can show a lightweight
  // spinner without blocking login/signup buttons elsewhere.
  bool _isRefreshingProfile = false;
  String? _token;
  Map<String, dynamic>? _driver;
  String? _error;

  bool get initialized => _initialized;
  bool get isBusy => _isBusy;
  bool get isRefreshingProfile => _isRefreshingProfile;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  String? get token => _token;
  Map<String, dynamic>? get driver => _driver;
  String? get error => _error;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _initialized = true;
    notifyListeners();

    // Only the token is persisted, so a driver who reopens the app is
    // authenticated but has no profile until something asks for one. That used
    // to be the profile screen alone; now the WhatsApp message signs off with
    // the driver's name, so it has to be there from the first order they open.
    //
    // Deliberately not awaited: startup must not block on the network, and
    // refreshProfile already swallows its own failures. Anything reading the
    // name before this lands falls back to leaving it out.
    if (isAuthenticated) {
      unawaited(refreshProfile());
    }
  }

  Future<void> login({required String email, required String password}) async {
    _setBusy(true);
    _error = null;

    try {
      final res = await ApiClient.loginDriver(email: email, password: password);
      final token = res['token'];
      if (token is! String || token.isEmpty) {
        throw ApiException('Login response missing token');
      }

      _token = token;
      _driver = res['driver'] is Map<String, dynamic>
          ? (res['driver'] as Map<String, dynamic>)
          : null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signup({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    _setBusy(true);
    _error = null;

    try {
      final res = await ApiClient.signupDriver(
        fullName: fullName,
        email: email,
        phone: phone,
        password: password,
      );

      final token = res['token'];
      if (token is! String || token.isEmpty) {
        throw ApiException('Signup response missing token');
      }

      _token = token;
      _driver = res['driver'] is Map<String, dynamic>
          ? (res['driver'] as Map<String, dynamic>)
          : null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  // Added to fix the change-password feature.
  // Passes the stored JWT token to ApiClient.changePassword so the backend can
  // identify which driver is making the request. Throws if the driver is not
  // currently logged in (token is missing) or if the backend rejects the request
  // (e.g. wrong current password) — the error bubbles up to the UI for display.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_token == null || _token!.isEmpty) throw ApiException('Not authenticated');
    await ApiClient.changePassword(
      token: _token!,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  // Fetches fresh driver data from GET /api/drivers/me and updates _driver.
  // Called by ProfileScreen on load and on pull-to-refresh.
  // Errors are swallowed intentionally — the profile still shows the stale data
  // from login/signup rather than breaking the screen on a network hiccup.
  Future<void> refreshProfile() async {
    if (_token == null || _token!.isEmpty) return;
    _isRefreshingProfile = true;
    notifyListeners();
    try {
      final data = await ApiClient.getMe(token: _token!);
      // Backend may return {driver: {...}} or the driver object directly.
      final driverData = data['driver'];
      _driver = driverData is Map<String, dynamic> ? driverData : data;
    } catch (_) {
      // keep existing driver data on failure
    } finally {
      _isRefreshingProfile = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _token = null;
    _driver = null;
    _error = null;
    notifyListeners();

    // Stops location sharing along with the session. The service does stop
    // itself once the token is gone, but it would carry the previous driver's
    // orders in its stored lists until then — and on a shared phone the next
    // person to log in would inherit them.
    await BackgroundLocationService.stopTracking();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }
}
