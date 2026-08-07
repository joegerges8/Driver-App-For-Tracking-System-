class ApiConfig {

 // stores the base URL of the backend
    static const String _prodUrl =
      'https://dispatcher-dashboard.up.railway.app';

  static const String _override =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static String get baseUrl {
    final override = _override.trim();
    final value = override.isNotEmpty ? override : _prodUrl;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
