// Ordering the driver's assigned orders so the run they are actually on comes
// first.
//
// A driver on a batch run starts several orders as they load them, and each one
// stays under way until it is delivered or returned. The list they are shown,
// though, arrives in the backend's order — roughly when each order was assigned
// — so the three orders in the driver's hands could sit anywhere in it, below a
// dozen they have not set off with yet. On the home screen that is worse than
// on a list: the cards there are swiped one at a time, so an active delivery
// eight cards down is eight swipes away from the address the driver needs while
// they are already driving to it.
//
// So the orders being delivered are lifted to the top, which is also what the
// green "Active" badge on each card already says about them — the sort just
// makes the list agree with the badge.
//
// Everything else keeps the order it came in. This is a partition rather than a
// sort by a key: only the active/not-active split is decided here, and orders
// on the same side of it are left exactly as the backend sent them, so nothing
// shuffles under a driver mid-scroll for a reason they cannot see.

import 'package:delivery_boy_app/models/order_model.dart';

/// Returns [orders] with the ones [isActive] accepts moved to the front.
///
/// Stable on both sides of the split: two active orders stay in the order they
/// were already in, and so do two inactive ones. Dart's `List.sort` gives no
/// such promise, which is why this builds the two groups by hand instead.
///
/// The input list is not modified — the provider hands out its assigned-order
/// list from this, and that list is rebuilt by the poll rather than reordered.
List<OrderModel> sortActiveFirst(
  List<OrderModel> orders, {
  required bool Function(OrderModel order) isActive,
}) {
  final active = <OrderModel>[];
  final rest = <OrderModel>[];

  for (final order in orders) {
    if (isActive(order)) {
      active.add(order);
    } else {
      rest.add(order);
    }
  }

  return [...active, ...rest];
}
