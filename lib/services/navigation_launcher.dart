import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class NavigationLauncher {
  static Future<void> openGoogleMapsNavigation({
    required LatLng destination,
  }) async {
    final lat = destination.latitude;
    final lng = destination.longitude;

    // Prefer the Google Maps app turn-by-turn navigation when available.
    // https://developers.google.com/maps/documentation/urls/android-intents
    final navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');

    try {
      final launched = await launchUrl(
        navUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;
    } catch (_) {
      // Fall back below.
    }

    // Fallback: open navigation in browser (or Maps app if it can handle the URL).
    final webUri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '$lat,$lng',
      'travelmode': 'driving',
      'dir_action': 'navigate',
    });

    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }
}
