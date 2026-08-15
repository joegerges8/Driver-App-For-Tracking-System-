// address.dart
//
// One answer to "how should this order's address read on a card".
//
// The backend keeps the written address and the town in two columns, because
// the town is what the delivery area is derived from (see areaLookup on the
// backend, and the area filter chips on the orders screen). Joining the two
// for display is a separate question, and the naive join repeats itself often
// enough to be worth a rule:
//
//   address1 'Fraikeh' + address2 'Friekeh valley residence, house nb 4'
//   with city 'Fraikeh'  ->  'Fraikeh, Friekeh valley residence, house nb 4,
//                             Fraikeh'
//
// The repetition is not a data error. A Shopify checkout asks for the address
// and the city in separate fields, and a customer who has already written the
// town into the address line writes it again into the field that demands it.
// So the town reaching us twice is the normal case, not the broken one, and
// the display is where it has to be reconciled.
//
// The town is not always the whole of the first field either. Customers who
// write their address as one run of slash-separated parts —
// 'Beirut/ Ras Nab3/ Muhammad Hout Street/ Olive Garden Building' — leave the
// town as the first part of a longer string, so an equality test against the
// address would miss it. Hence the comparison below is per segment, splitting
// on the separators customers actually type between the parts of an address.
//
// Two things this deliberately does not do. It never drops the town when the
// address does not name it, since a street with no town is not an address a
// driver can find; and it never edits the address itself, so whatever the
// customer wrote reaches the driver as they wrote it.

// The separators customers put between the parts of an address. Commas are
// the ones Shopify itself inserts between address1 and address2; slashes are
// what a Lebanese address is often written with end to end.
final RegExp _segmentSeparator = RegExp(r'[,/]');

// Everything that is not a letter or a digit. Two pieces of text are compared
// by their words alone, so 'Ashkout' matches ' ashkout,' and 'Ras Nab3' keeps
// its digit rather than being reduced to 'ras nab'.
final RegExp _nonAlphanumeric = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Reduces text to the part worth comparing: lowercase words, single-spaced.
///
/// Returns an empty string for text carrying nothing to match on — a stray
/// comma, a run of spaces — which the caller reads as "nothing to compare"
/// rather than as a match against another empty segment.
String _comparable(String value) =>
    value.toLowerCase().replaceAll(_nonAlphanumeric, ' ').trim();

/// The delivery address as a driver should read it.
///
/// [shippingAddress] is the written address the backend stores (Shopify's
/// address1 and address2 already joined), [city] the town it stores alongside.
/// The town is appended unless the address already names it — as its own line,
/// as in 'Ashkout, House No. 280 Street No.7', or as one segment among several,
/// as in 'Beirut/ Ras Nab3/ Muhammad Hout Street'.
///
/// Either part may be empty; the other is then the whole answer, and two empty
/// parts give an empty string for the caller to substitute a placeholder for.
String buildDeliveryAddress(String shippingAddress, String city) {
  final address = shippingAddress.trim();
  final town = city.trim();

  if (town.isEmpty) return address;
  if (address.isEmpty) return town;

  final townKey = _comparable(town);
  // A town written entirely in punctuation names nowhere; appending it would
  // only put a comma and a stray mark on the end of a good address.
  if (townKey.isEmpty) return address;

  final alreadyNamed = address
      .split(_segmentSeparator)
      .map(_comparable)
      .any((segment) => segment == townKey);

  return alreadyNamed ? address : '$address, $town';
}
