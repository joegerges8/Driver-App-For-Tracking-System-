import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class CurrentLocationProvider extends ChangeNotifier {
  // default: San Francisco
  LatLng _currentLocation = LatLng(37.7749, -122.4194);
  bool _isLoading = true;
  String _errorMessage = '';
  // public getters to access private varibales
  LatLng get currentLocation => _currentLocation;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;

  CurrentLocationProvider() {
    _getCurrentLocation();
  }
  // main function to get device's current location
  Future<void> _getCurrentLocation() async {
    try {
      // check if loction permission is granted
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // request permission if denied
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _errorMessage = "Location permission denied. Use default location.";
          _isLoading = false;
          notifyListeners();
          return;
        }
      }
            // Check if permission is permanently denied
      if (permission == LocationPermission.deniedForever) {
        _errorMessage =
            'Location permissions are permanently denied. Using default location.';
        _isLoading = false;
        notifyListeners();
        return;
      }
      // check if location service are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _errorMessage = "Location service are disable";
        _isLoading = false;
        notifyListeners();
        return;
      }
      // get current position with a 10-second timeout so the loading
      // overlay doesn't hang forever when GPS takes too long to fix.
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 10));
      } on TimeoutException {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) {
        _errorMessage = 'Could not get location. Using default.';
        _isLoading = false;
        notifyListeners();
        return;
      }
      // success - update location and clear loading/error states.
      _currentLocation = LatLng(position.latitude, position.longitude);
      _isLoading = false;
      _errorMessage = "";
      notifyListeners();
    } catch (e) {
      // handle any errors during location retrival
      _errorMessage =
          "Error getting location ${e.toString()}. Use default location.";
      _isLoading = false;
      notifyListeners();
    }
  }

  // public method to manually refresh location (can be calleded by UI)
  void refreshLocation() {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();
    _getCurrentLocation();
  }
}
