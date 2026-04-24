Future<bool> ensureGoogleMapsLoaded({required String apiKey}) async {
  // Non-web platforms don't need Google Maps JS.
  return true;
}
