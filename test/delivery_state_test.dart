// Tests for the two things that went wrong with a delivery already under way:
// it silently reverted to pending, and a newly assigned order stopped arriving.
//
// Both are DeliveryProvider's doing, and both only show up across a refresh —
// which is why these drive the provider through real fetches rather than
// checking any one method in isolation. The order list and the background
// tracker are the two things the provider talks to, and both are handed in.

import 'dart:async';

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// One order as the backend sends it. Only the fields the provider reads.
Map<String, dynamic> backendOrder(
  String id, {
  String status = 'ASSIGNED',
  String number = '',
}) {
  return {
    'id': id,
    'order_number': number.isEmpty ? '#$id' : number,
    'order_status': status,
    'customer_first_name': 'Customer',
    'customer_last_name': id,
    'customer_phone': '03000000',
    'shipping_address': 'Somewhere $id',
    'total_price': '10.00',
    'line_items': const [],
  };
}

// Stands in for the background location service. Records what the provider
// asked it to do, so the tests can assert on the GPS side of each decision.
class FakeTracker implements DeliveryTracker {
  FakeTracker({List<String>? restored}) : restoredIds = restored ?? [];

  final List<String> restoredIds;
  final List<String> started = [];
  final List<String> stopped = [];
  List<String> published = [];

  @override
  Future<void> startTracking(String orderId) async => started.add(orderId);

  @override
  Future<void> stopTrackingOrder(String orderId) async => stopped.add(orderId);

  @override
  Future<void> publishBackendOrders({
    required Iterable<String> openOrderIds,
  }) async {
    published = openOrderIds.toList();
  }

  @override
  Future<List<String>> activeOrderIds() async => restoredIds;
}

// A fetcher the test drives: it answers with whatever rows are set on it, and
// records the carried ids the provider asked about.
class FakeBackend {
  List<Map<String, dynamic>> rows = [];
  List<List<String>> carriedAsked = [];
  int calls = 0;
  Object? failWith;
  // Completes only when the test says so — used for the stalled-request case.
  Completer<void>? hangUntil;

  Future<List<dynamic>> fetch({
    required String token,
    Iterable<String> carrying = const [],
  }) async {
    calls++;
    carriedAsked.add(carrying.toList()..sort());
    if (hangUntil != null) await hangUntil!.future;
    if (failWith != null) throw failWith!;
    return rows;
  }
}

// Opens an order and starts delivering it, the way the detail screen does.
void startDelivering(DeliveryProvider provider, OrderModel order) {
  provider.setCurrentOrder(order);
  provider.startDelivery(driverLocation: const LatLng(33.9, 35.5));
}

OrderModel orderFrom(Map<String, dynamic> row) => OrderModel.fromBackend(row);

void main() {
  group('a delivery already under way', () {
    test(
      'two orders started together both stay active when the backend list '
      'leaves them out',
      () async {
        // The reported case: both orders were returned earlier, so the backend
        // does not list either as awaiting action. Before the fix, whichever
        // one was open on screen was dropped back to pending on the next
        // refresh while the other stayed active.
        final backend = FakeBackend();
        final tracker = FakeTracker();
        final provider = DeliveryProvider(
          fetchOrders: backend.fetch,
          tracker: tracker,
        );

        final first = orderFrom(backendOrder('1', status: 'RETURNED'));
        final second = orderFrom(backendOrder('2', status: 'RETURNED'));

        startDelivering(provider, first);
        startDelivering(provider, second);
        expect(provider.activeOrderIds, {'1', '2'});

        // The backend answers about the carried ids, and says both are still
        // this driver's — RETURNED, because that is what they were left at.
        backend.rows = [
          backendOrder('1', status: 'RETURNED'),
          backendOrder('2', status: 'RETURNED'),
        ];

        await provider.refreshMyOrders(token: 't');

        expect(
          provider.activeOrderIds,
          {'1', '2'},
          reason: 'both deliveries were started and neither was finished',
        );
        expect(provider.isDelivering('1'), isTrue);
        expect(provider.isDelivering('2'), isTrue);
        expect(
          provider.orders.map((o) => o.id).toSet(),
          {'1', '2'},
          reason: 'a delivery under way belongs on the list the driver sees',
        );
        expect(
          tracker.stopped,
          isEmpty,
          reason: 'neither customer\'s map should have gone dark',
        );
        expect(tracker.published.toSet(), containsAll({'1', '2'}));
      },
    );

    test('the backend is asked about every carried order by id', () async {
      final backend = FakeBackend();
      final provider = DeliveryProvider(
        fetchOrders: backend.fetch,
        tracker: FakeTracker(),
      );

      startDelivering(provider, orderFrom(backendOrder('7')));
      startDelivering(provider, orderFrom(backendOrder('8')));

      backend.rows = [backendOrder('7'), backendOrder('8')];
      await provider.refreshMyOrders(token: 't');

      expect(backend.carriedAsked.last, ['7', '8']);
    });

    test('survives the app being backgrounded and brought back', () async {
      // Nothing is destroyed on resume, but a refresh runs — repeatedly. The
      // bug showed up on the second one, so run several.
      final backend = FakeBackend();
      final tracker = FakeTracker();
      final provider = DeliveryProvider(
        fetchOrders: backend.fetch,
        tracker: tracker,
      );

      startDelivering(provider, orderFrom(backendOrder('1', status: 'RETURNED')));
      startDelivering(provider, orderFrom(backendOrder('2', status: 'RETURNED')));

      backend.rows = [
        backendOrder('1', status: 'RETURNED'),
        backendOrder('2', status: 'RETURNED'),
      ];

      for (var i = 0; i < 3; i++) {
        await provider.refreshMyOrders(token: 't', silent: true);
        expect(provider.activeOrderIds, {'1', '2'}, reason: 'refresh ${i + 1}');
      }
    });

    test('is restored after the app is killed mid-run', () async {
      final backend = FakeBackend();
      // What the location service kept on disk while the UI was gone.
      final tracker = FakeTracker(restored: ['1', '2']);
      final provider = DeliveryProvider(
        fetchOrders: backend.fetch,
        tracker: tracker,
      );

      backend.rows = [
        backendOrder('1', status: 'RETURNED'),
        backendOrder('2', status: 'RETURNED'),
      ];

      await provider.refreshMyOrders(token: 't');

      expect(provider.activeOrderIds, {'1', '2'});
      expect(backend.carriedAsked.last, ['1', '2']);
    });

    test('a failed refresh keeps both deliveries on screen', () async {
      final backend = FakeBackend();
      final provider = DeliveryProvider(
        fetchOrders: backend.fetch,
        tracker: FakeTracker(),
      );

      startDelivering(provider, orderFrom(backendOrder('1')));
      startDelivering(provider, orderFrom(backendOrder('2')));

      backend.failWith = Exception('offline');
      await provider.refreshMyOrders(token: 't');

      expect(provider.activeOrderIds, {'1', '2'});
      expect(provider.orders.map((o) => o.id).toSet(), {'1', '2'});
    });

    test('starting a returned order again takes it off the Returned tab',
        () async {
      final backend = FakeBackend();
      final provider = DeliveryProvider(
        fetchOrders: backend.fetch,
        tracker: FakeTracker(),
      );

      final order = orderFrom(backendOrder('1'));
      provider.setCurrentOrder(order);
      provider.completeReturn();
      expect(provider.returnedOrders.map((o) => o.id), ['1']);

      startDelivering(provider, order);

      expect(
        provider.returnedOrders,
        isEmpty,
        reason: 'it is out for delivery again, not sitting returned',
      );
      expect(provider.orders.map((o) => o.id), contains('1'));

      // And it must not be filtered back out by the next refresh.
      backend.rows = [backendOrder('1', status: 'RETURNED')];
      await provider.refreshMyOrders(token: 't');

      expect(provider.isDelivering('1'), isTrue);
      expect(provider.orders.map((o) => o.id), contains('1'));
    });
  });

  group('letting a delivery go', () {
    test('an order the backend no longer has is dropped and its GPS stopped',
        () async {
      // The dispatcher deleted it, or handed it to another driver. The backend
      // was asked about it by id and did not answer for it.
      final backend = FakeBackend();
      final tracker = FakeTracker();
      final provider = DeliveryProvider(
        fetchOrders: backend.fetch,
        tracker: tracker,
      );

      startDelivering(provider, orderFrom(backendOrder('1')));
      startDelivering(provider, orderFrom(backendOrder('2')));

      backend.rows = [backendOrder('1')]; // 2 is gone
      await provider.refreshMyOrders(token: 't');

      expect(provider.activeOrderIds, {'1'});
      expect(provider.orders.map((o) => o.id), ['1']);
      expect(tracker.stopped, contains('2'));
      expect(tracker.published, isNot(contains('2')));
    });

    test('an order delivered elsewhere is let go', () async {
      final backend = FakeBackend();
      final tracker = FakeTracker();
      final provider = DeliveryProvider(
        fetchOrders: backend.fetch,
        tracker: tracker,
      );

      startDelivering(provider, orderFrom(backendOrder('1')));

      backend.rows = [backendOrder('1', status: 'DELIVERED')];
      await provider.refreshMyOrders(token: 't');

      expect(provider.isDelivering('1'), isFalse);
      expect(tracker.stopped, contains('1'));
    });

    test('a cancelled order is let go', () async {
      final backend = FakeBackend();
      final tracker = FakeTracker();
      final provider = DeliveryProvider(
        fetchOrders: backend.fetch,
        tracker: tracker,
      );

      startDelivering(provider, orderFrom(backendOrder('1')));

      backend.rows = [backendOrder('1', status: 'CANCELLED')];
      await provider.refreshMyOrders(token: 't');

      expect(provider.isDelivering('1'), isFalse);
      expect(tracker.stopped, contains('1'));
    });

    test('a terminal order the driver is not carrying stays off the list',
        () async {
      final backend = FakeBackend();
      final provider = DeliveryProvider(
        fetchOrders: backend.fetch,
        tracker: FakeTracker(),
      );

      backend.rows = [
        backendOrder('1'),
        backendOrder('2', status: 'DELIVERED'),
      ];
      await provider.refreshMyOrders(token: 't');

      expect(provider.orders.map((o) => o.id), ['1']);
    });
  });

  group('a newly assigned order', () {
    test('appears on the next poll without the driver touching anything',
        () async {
      final backend = FakeBackend();
      final provider = DeliveryProvider(
        fetchOrders: backend.fetch,
        tracker: FakeTracker(),
      );

      backend.rows = [backendOrder('1')];
      await provider.refreshMyOrders(token: 't', silent: true);
      expect(provider.orders.map((o) => o.id), ['1']);

      // The dispatcher assigns another one.
      backend.rows = [backendOrder('2'), backendOrder('1')];
      await provider.refreshMyOrders(token: 't', silent: true);

      expect(provider.orders.map((o) => o.id), ['2', '1']);
    });

    test('still arrives after a request that never came back', () async {
      // The bug: the poll takes a "already fetching" lock, and a request that
      // hangs never gives it back — so every later poll returned immediately
      // and the list stopped updating for the rest of the session. Only
      // tapping a tab refreshed it by hand.
      final backend = FakeBackend();
      final provider = DeliveryProvider(
        fetchOrders: backend.fetch,
        tracker: FakeTracker(),
      );

      backend.rows = [backendOrder('1')];
      backend.hangUntil = Completer<void>();

      // Fire the request that wedges, and do not wait for it.
      final wedged = provider.refreshMyOrders(token: 't');
      await Future<void>.delayed(Duration.zero);
      expect(provider.isLoadingOrders, isTrue);

      // A poll arriving while it is stuck is skipped, as it should be...
      provider.startAutoRefresh(token: 't');
      await Future<void>.delayed(Duration.zero);
      expect(backend.calls, 1);
      provider.stopAutoRefresh();

      // ...but the lock has to let go once the request finally resolves,
      // rather than holding the driver's list frozen behind it.
      backend.hangUntil!.complete();
      await wedged;

      expect(provider.isLoadingOrders, isFalse);

      backend.rows = [backendOrder('2'), backendOrder('1')];
      await provider.refreshMyOrders(token: 't', silent: true);
      expect(provider.orders.map((o) => o.id), ['2', '1']);
    });
  });
}
