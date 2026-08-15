// The order pins on the home screen map.
//
// The map used to show one thing — where the driver is — which answers "where
// am I" and nothing about the run itself. A driver looking at it could not see
// how much was left or where it was going.
//
// So every order the driver is carrying gets a pin, coloured by whether it is
// done: red for a delivery still owed to a customer, green for one already
// made. Two colours rather than a legend because that is the whole question
// being asked of the map at a glance — what is left, and where.
//
// ── Why the pin is the town and not the doorstep ────────────────────────────
//
// It would be nicer to pin the exact address, and the app cannot: the customer
// coordinate columns are empty for nearly every order, because customers type
// an address at checkout and are never asked to drop a pin. Pinning only the
// orders that happen to carry one would leave a driver holding a dozen orders
// looking at a map with one pin on it.
//
// So the pin is the centre of the town, which the backend resolves from the
// city the customer typed (city_latitude / city_longitude — see the driver
// order endpoints and townCoords.js). That is deliberately approximate and is
// the right kind of approximate: the map is answering "how many orders, in
// which towns", not "which building". The exact address stays on the card and
// on the order detail screen, which is what the driver actually navigates by.
//
// ── Why two orders in one town do not become one pin ────────────────────────
//
// Every order in a town resolves to the identical coordinate, so pins would
// land exactly on top of each other and four orders in Jounieh would look like
// one. Google Maps draws the last one and swallows the rest — including their
// taps, so the driver could not even find the others.
//
// They are spread around the town centre instead, on a ring a few dozen metres
// across. Close enough that the cluster still reads as one town, far enough
// apart to be seen and tapped separately, and the count — which is the thing
// the driver is reading off the map — is right.

import 'dart:math' as math;

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// How far from the town centre the fanned-out pins sit, in metres.
///
/// Small enough that the ring still reads as one town at the zoom a driver
/// looks at a town from, and large enough that the pins do not touch: a map
/// marker is about 40px tall, which is roughly 25m at zoom 15.
const double _ringRadiusMetres = 70;

/// How many pins fit on one ring before another is started outside it. Beyond
/// about eight the pins on a single ring start to crowd each other.
const int _pinsPerRing = 8;

/// Metres per degree of latitude. Longitude shrinks by cos(latitude), which is
/// applied where it is used — at Lebanon's latitude a degree of longitude is
/// about 83% of a degree of latitude, and ignoring that would make the rings
/// visibly oval.
const double _metresPerDegreeLatitude = 111320;

/// Whether this order can be put on a map at all.
///
/// False for an order whose city text matched no town the backend knows and
/// which carries no area either. Those keep their card below the map — the
/// address is there — but nothing is invented for them on the map.
bool hasMappableLocation(OrderModel order) => order.cityLocation != null;

/// A pin for every order in [pending] and [delivered] that the backend could
/// place, spread around its town centre so orders sharing a town stay
/// separately visible.
///
/// [delivered] is taken as the more recent truth: an order in both lists is
/// pinned green once and not red as well.
Set<Marker> buildOrderMarkers({
  required List<OrderModel> pending,
  required List<OrderModel> delivered,
}) {
  // Keyed by order id so the same order cannot be added twice, whichever list
  // it arrives in. Delivered is collected first and pending skips ids already
  // seen, which is what makes delivered win.
  final hues = <String, double>{};
  final orders = <String, OrderModel>{};

  for (final order in delivered) {
    if (!hasMappableLocation(order)) continue;
    hues[order.id] = BitmapDescriptor.hueGreen;
    orders[order.id] = order;
  }

  for (final order in pending) {
    if (!hasMappableLocation(order)) continue;
    if (hues.containsKey(order.id)) continue;
    hues[order.id] = BitmapDescriptor.hueRed;
    orders[order.id] = order;
  }

  // Grouped by the resolved coordinate rather than by the city text: customers
  // spell one town a dozen ways ("zahle", "Zahlé", "Zahle Madine") and the
  // backend collapses all of them onto the same point. Grouping by the text
  // would leave those spellings in separate groups, each fanning out around
  // the same centre and landing back on top of each other.
  final byTown = <String, List<OrderModel>>{};
  for (final order in orders.values) {
    byTown.putIfAbsent(_townKey(order.cityLocation!), () => []).add(order);
  }

  final markers = <Marker>{};
  for (final town in byTown.values) {
    // Sorted so a pin keeps its place on the ring between refreshes. The lists
    // are rebuilt from the backend every poll and arrive in whatever order the
    // query returned; without this, pins would shuffle around the town centre
    // under a driver who is just watching the map.
    town.sort((a, b) => a.id.compareTo(b.id));

    for (var i = 0; i < town.length; i++) {
      final order = town[i];
      markers.add(_pin(
        order,
        hues[order.id]!,
        _fanOut(order.cityLocation!, i, town.length),
      ));
    }
  }

  return markers;
}

// Groups coordinates that are the same town centre. Rounded to five decimals —
// about a metre — so two orders the backend placed identically always land in
// one group, without floating-point equality being the thing holding it
// together.
String _townKey(LatLng centre) =>
    '${centre.latitude.toStringAsFixed(5)},${centre.longitude.toStringAsFixed(5)}';

/// Where the [index]th of [count] orders in one town sits.
///
/// A town with a single order keeps the centre exactly; the rest are placed
/// evenly around a ring, and a second ring opens outside the first once eight
/// pins are on it.
LatLng _fanOut(LatLng centre, int index, int count) {
  if (count <= 1) return centre;

  final ring = index ~/ _pinsPerRing;
  final radius = _ringRadiusMetres * (ring + 1);

  // Positions on the ring: the last ring is usually partly empty, and dividing
  // by how many actually sit on it keeps them evenly spaced rather than
  // bunched into one arc.
  final onThisRing = math.min(count - ring * _pinsPerRing, _pinsPerRing);
  final angle = 2 * math.pi * (index % _pinsPerRing) / onThisRing;

  final latitudeOffset = radius * math.cos(angle) / _metresPerDegreeLatitude;

  // A degree of longitude covers less ground the further from the equator, so
  // without the cos() the ring would be stretched east-west.
  final metresPerDegreeLongitude =
      _metresPerDegreeLatitude * math.cos(centre.latitude * math.pi / 180);
  final longitudeOffset = radius * math.sin(angle) / metresPerDegreeLongitude;

  return LatLng(
    centre.latitude + latitudeOffset,
    centre.longitude + longitudeOffset,
  );
}

// The info window carries the order number and the address rather than the
// customer's name: those are what the driver matches against the card they are
// holding, and a name on a map pin says nothing about where the pin is.
Marker _pin(OrderModel order, double hue, LatLng position) {
  return Marker(
    markerId: MarkerId('order_${order.id}'),
    position: position,
    infoWindow: InfoWindow(
      title: order.item,
      snippet: order.deliveryAddress,
    ),
    icon: BitmapDescriptor.defaultMarkerWithHue(hue),
  );
}
