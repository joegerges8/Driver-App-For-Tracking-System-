// The pins the driver sees on the home screen map.
//
// What these lock down is what the map is allowed to say. A green pin is a stop
// the driver no longer has to make and a red one is a stop they do; a town with
// four orders in it has to show four pins and not one; and nothing may appear
// on the map for an order the backend could not place.

import 'dart:math' as math;

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/utils/order_pins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const LatLng _jounieh = LatLng(33.9808, 35.6178);
const LatLng _zahle = LatLng(33.8463, 35.9019);

OrderModel _order(
  String id, {
  LatLng? city = _jounieh,
}) =>
    OrderModel(
      id: id,
      customerName: 'Customer $id',
      customerPhone: '70218542',
      item: 'Order #$id',
      price: 10,
      pickupLocation: const LatLng(0, 0),
      // The exact pin the order carries, if any. The map deliberately ignores
      // this in favour of the town centre — see the tests below.
      deliveryLocation: const LatLng(34.5, 36.5),
      cityLocation: city,
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

// Rough metres between two points — enough to assert that fanned-out pins are
// close to their town and not on top of each other.
double _metresBetween(LatLng a, LatLng b) {
  const metresPerDegree = 111320.0;
  final dLat = (a.latitude - b.latitude) * metresPerDegree;
  final dLng = (a.longitude - b.longitude) *
      metresPerDegree *
      math.cos(a.latitude * math.pi / 180);
  return math.sqrt(dLat * dLat + dLng * dLng);
}

void main() {
  group('buildOrderMarkers', () {
    test('pins an undelivered order red and a delivered one green', () {
      final markers = buildOrderMarkers(
        pending: [_order('1')],
        delivered: [_order('2', city: _zahle)],
      );

      expect(markers.length, 2);
      expect(_hueOf(_pinFor(markers, '1')), BitmapDescriptor.hueRed);
      expect(_hueOf(_pinFor(markers, '2')), BitmapDescriptor.hueGreen);
    });

    test('pins the town centre, not the exact address on the order', () {
      // _order carries a deliveryLocation far away in the Bekaa. The map is a
      // picture of which towns the run covers, so the town centre is what it
      // shows — the doorstep stays on the card.
      final markers = buildOrderMarkers(
        pending: [_order('1')],
        delivered: const [],
      );

      expect(_pinFor(markers, '1').position, _jounieh);
    });

    test('skips an order the backend could not place', () {
      final markers = buildOrderMarkers(
        pending: [_order('1', city: null)],
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

    test('labels a pin by order number and address', () {
      final markers = buildOrderMarkers(
        pending: [_order('7')],
        delivered: const [],
      );

      final pin = _pinFor(markers, '7');
      expect(pin.infoWindow.title, 'Order #7');
      expect(pin.infoWindow.snippet, 'Hamra Street');
    });

    test('leaves the driver a map with no pins when nothing is assigned', () {
      expect(
        buildOrderMarkers(pending: const [], delivered: const []),
        isEmpty,
      );
    });
  });

  group('orders sharing a town', () {
    test('each keeps its own pin instead of stacking into one', () {
      final markers = buildOrderMarkers(
        pending: [_order('1'), _order('2'), _order('3'), _order('4')],
        delivered: const [],
      );

      expect(markers.length, 4);

      final positions = markers.map((m) => m.position).toSet();
      expect(positions.length, 4, reason: 'no two pins may share a point');
    });

    test('sits far enough apart to tap and close enough to read as one town',
        () {
      final markers = buildOrderMarkers(
        pending: [_order('1'), _order('2'), _order('3')],
        delivered: const [],
      );

      for (final marker in markers) {
        final fromCentre = _metresBetween(marker.position, _jounieh);
        expect(fromCentre, greaterThan(20));
        expect(fromCentre, lessThan(300));
      }

      final list = markers.toList();
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          expect(
            _metresBetween(list[i].position, list[j].position),
            greaterThan(30),
            reason: 'pins must not overlap on screen',
          );
        }
      }
    });

    test('groups two spellings of one town by the point, not the text', () {
      // The backend collapses "zahle" and "Zahlé" onto the same centre. If the
      // grouping went by city text they would fan out independently and land
      // back on top of each other.
      final markers = buildOrderMarkers(
        pending: [_order('1', city: _zahle), _order('2', city: _zahle)],
        delivered: const [],
      );

      expect(markers.map((m) => m.position).toSet().length, 2);
    });

    test('keeps a town of one order exactly on the town centre', () {
      final markers = buildOrderMarkers(
        pending: [_order('1'), _order('2', city: _zahle)],
        delivered: const [],
      );

      expect(_pinFor(markers, '1').position, _jounieh);
      expect(_pinFor(markers, '2').position, _zahle);
    });

    test('gives a pin the same spot when the list comes back reordered', () {
      // The order list is rebuilt from the backend on every poll and arrives in
      // whatever order the query returned. A pin that moved around the town
      // centre each time would be movement the driver cannot explain.
      final first = buildOrderMarkers(
        pending: [_order('1'), _order('2'), _order('3')],
        delivered: const [],
      );
      final second = buildOrderMarkers(
        pending: [_order('3'), _order('1'), _order('2')],
        delivered: const [],
      );

      for (final id in ['1', '2', '3']) {
        expect(_pinFor(first, id).position, _pinFor(second, id).position);
      }
    });

    test('spreads a town holding more than one ring of orders', () {
      final orders = List.generate(12, (i) => _order('$i'));
      final markers = buildOrderMarkers(pending: orders, delivered: const []);

      expect(markers.length, 12);
      expect(markers.map((m) => m.position).toSet().length, 12);
    });
  });

  group('framing the run', () {
    test('boxes every point the driver has to see', () {
      // Beirut, Jounieh and the driver somewhere between them: the box has to
      // hold all three, with the lower corner south-west of the upper one.
      final bounds = boundsFor(const [
        LatLng(33.8938, 35.5018),
        LatLng(33.9808, 35.6178),
        LatLng(33.9450, 35.5600),
      ])!;

      expect(bounds.southwest, const LatLng(33.8938, 35.5018));
      expect(bounds.northeast, const LatLng(33.9808, 35.6178));
    });

    test('puts the corners the right way round whatever the order in', () {
      // The points arrive in whatever order the lists produced them; a box
      // built with the corners swapped is rejected by Google Maps outright.
      final bounds = boundsFor(const [
        LatLng(34.4367, 35.8497),
        LatLng(33.2705, 35.2038),
      ])!;

      expect(
        bounds.southwest.latitude,
        lessThanOrEqualTo(bounds.northeast.latitude),
      );
      expect(
        bounds.southwest.longitude,
        lessThanOrEqualTo(bounds.northeast.longitude),
      );
    });

    test('has nothing to frame when there is nothing on the map', () {
      expect(boundsFor(const []), isNull);
    });

    test('calls a driver standing among their orders one place', () {
      // Everything inside one town. Fitting a camera to a box this small is a
      // street-level zoom, which is what the framing exists to avoid.
      final single = singlePointOf(const [
        LatLng(33.9808, 35.6178),
        LatLng(33.9814, 35.6183),
      ]);

      expect(single, isNotNull);
      expect(single!.latitude, closeTo(33.9811, 0.001));
    });

    test('calls two towns apart a spread, not one place', () {
      expect(
        singlePointOf(const [
          LatLng(33.8938, 35.5018), // Beirut
          LatLng(33.9808, 35.6178), // Jounieh
        ]),
        isNull,
      );
    });

    test('treats a lone driver with no orders as one place', () {
      expect(singlePointOf(const [LatLng(33.9808, 35.6178)]), isNotNull);
    });

    test('holds the fanned-out pins of one town together as one place', () {
      // Several orders in one town are spread on a ring a few dozen metres
      // across. That must not read as a spread worth zooming out for.
      final markers = buildOrderMarkers(
        pending: [_order('1'), _order('2'), _order('3')],
        delivered: const [],
      );

      expect(singlePointOf(markers.map((m) => m.position)), isNotNull);
    });
  });

  group('hasMappableLocation', () {
    test('rejects an order with no resolved town', () {
      expect(hasMappableLocation(_order('1', city: null)), isFalse);
    });

    test('accepts an order the backend placed', () {
      expect(hasMappableLocation(_order('1')), isTrue);
    });
  });
}
