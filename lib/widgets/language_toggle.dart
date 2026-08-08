import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/provider/locale_provider.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Two-option segmented switch: English | العربية.
// Tapping a side calls LocaleProvider.setLocale, which persists the choice and
// rebuilds MaterialApp — the whole app re-renders in the new language and, for
// Arabic, flips to a right-to-left layout.
//
// Both labels are always written in their own language (never translated) so a
// driver who lands in the wrong language can still recognise the way back.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final isArabic = localeProvider.isArabic(context);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            label: 'English',
            selected: !isArabic,
            onTap: () =>
                localeProvider.setLocale(LocaleProvider.englishLocale),
          ),
          _segment(
            label: 'العربية',
            selected: isArabic,
            onTap: () => localeProvider.setLocale(LocaleProvider.arabicLocale),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? buttonMainColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

// Compact version for the login and signup screens, which have no settings
// area. Shows the language the driver would switch *to*, so one tap flips the
// screen before they have an account to store a preference against.
class LanguageSwitchButton extends StatelessWidget {
  const LanguageSwitchButton({super.key, this.color = Colors.white});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final l10n = context.l10n;
    final otherLanguage = localeProvider.isArabic(context)
        ? l10n.english
        : l10n.arabic;

    return TextButton.icon(
      onPressed: () => localeProvider.toggle(context),
      icon: Icon(Icons.language, size: 18, color: color),
      label: Text(
        otherLanguage,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
