// Customer phone numbers, and the two shapes the app needs them in.
//
// The phone column is free-form text typed by a customer into a Shopify
// checkout, so the same line reaches the driver written any number of ways:
// '+961 70 218 542' from one store, '70218542' from the next, sometimes
// '0096170218542' or a local '03 719 871'. Nothing upstream normalises it.
//
// Two jobs come out of that. Matching needs one canonical string per line so a
// search can compare them — normalizePhone. Reading needs the shortest form a
// driver in Lebanon recognises at a glance, with the country code they already
// know taken off — displayPhone. Neither touches what is stored: calling and
// WhatsApp keep using the raw number, which is the one that dials.
//
// Both are pure so they can be unit-tested without pumping a widget. See
// test/phone_test.dart.

// The country code every number here is assumed to carry, matching
// toWhatsAppNumber and the dispatcher dashboard.
const String _lebanonCountryCode = '961';

/// Reduces a phone number — stored or typed — to its national digits.
///
/// Everything that is formatting rather than identity comes off: '+', spaces,
/// dashes and brackets, then the '00' international prefix, then the country
/// code, then the trunk '0' that the local form carries and the international
/// form drops. What is left is the same string whichever way the number was
/// written, which is the whole point — '+961 70 218 542', '0096170218542' and
/// '70218542' all reduce to '70218542'.
///
/// A query holding only a country code ('+961') reduces to nothing, and
/// callers read that as a search the driver has not finished typing rather
/// than as one that matched nothing.
String normalizePhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');

  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith(_lebanonCountryCode)) {
    digits = digits.substring(_lebanonCountryCode.length);
  }

  // Local numbers are written with a trunk zero ('03 123 456') that the
  // international form leaves out, so it cannot be part of what is compared.
  return digits.replaceFirst(RegExp(r'^0+'), '');
}

/// The number as it should be read on an order card: no country code.
///
/// A driver delivering in Lebanon knows the +961, so printing it costs a card
/// eight characters of a line that is already competing with the customer's
/// name — and makes two orders look like different kinds of number when they
/// are the same kind, written differently by two stores.
///
/// Only an actual country code is removed. A number that arrived without one
/// is passed through exactly as the store saved it, spacing and all: it is
/// already in the short form, and rewriting someone's '03 719 871' into
/// '03719871' would be tidying for its own sake. When stripping the code
/// leaves a seven-digit national number — '3719871', an 03 mobile or an 01
/// landline — the trunk zero goes back on, since that is how the number is
/// said and dialled at home.
///
/// Anything that leaves nothing behind ('+961' on its own, or a column holding
/// punctuation) is returned untouched rather than blanked, so a number the app
/// does not understand is still shown to the driver instead of disappearing.
String displayPhone(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final digits = trimmed.replaceAll(RegExp(r'\D'), '');

  // No country code to take off — this is already the short form.
  var rest = digits;
  if (rest.startsWith('00')) rest = rest.substring(2);
  if (!rest.startsWith(_lebanonCountryCode)) return trimmed;
  rest = rest.substring(_lebanonCountryCode.length);

  if (rest.isEmpty) return trimmed;

  // '3719871' is how the international form writes an '03 719 871'.
  if (rest.length == 7) return '0$rest';

  return rest;
}
