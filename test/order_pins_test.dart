// The pins the driver sees on the home screen map.
//
// What these lock down is what the two colours are allowed to mean. A green pin
// is a stop the driver no longer has to make, a red one is a stop they do, and
// nothing may appear on the map that is not a real address — a pin in the wrong
// colour or the wrong ocean sends a driver somewhere.

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/utils/order_pins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

OrderModel _order(
  String id, {
  LatLng location = const LatLng(33.8938, 35.5018), // Beirut
}) =>
    OrderModel(
      id: id,
      customerName: 'Customer $id',
      customerPhone: '70218542',
      item: 'Order #$id',
      price: 10,
      pickupLocation: const LatLng(0, 0),
      deliveryLocation: location,
      pickupAddress: 'Current location',
      deliveryAddress: 'Hamra Street',
    );

Marker _pinFor(Set<Marker> markers, String orderId) =>
    markers.firstWhere((m) => m.markerId == MarkerId('order_$orderId'));

// The colour of a pin, read off the descriptor's serialised form
// (['defaultMarker', hue]) rather than by comparing two BitmapDescriptors:
// those carry no value equality, so two identical red markers are not equal to
// each other and such an assertion would fail whatever the colour.
num _hueOf(Marker marker) => (marker.icon.toJson() as List)[1] as num;

void main() {
  group('buildOrderMarkers', () {
    test('pins an undelivered order red and a delivered one green', () {
      final markers = buildOrderMarkers(
        pending: [_order('1')],
        delivered: [_order('2')],
      );

      expect(markers.length, 2);
      expect(_hueOf(_pinFor(markers, '1')), BitmapDescriptor.hueRed);
      expect(_hueOf(_pinFor(markers, '2')), BitmapDescriptor.hueGreen);
    });

    test('skips an order with no coordinates instead of pinning (0, 0)', () {
      final markers = buildOrderMarkers(
        pending: [_order('1', location: const LatLng(0, 0))],
        delivered: const [],
      );

      expect(markers, isEmpty);
    });

    test('pins an order that is in both lists once, as delivered', () {
      // The window right after a delivery is marked: the completed list already
      // has the order, the assigned list has not been re-fetched yet.
      final markers = buildOrderMarkers(
        pending: [_order('1')],
        delivered: [_order('1')],
      );

      expect(markers.length, 1);
      expect(_hueOf(_pinFor(markers, '1')), BitmapDescriptor.hueGreen);
    });

    test('puts the pin on the delivery address, labelled by order number', () {
      final markers = buildOrderMarkers(
        pending: [_order('7', location: const LatLng(34.1234, 35.6789))],
        delivered: const [],
      );

      final pin = _pinFor(markers, '7');
      expect(pin.position, const LatLng(34.1234, 35.6789));
      expect(pin.infoWindow.title, 'Order #7');
      expect(pin.infoWindow.snippet, 'Hamra Street');
    });

    test('leaves the driver a map with no pins when nothing is assigned', () {
      expect(buildOrderMarkers(pending: const [], delivered: const []),
          isEmpty);
    });
  });

  group('hasMappableLocation', () {
    test('rejects the (0, 0) sentinel a missing address falls back to', () {
      expect(hasMappableLocation(_order('1', location: const LatLng(0, 0))),
          isFalse);
    });

    test('accepts a real coordinate', () {
      expect(hasMappableLocation(_order('1')), isTrue);
    });
  });
}
