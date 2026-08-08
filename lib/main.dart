import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/provider/current_location_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/locale_provider.dart';
import 'package:delivery_boy_app/screen/auth_gate.dart';
import 'package:delivery_boy_app/services/background_location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundLocationService.initialize();
  final mapsImplementation = GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is GoogleMapsFlutterAndroid) {
    mapsImplementation.useAndroidViewSurface = true;
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_)=> CurrentLocationProvider()),
        ChangeNotifierProvider(create: (_)=> DeliveryProvider()),
        // Added in this change:
        // AuthProvider stores JWT + driver profile and persists token.
        ChangeNotifierProvider(create: (_)=> AuthProvider()),
        // Added in this change:
        // LocaleProvider holds the English/Arabic choice and loads the saved
        // one from SharedPreferences straight away, so the app opens in the
        // language the driver last picked.
        ChangeNotifierProvider(create: (_)=> LocaleProvider()..load()),
      ],
      // Rebuilds the whole app when the driver flips the language toggle.
      // Passing `locale: null` (no saved choice) makes MaterialApp fall back to
      // the device language, resolved against supportedLocales.
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) => MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: localeProvider.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            // The Global* delegates translate Flutter's own widgets and are what
            // set TextDirection.rtl for Arabic, flipping the entire layout.
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Added in this change:
          // AuthGate decides whether to show Login/Signup or the main app.
          home: const AuthGate(),
        ),
      ),
    );
  }
}
