// Which deliveries the Done tab is holding.
//
// The tab is the day's run: it fills up as the driver works and starts empty
// again after midnight. Everything that decides which side of midnight an
// order falls on lives in delivery_day.dart, so it is what is pinned here —
// above all the two cases that are easy to get backwards, an order delivered
// late last night and an order with no completion time at all.

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/utils/delivery_day.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

OrderModel orderDeliveredAt(DateTime? deliveredAt, {String id = '1'}) {
  return OrderModel(
    id: id,
    customerName: 'Customer',
    customerPhone: '',
    item: 'Order #$id',
    price: 10,
    pickupLocation: const LatLng(0, 0),
    deliveryLocation: const LatLng(0, 0),
    pickupAddress: 'Current location',
    deliveryAddress: 'Delivery address',
    deliveredAt: deliveredAt,
  );
}

void main() {
  group('isDeliveredToday', () {
    test('counts a delivery made earlier today', () {
      final order = orderDeliveredAt(
        DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(isDeliveredToday(order), isTrue);
    });

    // The whole point: the tab empties at midnight rather than growing
    // forever, so yesterday evening's run is no longer on it this morning.
    test('drops a delivery made yesterday', () {
      final yesterdayEvening = driverToday().subtract(
        const Duration(hours: 1),
      );
      expect(isDeliveredToday(orderDeliveredAt(yesterdayEvening)), isFalse);
    });

    test('counts a delivery made just after midnight', () {
      final justAfterMidnight = driverToday().add(const Duration(minutes: 1));
      expect(isDeliveredToday(orderDeliveredAt(justAfterMidnight)), isTrue);
    });

    // delivered_at reaches the app as an instant in UTC. Read without being
    // converted to the driver's clock, a delivery made at 2am in Beirut dates
    // to the previous day and never appears on the tab that is supposed to be
    // showing this morning's work.
    test('reads the day on the driver clock, not UTC', () {
      final now = DateTime.now();
      final order = orderDeliveredAt(now.toUtc());
      expect(deliveryDayOf(order), driverToday());
      expect(isDeliveredToday(order), isTrue);
    });

    // Orders from a backend predating the delivered_at column. They belong to
    // no day, so they are not today's work — an order completed on this phone
    // is stamped as it is marked delivered and never lands here.
    test('leaves out an order with no completion time', () {
      expect(deliveryDayOf(orderDeliveredAt(null)), isNull);
      expect(isDeliveredToday(orderDeliveredAt(null)), isFalse);
    });
  });

  group('copyWith', () {
    test('stamps a completion time on an order that had none', () {
      final at = DateTime.now();
      final delivered = orderDeliveredAt(null).copyWith(
        isPaid: true,
        deliveredAt: at,
      );
      expect(delivered.deliveredAt, at);
      expect(isDeliveredToday(delivered), isTrue);
    });

    test('keeps the completion time it already had', () {
      final at = DateTime.now().subtract(const Duration(days: 3));
      final order = orderDeliveredAt(at).copyWith(driverNote: 'left at door');
      expect(order.deliveredAt, at);
    });
  });
}
