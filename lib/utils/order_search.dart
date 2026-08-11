// Finding one order by its number, the way a driver asks for it.
//
// A driver holding a phone at someone's gate knows an order as the number
// printed on the label — "2693" — and that is the same number the customer or
// the dispatcher reads out over the phone. Shopify writes it as "#2693", so the
// '#' is dropped on both sides of the comparison instead of being demanded from
// someone typing one-handed. Spaces and letter case go the same way: they are
// how the number was written down, not part of which order it is.
//
// The matching lives here rather than inside the orders screen so it can be
// tested on its own, and so the screen is left holding only the text field.

/// Reduces typed text to the part worth comparing: no '#', no whitespace, all
/// lowercase.
///
/// Returns an empty string for text that carries nothing to match on — '#' or
/// a few spaces on their own — which callers read as "no search is active"
/// rather than as a search that happens to match nothing.
String normalizeOrderQuery(String raw) =>
    raw.replaceAll(RegExp(r'[\s#]'), '').toLowerCase();

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
