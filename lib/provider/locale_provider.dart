import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Holds the language the driver picked (English or Arabic) and persists it in
// SharedPreferences, so the choice survives an app restart and a re-login.
//
// The locale starts as null, which makes MaterialApp follow the phone's own
// language setting — a driver whose phone is already in Arabic gets Arabic on
// first launch without touching the toggle. Once they flip the toggle their
// explicit choice is stored and wins over the device setting from then on.
class LocaleProvider extends ChangeNotifier {
  static const _localeKey = 'driver_locale';

  static const Locale englishLocale = Locale('en');
  static const Locale arabicLocale = Locale('ar');

  Locale? _locale;
  bool _loaded = false;

  // null = follow the device language.
  Locale? get locale => _locale;
  bool get loaded => _loaded;

  // What the UI is actually rendering right now — MaterialApp has already
  // resolved `locale` (or the device language when it is null) against the
  // supported list, so the toggle highlights the correct side even before the
  // driver has made an explicit choice.
  Locale effectiveLocale(BuildContext context) =>
      _locale ?? Localizations.localeOf(context);

  bool isArabic(BuildContext context) =>
      effectiveLocale(context).languageCode == 'ar';

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    if (code != null &&
        AppLocalizations.supportedLocales
            .any((l) => l.languageCode == code)) {
      _locale = Locale(code);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale?.languageCode == locale.languageCode) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
  }

  // Flips between the two languages — used by the switch on the profile screen
  // and the compact language button on the login screen.
  Future<void> toggle(BuildContext context) =>
      setLocale(isArabic(context) ? englishLocale : arabicLocale);
}
