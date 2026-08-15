// The order pins on the home screen map.
//
// The map used to show one thing — where the driver is — which answers "where
// am I" and nothing about the run itself. A driver looking at it could not see
// whether the next drop was around the corner or across town, or which of the
// day's stops were already behind them.
//
// So every order the driver is carrying gets a pin, coloured by whether it is
// done: red for a delivery still owed to a customer, green for one already
// made. Two colours rather than a legend because that is the whole question
// being asked of the map at a glance — what is left.
//
// Two things decide whether an order can be pinned at all:
//
//  * It needs coordinates. OrderModel falls back to (0, 0) for an order whose
//    Shopify record carried neither lat/lng columns nor a parseable maps link
//    (see OrderModel.fromBackend), and that sentinel is a real place in the
//    Gulf of Guinea — pinning it would put a stop 3,000km off the coast of
//    Africa on the driver's map. Those orders are skipped; they still show up
//    on the cards below the map, which is where their address is.
//
//  * An order must produce one pin, not two. The delivered and pending lists
//    are fetched from separate endpoints and an order can briefly appear in
//    both — the moment after a delivery is marked, before the assigned list is
//    re-fetched. Delivered wins there, since that is the newer fact.

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Whether this order can be put on a map at all — see the note above about
/// the (0, 0) sentinel.
bool hasMappableLocation(OrderModel order) {
  final location = order.deliveryLocation;
  return location.latitude.abs() > 0.001 && location.longitude.abs() > 0.001;
}

/// A pin for every order in [pending] and [delivered] that has coordinates.
///
/// [delivered] is taken as the more recent truth: an order in both lists is
/// pinned green once and not red as well.
Set<Marker> buildOrderMarkers({
  required List<OrderModel> pending,
  required List<OrderModel> delivered,
}) {
  // Keyed by order id so the same order cannot be added twice, whichever list
  // it arrives in. Delivered is inserted first and pending skips ids already
  // in here, which is what makes delivered win.
  final byId = <String, Marker>{};

  for (final order in delivered) {
    if (!hasMappableLocation(order)) continue;
    byId[order.id] = _pin(order, BitmapDescriptor.hueGreen);
  }

  for (final order in pending) {
    if (!hasMappableLocation(order)) continue;
    if (byId.containsKey(order.id)) continue;
    byId[order.id] = _pin(order, BitmapDescriptor.hueRed);
  }

  return byId.values.toSet();
}

// The info window carries the order number and the address rather than the
// customer's name: those are what the driver matches against the card they are
// holding, and a name on a map pin says nothing about where the pin is.
Marker _pin(OrderModel order, double hue) {
  return Marker(
    markerId: MarkerId('order_${order.id}'),
    position: order.deliveryLocation,
    infoWindow: InfoWindow(
      title: order.item,
      snippet: order.deliveryAddress,
    ),
    icon: BitmapDescriptor.defaultMarkerWithHue(hue),
  );
}
