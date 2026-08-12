// Putting the deliveries that are under way at the top of the driver's list.
//
// The promise these lock down is the one a driver on a batch run assumes: the
// orders they have set off with are the first ones they see, on the home screen
// and in the Orders tab, and nothing else about the list changes underneath
// them because of it.

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/utils/order_sort.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

OrderModel _order(String id) => OrderModel(
      id: id,
      customerName: 'Customer $id',
      customerPhone: '70218542',
      item: 'Item',
      price: 10,
      pickupLocation: const LatLng(0, 0),
      deliveryLocation: const LatLng(0, 0),
      pickupAddress: 'Current location',
      deliveryAddress: 'Beirut',
    );

List<String> _ids(List<OrderModel> orders) =>
    orders.map((o) => o.id).toList();

void main() {
  group('sortActiveFirst', () {
    test('lifts a started delivery above the orders still waiting', () {
      final orders = [_order('a'), _order('b'), _order('c')];

      final sorted = sortActiveFirst(
        orders,
        isActive: (o) => o.id == 'c',
      );

      expect(_ids(sorted), ['c', 'a', 'b']);
    });

    // A driver loading three orders starts each as they pick it up, and expects
    // to find all three at the top rather than one of them.
    test('keeps every started delivery ahead of the rest', () {
      final orders = [_order('a'), _order('b'), _order('c'), _order('d')];

      final sorted = sortActiveFirst(
        orders,
        isActive: (o) => o.id == 'b' || o.id == 'd',
      );

      expect(_ids(sorted), ['b', 'd', 'a', 'c']);
    });

    test('leaves orders on the same side of the split where they were', () {
      final orders = [_order('a'), _order('b'), _order('c')];

      final sorted = sortActiveFirst(orders, isActive: (_) => false);

      expect(_ids(sorted), ['a', 'b', 'c']);
    });

    test('changes nothing when every order is under way', () {
      final orders = [_order('a'), _order('b')];

      final sorted = sortActiveFirst(orders, isActive: (_) => true);

      expect(_ids(sorted), ['a', 'b']);
    });

    // The provider hands this list out and rebuilds its own from the backend's
    // answer; reordering the stored list in place would be a second source of
    // truth about what order the orders are in.
    test('does not reorder the list it was given', () {
      final orders = [_order('a'), _order('b')];

      sortActiveFirst(orders, isActive: (o) => o.id == 'b');

      expect(_ids(orders), ['a', 'b']);
    });

    test('handles an empty list', () {
      expect(sortActiveFirst(<OrderModel>[], isActive: (_) => true), isEmpty);
    });
  });
}
