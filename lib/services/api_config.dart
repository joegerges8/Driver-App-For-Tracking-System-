class ApiConfig {
  // Single place to configure the backend base URL.
  //
  // Recommended: override at build/run time:
  // `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000`
  //
  // Notes:
  // - Android emulator: use http://10.0.2.2:3000
  // - Physical Android phone: use your PC's LAN IP, e.g. http://192.168.1.50:3000
  // - iOS simulator: use http://localhost:3000

    static const String _prodUrl =
      'https://shopify-live-order-tracking-production.up.railway.app';

  static const String _override =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static String get baseUrl {
    final override = _override.trim();
    final value = override.isNotEmpty ? override : _prodUrl;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
