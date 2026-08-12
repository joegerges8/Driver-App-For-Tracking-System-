// delivery_day.dart
//
// One answer to "which day did this delivery happen on", shared by everything
// that dates a completed order: the Done tab, which shows today's run and
// empties itself at midnight, and the Shipment screen, which groups the same
// orders into Today / Yesterday / older.
//
// Two details are easy to get wrong separately and must not be answered
// differently in two places:
//
//  * delivered_at arrives from the backend as an instant in UTC, so it has to
//    be converted to the driver's own clock before a calendar day is read off
//    it. Without toLocal() a delivery made at 2am in Beirut dates to the day
//    before, and the tab that is supposed to hold "today's" work would still
//    be holding it the following evening.
//
//  * an order with no delivered_at at all — one from a backend predating the
//    column — belongs to no day. It is not today's work, so it does not sit in
//    the Done tab pretending to be. Orders completed on this phone are stamped
//    the moment the driver taps "Mark as Delivered" (see completeDelivery),
//    so the missing-timestamp case never covers a delivery just made.

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:flutter/material.dart';

/// The calendar day [order] was delivered on, in the driver's own timezone, or
/// null when the order carries no completion time.
DateTime? deliveryDayOf(OrderModel order) {
  final deliveredAt = order.deliveredAt;
  if (deliveredAt == null) return null;
  return DateUtils.dateOnly(deliveredAt.toLocal());
}

/// Today, as the driver's phone reckons it.
DateTime driverToday() => DateUtils.dateOnly(DateTime.now());

/// Whether this delivery is part of today's run. False for an order with no
/// completion time — see the note above.
bool isDeliveredToday(OrderModel order) => deliveryDayOf(order) == driverToday();
