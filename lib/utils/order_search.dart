// Finding one order the way a driver asks for it: by the customer's phone
// number, or still by the order number if that is what they have.
//
// The number a driver has in hand at the gate is almost always the customer's
// phone — it is what the customer called from and what the dispatcher reads
// out — so that is what the field searches. The trouble is that the same phone
// reaches this app written several ways: '+96170218542' from one store,
// '70218542' from another, sometimes '0096170218542' or a local '03 123 456'.
// A driver cannot be asked to remember which order was saved in which shape,
// so both the stored number and the typed one are reduced to the part that
// actually identifies the line — the national number, with the country code,
// the international prefix and the leading zero taken off — before they are
// compared. Typing 70218542 then finds +96170218542, and typing the whole
// +96170218542 finds a bare 70218542.
//
// Order-number lookup is kept alongside it. It costs nothing — order numbers
// and phone numbers are different lengths and never collide in practice — and
// a driver reading a number off a label should not have to know which of the
// two kinds of number the field wants.
//
// The matching lives here rather than inside the orders screen so it can be
// tested on its own, and so the screen is left holding only the text field.
// How a phone number is reduced to the part that identifies it lives one file
// over, in utils/phone.dart, since the order cards need the same rules to
// print a number as the search needs to compare one.

import 'package:delivery_boy_app/utils/phone.dart';

// Callers of the search should not have to know that the phone rules live
// elsewhere; normalizePhone reads as part of this API.
export 'package:delivery_boy_app/utils/phone.dart' show normalizePhone;

/// Reduces typed text to the part worth comparing: no '#', no whitespace, all
/// lowercase.
///
/// Returns an empty string for text that carries nothing to match on — '#' or
/// a few spaces on their own — which callers read as "no search is active"
/// rather than as a search that happens to match nothing.
String normalizeOrderQuery(String raw) =>
    raw.replaceAll(RegExp(r'[\s#]'), '').toLowerCase();

/// Whether [phone] is the number the driver meant by [query].
///
/// Both sides are reduced to their national digits first, so the country code
/// never has to be typed — nor avoided by a driver whose order happens to be
/// stored with one. Matching is on any part of the number so it narrows as the
/// driver types, and so the last few digits, which is how a number is usually
/// half-remembered, are enough.
bool phoneMatches(String phone, String query) {
  final needle = normalizePhone(query);
  if (needle.isEmpty) return false;

  final haystack = normalizePhone(phone);
  if (haystack.isEmpty) return false;

  return haystack.contains(needle);
}

/// Whether the order numbered [orderNumber] is one the driver meant by [query].
///
/// [query] is normalised here too, so callers may pass raw text straight from
/// the field. Matching is on any part of the number, not just its start: a
/// driver who half-remembers an order as "ending in 93" still finds it, and
/// typing the full number narrows to it anyway. Order numbers that carry a
/// store prefix ('EN2693') are found by their digits alone for the same reason.
///
/// An order with no number at all — one the backend sent with neither an
/// order_number nor a shopify_order_id — can never match, since there is
/// nothing the driver could have typed to mean it.
bool orderNumberMatches(String orderNumber, String query) {
  final needle = normalizeOrderQuery(query);
  if (needle.isEmpty) return false;

  final haystack = normalizeOrderQuery(orderNumber);
  if (haystack.isEmpty) return false;

  return haystack.contains(needle);
}

/// Whether an order with this [phone] and [orderNumber] answers [query].
///
/// The field is one box and the driver types one number into it, so which of
/// the two it turns out to be is the app's problem, not theirs.
bool orderMatchesSearch({
  required String phone,
  required String orderNumber,
  required String query,
}) =>
    phoneMatches(phone, query) || orderNumberMatches(orderNumber, query);

/// Whether [raw] is enough for the screen to start narrowing the list.
///
/// A field holding only decoration — '#', spaces, or a country code the driver
/// has typed the first half of — is not a search yet, and the list stays whole
/// rather than emptying out under someone mid-way through a number.
bool isSearchActive(String raw) => normalizePhone(raw).isNotEmpty;
