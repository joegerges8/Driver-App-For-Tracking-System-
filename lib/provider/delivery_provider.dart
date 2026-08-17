// delivery_provider.dart
//
// This file implements the state management layer for all delivery-related
// data in the driver app. It uses the Provider package with ChangeNotifier,
// which is a reactive pattern: whenever data changes, notifyListeners() is
// called and any widget that is "watching" this provider automatically rebuilds.
//
// It manages:
//   - The list of assigned (pending) orders from the backend.
//   - The list of completed (delivered) orders from a separate endpoint.
//   - The list of returned orders, from a third endpoint.
//   - The current order being delivered and its delivery status.
//
// Delivery flow (deliberately kept as simple as possible):
//   1. Driver taps an order  → OrderDetailScreen, status = notStarted.
//   2. Driver taps "Start Delivery" → status = delivering, GPS sharing starts.
//   3. Driver taps "Mark as Delivered" or "Mark as Returned" → done.
//
// Several orders can be at step 2 at the same time — a driver doing a batch run
// starts each order as they load it, and each one keeps its own status until it
// is delivered or returned. That is why delivery state is keyed by order id
// rather than held in a single field: with one shared status, starting a second
// delivery silently ended the first, and its customer's map froze mid-journey.
//
// Step 3 is written down before it is sent. The outcome goes into a queue on
// disk (see pending_status_queue.dart) and is retried — on every poll, on every
// app start, and from the background service while the app is closed — until
// the backend confirms it. A driver who marks an order delivered with no
// signal used to lose it entirely: the order read as done on the phone and
// stayed out for delivery on the dispatcher's dashboard, with nothing left
// anywhere that would ever try again.
//
// There is no in-app map, no accept/decline step and no "picked up" step.
// PICKED_UP is set by the dispatcher from the dashboard — that status is what
// makes the driver's marker appear on the customer's tracking page, while the
// coordinates themselves are posted by the background location service that
// starts the moment the driver taps "Start Delivery".
//
// Starting a delivery does post one thing to the backend: the time it happened
// (POST /me/orders/:id/start). That is the clock the dispatcher's "avg to
// deliver" runs on, and it is a timestamp only — the order's status is left
// exactly where the dispatcher put it.

import 'dart:async';

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/services/api_client.dart';
import 'package:delivery_boy_app/services/background_location_service.dart';
import 'package:delivery_boy_app/services/pending_status_queue.dart';
import 'package:delivery_boy_app/utils/delivery_day.dart';
import 'package:delivery_boy_app/utils/order_sort.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Represents the stages of a single delivery. The UI uses this enum to decide
// which buttons to show at the bottom of the order detail screen.
enum DeliveryStatus {
  notStarted, // Order opened, driver has not started the delivery yet.
  delivering, // Driver tapped "Start Delivery" — on the way to the customer.
  delivered, // Driver confirmed the delivery was completed.
  returned, // Driver could not deliver and returned the order.
}

class DeliveryProvider extends ChangeNotifier {
  // ── Delivery state ────────────────────────────────────────────────────────
  // Status per order id. An order missing from this map has not been started.
  // Orders stay in here while they are being delivered and are removed once
  // they are delivered or returned.
  final Map<String, DeliveryStatus> _statusById = {};

  OrderModel? _currentOrder; // The order currently open on the detail screen.

  // Set once the in-progress deliveries have been restored from disk, so the
  // restore only runs on the first refresh after app start.
  bool _restoredActiveDeliveries = false;

  // ── Assigned (pending) orders ─────────────────────────────────────────────
  List<OrderModel> _orders = [];
  bool _isLoadingOrders = false;
  String? _ordersError;

  // ── Completed (delivered) orders ──────────────────────────────────────────
  // Fetched from a separate backend endpoint (GET /api/drivers/me/orders/completed).
  // Kept in a separate list so pending and completed orders are never mixed.
  List<OrderModel> _completedOrders = [];
  bool _isLoadingCompleted = false;
  String? _completedError;

  // Orders this device marked DELIVERED whose PATCH has not been acknowledged
  // by the backend yet. Only these survive a completed-orders fetch that comes
  // back without them — anything else the backend omits is genuinely gone.
  final Set<String> _unsyncedCompletedIds = {};

  // ── The outbox ────────────────────────────────────────────────────────────
  // Delivery outcomes written to disk and not yet accepted by the backend.
  //
  // A driver marking an order delivered with no signal used to lose it: the
  // PATCH failed, the order sat in the Done tab looking finished, and the
  // dashboard still showed it out for delivery with nothing left to try again.
  // The queue is the record that survives that — the app retries it on every
  // poll, on every relaunch, and from the background service while the app is
  // closed, until the backend confirms.
  //
  // This mirror of the stored queue is what the UI reads; PendingStatusQueue
  // holds the copy that outlives the process.
  List<PendingStatusChange> _pendingStatuses = const [];
  bool _loadedPendingStatuses = false;
  bool _isFlushingStatuses = false;

  // True once the Done tab has loaded at least once, so the background poll
  // knows whether keeping that list fresh is worth a request.
  bool _completedLoadedOnce = false;

  // ── Background polling ────────────────────────────────────────────────────
  // The app has no push channel for order changes, so while it is in the
  // foreground it re-fetches on a timer. Without this, an order the dispatcher
  // deleted stayed on the driver's screen until the app was restarted.
  static const Duration pollInterval = Duration(seconds: 30);
  Timer? _pollTimer;
  String? _pollToken;
  bool _isPolling = false;

  // ── Returned orders ───────────────────────────────────────────────────────
  // Orders the driver marked as returned, fetched from
  // GET /api/drivers/me/orders/returned.
  //
  // This list used to be built up in memory only. A returned order is closed on
  // the backend, so it is absent from the assigned list and is not delivered
  // either — nothing read it back, and closing the app emptied the Returned tab
  // even though the return itself had been recorded.
  List<OrderModel> _returnedOrders = [];
  bool _isLoadingReturned = false;
  String? _returnedError;

  // Orders this device marked RETURNED whose PATCH has not been acknowledged by
  // the backend yet. Only these survive a returned-orders fetch that comes back
  // without them — the same protection _unsyncedCompletedIds gives the Done tab.
  final Set<String> _unsyncedReturnedIds = {};

  // True once the Returned tab has loaded at least once, so the background poll
  // knows whether keeping that list fresh is worth a request.
  bool _returnedLoadedOnce = false;

  // Orders this device has just sent back out — a returned order the driver
  // tapped "Start Delivery" on again — whose re-opening PATCH the backend has
  // not acknowledged yet. Until it does, its order list still describes the
  // world from before the restart, and the order being missing from it means
  // "the answer is stale", not "the dispatcher took this away".
  final Set<String> _reopeningIds = {};

  // Where the driver was when they started each delivery, keyed by order id.
  // Shown as the pickup point on the order detail screen.
  final Map<String, LatLng> _pickupLocationById = {};
  final Map<String, String> _pickupAddressById = {};

  // ── Public getters ────────────────────────────────────────────────────────
  // Exposing unmodifiable views prevents external code from mutating the lists
  // directly — all changes must go through the provider's methods.

  // Status of the order currently open on the detail screen.
  DeliveryStatus get status => statusOf(_currentOrder?.id);
  OrderModel? get currentOrder => _currentOrder;

  // True when the order on screen is being delivered. Note this is about the
  // selected order only — use isDelivering() to ask about any other order.
  bool get hasActiveDelivery => isDelivering(_currentOrder?.id);

  /// Status of any order, whether or not it is the one on screen.
  DeliveryStatus statusOf(String? orderId) =>
      _statusById[orderId] ?? DeliveryStatus.notStarted;

  /// Whether this specific order is currently out for delivery.
  bool isDelivering(String? orderId) =>
      statusOf(orderId) == DeliveryStatus.delivering;

  /// Ids of every order the driver has started and not yet finished.
  Set<String> get activeOrderIds => _statusById.entries
      .where((e) => e.value == DeliveryStatus.delivering)
      .map((e) => e.key)
      .toSet();

  /// How many deliveries are in progress at once. The backend derives the same
  /// number independently (from which orders are receiving GPS pings) to widen
  /// each customer's ETA, since a driver carrying three orders reaches any one
  /// of them later than a driver carrying one.
  int get activeDeliveryCount => activeOrderIds.length;

  /// The driver's assigned orders, deliveries under way first.
  ///
  /// Both screens that show this list read it from here — the swipeable cards
  /// on the home screen and the All tab on the orders screen — so the orders
  /// the driver has set off with are at the top of both. See sortActiveFirst
  /// for why they are lifted and why nothing else moves.
  ///
  /// Sorted on the way out rather than in place: _orders is rebuilt from the
  /// backend's answer on every refresh, and the code that reapplies delivery
  /// state onto it works by matching ids, so there is nothing to gain from
  /// keeping the stored list in this order and one more thing to keep true.
  List<OrderModel> get orders => List.unmodifiable(
        sortActiveFirst(_orders, isActive: (o) => isDelivering(o.id)),
      );
  bool get isLoadingOrders => _isLoadingOrders;
  String? get ordersError => _ordersError;
  List<OrderModel> get completedOrders => List.unmodifiable(_completedOrders);

  /// The deliveries finished today, in the driver's own timezone.
  ///
  /// This is what the Done tab shows. The tab is a record of the day's run
  /// rather than of everything the driver has ever delivered: it fills up over
  /// the day and is empty again after midnight, so a driver counting what they
  /// delivered is counting today's work and nothing else.
  ///
  /// The full list is deliberately left alone — the Shipment screen reads it
  /// for its Day/Week/Month history, which only means anything if the older
  /// days are still there.
  ///
  /// Nothing needs to fire at midnight for the tab to empty. The list is
  /// filtered as it is read, and the background poll rebuilds the screen every
  /// [pollInterval] while the app is in the foreground, so the last of
  /// yesterday's cards leaves within half a minute of the day turning over.
  List<OrderModel> get todaysCompletedOrders =>
      List.unmodifiable(_completedOrders.where(isDeliveredToday));
  bool get isLoadingCompleted => _isLoadingCompleted;
  String? get completedError => _completedError;
  List<OrderModel> get returnedOrders => List.unmodifiable(_returnedOrders);
  bool get isLoadingReturned => _isLoadingReturned;
  String? get returnedError => _returnedError;

  /// How many finished deliveries are still waiting to reach the backend.
  ///
  /// Zero is the normal state — a delivery marked with signal syncs in the same
  /// second. Anything above zero means the dashboard does not know about that
  /// many completed orders yet, which is worth telling the driver so they are
  /// not surprised by a dispatcher asking about an order they finished hours
  /// ago.
  int get pendingSyncCount => _pendingStatuses.length;

  /// Whether this particular order is finished on the phone but not yet on the
  /// dashboard. Used by the order card to mark it as still syncing.
  bool hasPendingSync(String? orderId) =>
      orderId != null && _pendingStatuses.any((c) => c.orderId == orderId);

  // Creates a copy of an order with updated pickup location fields.
  // OrderModel is immutable (all fields are final), so we must create a new
  // instance rather than mutating the existing one.
  OrderModel _withPickup(
    OrderModel order, {
    required LatLng pickupLocation,
    required String pickupAddress,
  }) {
    return order.copyWith(
      pickupLocation: pickupLocation,
      pickupAddress: pickupAddress,
    );
  }

  // Returns a copy of the given order recorded as delivered: paid, and stamped
  // with the moment it finished.
  //
  // The payment flip is for a COD delivery — at that moment cash has been
  // collected, so the financial status becomes paid. isPrepaid is deliberately
  // left alone: it describes how the order arrived, so collecting the cash on
  // delivery must not change it — that is exactly the distinction the earnings
  // totals rely on.
  //
  // The timestamp is what dates the order to today's run. The backend stamps
  // its own delivered_at and that is the one that survives the next fetch, but
  // until the PATCH lands this copy is all the app has, and an order with no
  // completion time belongs to no day at all — the driver would tap "Mark as
  // Delivered" and watch the order leave the Done tab it had just entered.
  //
  // [at] is when the delivery actually happened, for the case where that is
  // not now: an order finished offline and read back out of the outbox after a
  // restart keeps the time the driver marked it, not the time the app reopened.
  OrderModel _withDeliveryRecorded(OrderModel order, {DateTime? at}) {
    return order.copyWith(isPaid: true, deliveredAt: at ?? DateTime.now());
  }

  // Fetches the list of assigned (non-delivered) orders for this driver
  // from GET /api/drivers/me/orders. Sets loading state before the call
  // and clears it in the finally block regardless of success or failure.
  //
  // A silent refresh is the one the poll timer fires: it skips the skeleton
  // loader and swallows network errors, so a driver reading an order is not
  // interrupted every 30 seconds by a spinner or a transient failure message.
  Future<void> refreshMyOrders({
    required String token,
    bool silent = false,
  }) async {
    await _restoreActiveDeliveries();
    // Deliveries finished offline before the app was last closed. Read before
    // the list is fetched so the answer can be judged against them.
    await loadPendingStatuses();

    // Snapshot every in-progress delivery, not just the one on screen. Orders
    // the driver is carrying must survive a refresh even if the backend list
    // comes back without them. This copy is what the failure path falls back
    // to; the success path takes a fresh one once the answer is in.
    final activeIds = activeOrderIds;
    final activeOrdersById = {
      for (final o in [..._orders, if (_currentOrder != null) _currentOrder!])
        if (activeIds.contains(o.id)) o.id: o,
    };
    final previousCurrentId = _currentOrder?.id;

    if (!silent) {
      _isLoadingOrders = true;
      _ordersError = null;
      notifyListeners(); // Triggers skeleton loading UI.
    }

    try {
      final list = await ApiClient.getMyOrders(token: token);
      final parsed = <OrderModel>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          parsed.add(OrderModel.fromBackend(item));
        }
      }
      // Filter out orders the driver has already finished locally. This prevents
      // a race condition where the PATCH request to mark an order DELIVERED or
      // RETURNED hasn't reached the server yet by the time refreshMyOrders runs,
      // causing the order to reappear in the list from the backend response.
      //
      // Orders whose outcome is still sitting in the outbox are moved into
      // their tab here first, then counted as finished with the rest. Without
      // that, an order the driver delivered in a dead spot — which the backend
      // still lists as assigned, because it has not been told — would come
      // back into the pending list on the next refresh and read as undelivered.
      final finishedIds = {
        ..._applyPendingStatuses(parsed),
        ..._completedOrders.map((o) => o.id),
        ..._returnedOrders.map((o) => o.id),
      };

      // Taken again now the answer is back, rather than reusing the snapshot
      // above: the driver may have tapped "Start Delivery" while the request
      // was in flight, and that order is about to be written over along with
      // the rest of the list.
      final startedIds = activeOrderIds;
      final startedById = {
        for (final o in [..._orders, if (_currentOrder != null) _currentOrder!])
          if (startedIds.contains(o.id)) o.id: o,
      };

      _orders = parsed.where((o) => !finishedIds.contains(o.id)).toList();

      // Do not reset in-progress deliveries just because Home/Orders refreshed.
      // Keep the driver's local progress until each order is delivered or returned.
      _reapplyActiveOrders(
        startedIds,
        startedById,
        parsed.map((o) => o.id).toSet(),
      );
      _publishBackendOrders(parsed);
      _currentOrder = _pickCurrentOrder(previousCurrentId);
      _ordersError = null;
    } catch (e) {
      // A poll that fails changes nothing: the driver keeps looking at the
      // list they already had, with no error banner they did not ask for.
      if (silent) return;

      _ordersError = e.toString();
      if (activeIds.isNotEmpty) {
        // Keep whatever the driver is carrying — a failed refresh must never
        // drop an in-progress delivery off the screen.
        _orders = activeOrdersById.values.toList();
        _currentOrder = _pickCurrentOrder(previousCurrentId);
      } else {
        _orders = [];
        _currentOrder = null;
      }
    } finally {
      _isLoadingOrders = false;
      notifyListeners(); // Triggers rebuild with real data or error message.
    }
  }

  // Re-applies the driver's local delivery progress on top of a freshly
  // fetched order list: orders being delivered keep the pickup point stamped
  // when the driver set off.
  //
  // [activeIds] is every delivery in progress, and every one of them is judged
  // by the same rule. It used to walk [heldById] instead — the orders it had
  // managed to find a copy of, which is the pending list plus whichever order
  // was open on the detail screen. Two deliveries running at once were
  // therefore treated differently: the one on screen was checked against the
  // backend and the other was not, so a refresh could quietly send exactly one
  // of them back to "Start Delivery" and leave the rest alone.
  //
  // [liveIds] is every order id the backend just returned. An in-progress
  // delivery missing from that answer is not a hiccup — the dispatcher deleted
  // the order, cancelled it or handed it to someone else — so it is dropped
  // and its GPS stream stopped rather than being pinned back onto the list.
  // The exception is an order this device has just sent back out, whose PATCH
  // is still in flight: the answer predates the restart and says nothing about
  // it. A request that failed outright never reaches here; that path still
  // keeps whatever the driver was carrying.
  void _reapplyActiveOrders(
    Set<String> activeIds,
    Map<String, OrderModel> heldById,
    Set<String> liveIds,
  ) {
    for (final id in activeIds) {
      final held = heldById[id];

      if (!liveIds.contains(id)) {
        if (_reopeningIds.contains(id)) {
          // Pin it back on: _orders was just rebuilt from an answer that does
          // not know about the restart yet.
          if (held != null && !_orders.any((o) => o.id == id)) {
            _orders.insert(0, held);
          }
          continue;
        }
        _forgetOrder(id);
        continue;
      }

      final index = _orders.indexWhere((o) => o.id == id);
      if (index < 0 && held == null) continue;

      final base = index >= 0 ? _orders[index] : held!;

      final pickupLocation =
          _pickupLocationById[id] ?? base.pickupLocation ?? held?.pickupLocation;
      final pickupAddress =
          _pickupAddressById[id] ?? base.pickupAddress ?? held?.pickupAddress;

      final preserved = pickupLocation == null
          ? base
          : _withPickup(
              base,
              pickupLocation: pickupLocation,
              pickupAddress: pickupAddress ?? 'Current location',
            );

      if (index >= 0) {
        _orders[index] = preserved;
      } else {
        _orders.insert(0, preserved);
      }
    }
  }

  // Tells the background service which orders the driver still holds.
  //
  // Only ever a stop condition. An order missing from this list has been
  // delivered, returned, cancelled or taken away, and its GPS stream ends even
  // if this phone started it — that is what stops a finished delivery from
  // streaming on until the app is restarted.
  //
  // Deliberately nothing here starts a delivery. The dispatcher marking an
  // order PICKED_UP moves the paperwork; it does not mean the driver has set
  // off, and a customer watching their tracking page must not see a driver
  // moving around until the driver themselves says so by tapping "Start
  // Delivery". The service polls for the same list on its own timer; passing
  // it along here just gets the answer there a few seconds sooner.
  //
  // Orders whose re-opening PATCH is still in flight are added to it. They are
  // open — the driver has taken them back out — the backend has simply not
  // been asked since. Leaving them out would stop their GPS for the seconds it
  // takes the PATCH to land, which is the start of the delivery and the part
  // of it the customer is most likely to be watching.
  void _publishBackendOrders(List<OrderModel> parsed) {
    final open = <String>{
      for (final order in parsed)
        if (order.id.isNotEmpty) order.id,
      ..._reopeningIds,
    };

    BackgroundLocationService.publishBackendOrders(openOrderIds: open);
  }

  // Erases every trace of an order the backend no longer has: its local
  // delivery status, the pickup point, its place in any list, and the GPS
  // stream still posting for it. Used when the dispatcher deletes an order
  // that this driver was carrying.
  void _forgetOrder(String orderId) {
    _statusById.remove(orderId);
    _pickupLocationById.remove(orderId);
    _pickupAddressById.remove(orderId);
    _orders.removeWhere((o) => o.id == orderId);
    if (orderId.isNotEmpty) {
      BackgroundLocationService.stopTrackingOrder(orderId);
    }
  }

  // Chooses which order the detail screen should show after a refresh: the one
  // the driver already had open if it still exists, otherwise an in-progress
  // delivery, otherwise the top of the list.
  //
  // An order that was open and is now gone clears the screen instead. Sliding
  // a different order's address and phone number under the driver, in place of
  // the one they were reading, is the one outcome worse than an empty screen.
  OrderModel? _pickCurrentOrder(String? previousCurrentId) {
    if (previousCurrentId != null) {
      final previousIndex = _orders.indexWhere(
        (o) => o.id == previousCurrentId,
      );
      if (previousIndex >= 0) return _orders[previousIndex];

      // An order the driver just delivered or returned has left the pending
      // list on purpose — keep it on screen so the finished state stays put
      // until they navigate away themselves.
      for (final finished in [..._completedOrders, ..._returnedOrders]) {
        if (finished.id == previousCurrentId) return finished;
      }

      return null;
    }

    if (_orders.isEmpty) return null;

    final activeIndex = _orders.indexWhere((o) => isDelivering(o.id));
    if (activeIndex >= 0) return _orders[activeIndex];

    return _orders.first;
  }

  // Restores in-progress deliveries after the app was killed and relaunched.
  // The background location service keeps posting GPS for those orders from
  // its own isolate, so the ids it holds are the source of truth for what the
  // driver is still carrying — without this the UI would come back showing
  // "Start Delivery" for an order already on the road.
  Future<void> _restoreActiveDeliveries() async {
    if (_restoredActiveDeliveries) return;
    _restoredActiveDeliveries = true;

    try {
      final ids = await BackgroundLocationService.activeOrderIds();
      for (final id in ids) {
        _statusById[id] = DeliveryStatus.delivering;
      }
    } catch (_) {
      // Restore is best-effort — a driver can always tap Start Delivery again.
    }
  }

  // Fetches the list of completed (DELIVERED) orders for this driver
  // from GET /api/drivers/me/orders/completed.
  // This is called lazily — only when the driver opens the Done tab —
  // to avoid an unnecessary network request on app startup.
  Future<void> refreshCompletedOrders({
    required String token,
    bool silent = false,
  }) async {
    if (!silent) {
      _isLoadingCompleted = true;
      _completedError = null;
      notifyListeners();
    }

    try {
      final list = await ApiClient.getCompletedOrders(token: token);
      final parsed = <OrderModel>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          parsed.add(OrderModel.fromBackend(item));
        }
      }
      // Merge: keep locally-completed orders whose DELIVERED PATCH has not been
      // acknowledged yet. Without this, opening the Done tab would wipe out the
      // order the driver just delivered. Anything else the backend leaves out
      // has been deleted from the dashboard, so it leaves the tab too.
      final fetchedIds = parsed.map((o) => o.id).toSet();
      _completedOrders = [
        ...parsed,
        ..._completedOrders.where(
          (o) =>
              !fetchedIds.contains(o.id) && _unsyncedCompletedIds.contains(o.id),
        ),
      ];
      _completedLoadedOnce = true;

      // The backend calling an order delivered settles it, whoever recorded
      // that — the dispatcher, or this driver on another device. A stale copy
      // in the local Returned tab would otherwise show it in both tabs.
      _returnedOrders.removeWhere((o) => fetchedIds.contains(o.id));
      _completedError = null;
    } catch (e) {
      if (silent) return;
      _completedError = e.toString();
    } finally {
      _isLoadingCompleted = false;
      notifyListeners();
    }
  }

  // Fetches the orders this driver brought back, from
  // GET /api/drivers/me/orders/returned. This is what makes the Returned tab
  // survive the app being closed and reopened.
  Future<void> refreshReturnedOrders({
    required String token,
    bool silent = false,
  }) async {
    if (!silent) {
      _isLoadingReturned = true;
      _returnedError = null;
      notifyListeners();
    }

    try {
      final list = await ApiClient.getReturnedOrders(token: token);
      final parsed = <OrderModel>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final order = OrderModel.fromBackend(item);
          // An order the driver has just taken back out is still RETURNED on the
          // backend until its re-opening PATCH lands. Putting it back in the
          // Returned tab in the meantime would pull the delivery the driver just
          // started out from under them.
          if (_reopeningIds.contains(order.id)) continue;
          parsed.add(order);
        }
      }

      // Merge on the same terms as the Done tab: keep an order this device just
      // returned whose PATCH is still in flight, because the answer was written
      // before it landed. Anything else the backend leaves out is genuinely no
      // longer returned — sent back out, or deleted from the dashboard — so it
      // leaves the tab too.
      final fetchedIds = parsed.map((o) => o.id).toSet();
      _returnedOrders = [
        ...parsed,
        ..._returnedOrders.where(
          (o) =>
              !fetchedIds.contains(o.id) && _unsyncedReturnedIds.contains(o.id),
        ),
      ];
      _returnedLoadedOnce = true;

      // A returned order is not a delivered one. If the backend now calls it
      // returned, a stale copy in the Done tab would show it in both at once —
      // the mirror of what refreshCompletedOrders does for this list.
      _completedOrders =
          _completedOrders.where((o) => !fetchedIds.contains(o.id)).toList();

      // It is closed on the backend, so it has no business sitting in the
      // assigned list either. Closing it here also stops its GPS stream, which
      // matters when the return was recorded elsewhere — on another device, or
      // by the dispatcher — and this app never saw it happen.
      final nowReturned =
          _orders.where((o) => fetchedIds.contains(o.id)).toList();
      for (final order in nowReturned) {
        _finishOrder(order.id, DeliveryStatus.returned);
      }
      _orders.removeWhere((o) => fetchedIds.contains(o.id));
      _returnedError = null;
    } catch (e) {
      if (silent) return;
      _returnedError = e.toString();
    } finally {
      _isLoadingReturned = false;
      notifyListeners();
    }
  }

  // ── Auto-refresh ──────────────────────────────────────────────────────────

  /// Starts re-fetching orders every [pollInterval] while the app is in the
  /// foreground, and fetches once straight away. Called on login and whenever
  /// the app is resumed, so changes made on the dashboard — a deleted order
  /// above all — reach the driver without them restarting the app.
  void startAutoRefresh({required String token}) {
    if (token.isEmpty) return;
    _pollToken = token;

    _pollTimer ??= Timer.periodic(pollInterval, (_) => _poll());
    _poll();
  }

  /// Stops the timer when the app goes to the background or the driver logs
  /// out. The background location service keeps running on its own; only the
  /// order-list polling stops.
  ///
  /// Whatever round was in flight is abandoned here rather than left to be
  /// waited on. A request issued just before the app was put away can be left
  /// hanging by the phone dropping its connection, and _isPolling was what
  /// every later round checked before starting: one such request meant no poll
  /// ever ran again for the rest of the session, so an order the dispatcher
  /// assigned only appeared once the driver happened to tap a tab. The reply,
  /// if one ever arrives, is still applied — it is the same list, only later.
  void stopAutoRefresh() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isPolling = false;
  }

  // One silent round of polling. Skips itself while a fetch the driver asked
  // for is already running, so a pull-to-refresh is never fought over.
  Future<void> _poll() async {
    final token = _pollToken;
    if (token == null || token.isEmpty) return;
    if (_isPolling || _isLoadingOrders || _isLoadingCompleted) return;

    _isPolling = true;
    try {
      // Before anything is read, whatever the app still owes the backend is
      // sent. This is the retry that closes the loop: a delivery marked with no
      // signal reaches the dashboard on the first poll after the connection
      // comes back, without the driver doing anything.
      await flushPendingStatuses(token: token);
      await refreshMyOrders(token: token, silent: true);
      // Only worth a request once the driver has actually opened the Done tab.
      if (_completedLoadedOnce) {
        await refreshCompletedOrders(token: token, silent: true);
      }
      if (_returnedLoadedOnce) {
        await refreshReturnedOrders(token: token, silent: true);
      }
    } finally {
      _isPolling = false;
    }
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }

  // Clears the order shown on the detail screen. Called when the driver
  // finishes a delivery. Other in-progress deliveries are untouched.
  void dismissCurrentOrder() {
    _currentOrder = null;
    notifyListeners();
  }

  // Moves an order out of the pending list and into the Returned tab.
  // Does not notify — callers batch their own notifyListeners() call.
  void _moveToReturned(OrderModel order) {
    if (!_returnedOrders.any((o) => o.id == order.id)) {
      _returnedOrders.insert(0, order);
    }
    _orders.removeWhere((o) => o.id == order.id);
    // Delivered and returned are the two ends of the same order: an order that
    // goes back out after being delivered must not stay in the Done tab.
    _completedOrders =
        _completedOrders.where((o) => o.id != order.id).toList();
  }

  // Opens an order on the detail screen. Simply selecting an order no longer
  // touches any delivery state: each order carries its own status, so viewing
  // order B must not disturb order A, which may be out for delivery.
  void setCurrentOrder(OrderModel order) {
    _currentOrder = order;
    notifyListeners();
  }

  // Called when the driver taps "Start Delivery". Records where the driver was
  // when they set off and starts sharing GPS with the backend so the customer
  // tracking page can plot the driver once the dispatcher flips the order to
  // PICKED_UP from the dashboard.
  //
  // Starting a second order does not end the first: both stay in _statusById
  // and the background service posts the driver's position to both.
  //
  // An order the driver brought back and is now taking out again is the one
  // case where this touches the backend. A returned order is closed there, so
  // it is absent from the driver's order list — which is what the GPS stream
  // and every refresh are judged against. Left alone, the restart lasted only
  // until the next refresh, which read the order's absence as the dispatcher
  // having taken it away and put the card back to "Start Delivery", and the
  // customer's page never saw the driver move in the meantime. Re-opening the
  // order is what makes taking it out again mean anything.
  //
  // The status it goes back to is ASSIGNED — the order is in the driver's
  // hands and no further than that. Declaring it PICKED_UP stays the
  // dispatcher's call, exactly as it is for an order going out the first time.
  Future<void> startDelivery({
    required LatLng driverLocation,
    required String token,
  }) async {
    final order = _currentOrder;
    if (order == null) return;

    const pickupAddress = 'Current location';
    _pickupLocationById[order.id] = driverLocation;
    _pickupAddressById[order.id] = pickupAddress;

    // Rebuild the current order with the now-known pickup coordinates, and keep
    // the copy in the pending list in sync so the card shows the same thing.
    final started = _withPickup(
      order,
      pickupLocation: driverLocation,
      pickupAddress: pickupAddress,
    );
    _currentOrder = started;

    // Not being in the pending list is what marks a restart: the order was
    // finished, so it sits in the Returned or Done tab and nowhere else.
    final previousStatus = statusOf(order.id);
    final index = _orders.indexWhere((o) => o.id == order.id);
    final isRestart = index < 0;
    if (index >= 0) {
      _orders[index] = started;
    } else {
      _orders.insert(0, started);
      _returnedOrders = _returnedOrders.where((o) => o.id != order.id).toList();
      _unsyncedReturnedIds.remove(order.id);
      _completedOrders =
          _completedOrders.where((o) => o.id != order.id).toList();
    }

    _statusById[order.id] = DeliveryStatus.delivering;

    // Taking the order back out cancels any outcome still queued for it. The
    // backend was never told that this order was delivered or returned — that
    // is what "queued" means — so it already holds the order as open, which is
    // exactly where the driver is putting it. Sending the old outcome later
    // would close an order that is on the road.
    final supersededQueue = _pendingFor(order.id);
    if (supersededQueue != null) await _clearPending(order.id);

    if (order.id.isNotEmpty) {
      BackgroundLocationService.startTracking(order.id);
    }

    notifyListeners();

    if (order.id.isEmpty || token.isEmpty) return;

    // An ordinary start tells the backend one thing and changes nothing else:
    // the moment the driver set off, which is what the dispatcher's average
    // delivery time is measured from. It cannot fail loudly — see
    // ApiClient.startOrderDelivery.
    if (!isRestart) {
      await ApiClient.startOrderDelivery(token: token, orderId: order.id);
      return;
    }

    _reopeningIds.add(order.id);
    try {
      await ApiClient.updateOrderStatus(
        token: token,
        orderId: order.id,
        status: 'ASSIGNED',
      );
      _reopeningIds.remove(order.id);
    } catch (_) {
      // The order is still closed on the backend, so nothing about this
      // restart would survive: no GPS would flow and the next refresh would
      // drop the order out of every tab. Put it back where the driver found
      // it and let the caller say why.
      _reopeningIds.remove(order.id);
      await _undoRestart(order, previousStatus, requeue: supersededQueue);
      rethrow;
    }

    // After the re-open, never before: re-opening the order clears the trip
    // that ended in a return, and it is this trip — the one going out now —
    // that the delivery is timed from.
    await ApiClient.startOrderDelivery(token: token, orderId: order.id);
  }

  /// The queued outcome for an order, or null if it has none outstanding.
  PendingStatusChange? _pendingFor(String orderId) {
    for (final change in _pendingStatuses) {
      if (change.orderId == orderId) return change;
    }
    return null;
  }

  // Puts a finished order that failed to re-open back where the driver found
  // it, exactly as it was before they tapped "Start Delivery".
  //
  // [requeue] is the outcome that was cancelled when the restart began. If the
  // restart itself never landed, that cancellation must be undone too —
  // otherwise a driver who tapped "Start Delivery" on a delivered order while
  // offline would end up with the order back in the Done tab and nothing left
  // anywhere to tell the backend it was ever delivered.
  Future<void> _undoRestart(
    OrderModel order,
    DeliveryStatus previousStatus, {
    PendingStatusChange? requeue,
  }) async {
    if (requeue != null) {
      _pendingStatuses = await PendingStatusQueue.enqueue(requeue);
      if (requeue.isDelivered) {
        _unsyncedCompletedIds.add(order.id);
      } else {
        _unsyncedReturnedIds.add(order.id);
      }
    }

    _statusById[order.id] = previousStatus;
    _pickupLocationById.remove(order.id);
    _pickupAddressById.remove(order.id);
    if (_currentOrder?.id == order.id) _currentOrder = order;

    if (previousStatus == DeliveryStatus.delivered) {
      _orders.removeWhere((o) => o.id == order.id);
      if (!_completedOrders.any((o) => o.id == order.id)) {
        _completedOrders = [order, ..._completedOrders];
      }
    } else {
      _moveToReturned(order); // also takes it back out of the pending list
    }

    if (order.id.isNotEmpty) {
      BackgroundLocationService.stopTrackingOrder(order.id);
    }
    notifyListeners();
  }

  // Updates UI immediately, then syncs DELIVERED to the backend.
  //
  // Returns true when the backend has confirmed it, false when it could not be
  // reached and the delivery has been queued to send later. Throws only when
  // the backend actively refused the change — an order that is no longer this
  // driver's — because that is the one case where trying again cannot help and
  // the driver needs to be told now.
  Future<bool> markDelivered({required String token}) async {
    final orderId = _currentOrder?.id;
    completeDelivery(); // instant UI update — removes from pending, adds to completed
    if (orderId == null || orderId.isEmpty) return true;
    return _recordStatusChange(
      orderId: orderId,
      status: 'DELIVERED',
      token: token,
    );
  }

  // Saves the driver's own note on the order that is open on the detail screen.
  //
  // The note is written to local state first so it appears the moment the
  // driver saves it, then synced. A failed sync rethrows for the caller to
  // surface, and the local copy is rolled back to what the backend still
  // holds — a note that silently vanishes on the next refresh is worse than
  // one that reports it did not save.
  Future<void> saveDriverNote({
    required String token,
    required String note,
  }) async {
    final order = _currentOrder;
    if (order == null) return;

    final previous = order.driverNote;
    final trimmed = note.trim();
    if (trimmed == previous) return;

    _applyDriverNote(order.id, trimmed);

    try {
      await ApiClient.updateOrderNote(
        token: token,
        orderId: order.id,
        note: trimmed,
      );
    } catch (e) {
      _applyDriverNote(order.id, previous);
      rethrow; // caller shows error snackbar
    }
  }

  // Writes a driver note into every copy of the order the provider holds: the
  // one on screen and the one in the assigned list behind it, which is what
  // the orders page rebuilds from.
  void _applyDriverNote(String orderId, String note) {
    if (_currentOrder?.id == orderId) {
      _currentOrder = _currentOrder!.copyWith(driverNote: note);
    }

    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index != -1) {
      _orders[index] = _orders[index].copyWith(driverNote: note);
    }

    notifyListeners();
  }

  // Records that the customer paid the order on screen by Whish transfer.
  //
  // Written locally first so the badge flips and the earnings totals drop the
  // amount the moment the driver confirms, then synced. The backend records
  // the payment in Shopify before answering, so a failure means nothing was
  // recorded anywhere — the local copy is rolled back and the caller surfaces
  // the error for the driver to try again with signal. Deliberately not
  // queued like delivered/returned: a payment must never sit on the phone
  // looking recorded while the store still shows the order as unpaid.
  Future<void> markPaidByWhish({required String token}) async {
    final order = _currentOrder;
    if (order == null || order.id.isEmpty) return;
    if (order.isPaidByWhish) return;

    final previousPaid = order.isPaid;
    final previousMethod = order.paymentMethod;

    _applyPayment(order.id, isPaid: true, paymentMethod: 'WHISH');

    try {
      await ApiClient.markOrderPaidByWhish(token: token, orderId: order.id);
    } catch (e) {
      _applyPayment(
        order.id,
        isPaid: previousPaid,
        paymentMethod: previousMethod,
      );
      rethrow; // caller shows error snackbar
    }
  }

  // Writes a payment state into every copy of the order the provider holds:
  // the one on screen, the assigned list behind it, and the Done tab — a
  // Whish payment can be recorded before or after the delivery itself is
  // marked, so the order may be sitting in either list.
  void _applyPayment(
    String orderId, {
    required bool isPaid,
    required String paymentMethod,
  }) {
    OrderModel apply(OrderModel o) =>
        o.copyWith(isPaid: isPaid, paymentMethod: paymentMethod);

    if (_currentOrder?.id == orderId) {
      _currentOrder = apply(_currentOrder!);
    }

    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index != -1) {
      _orders[index] = apply(_orders[index]);
    }

    final doneIndex = _completedOrders.indexWhere((o) => o.id == orderId);
    if (doneIndex != -1) {
      _completedOrders = List.of(_completedOrders)
        ..[doneIndex] = apply(_completedOrders[doneIndex]);
    }

    notifyListeners();
  }

  // Updates UI immediately, then syncs RETURNED to the backend, on exactly the
  // same terms as markDelivered above: true if it landed, false if it is
  // queued for when the connection is back, and it only throws if the backend
  // refused it outright.
  Future<bool> markReturned({required String token}) async {
    final orderId = _currentOrder?.id;
    completeReturn(); // instant UI update — moves the order to the Returned tab
    if (orderId == null || orderId.isEmpty) return true;
    return _recordStatusChange(
      orderId: orderId,
      status: 'RETURNED',
      token: token,
    );
  }

  // ── Syncing finished deliveries ───────────────────────────────────────────

  // Records a finished delivery and tries to send it.
  //
  // Written to disk before the request goes out, never after. That order
  // matters more than anything else here: the app can be killed between the
  // tap and the reply — a driver pockets the phone, the system reclaims the
  // app — and whatever was only in memory at that moment is what used to be
  // lost.
  Future<bool> _recordStatusChange({
    required String orderId,
    required String status,
    required String token,
  }) async {
    final change = PendingStatusChange(
      orderId: orderId,
      status: status,
      occurredAt: DateTime.now(),
    );

    // Marked until the backend confirms: this is what protects the order from
    // being dropped by a completed/returned fetch that raced the PATCH.
    if (change.isDelivered) {
      _unsyncedCompletedIds.add(orderId);
    } else {
      _unsyncedReturnedIds.add(orderId);
    }

    _pendingStatuses = await PendingStatusQueue.enqueue(change);
    notifyListeners();

    if (token.isEmpty) return false;

    final outcome = await _sendStatusChange(change, token: token);
    notifyListeners();
    if (outcome.error != null) throw outcome.error!;
    return outcome.sent;
  }

  // Sends one queued change and settles what happens to it.
  //
  // Accepted, or refused for a reason that will not change, and it leaves the
  // queue. Anything else — no signal, a timeout, a backend having a bad
  // minute — and it stays exactly where it is for the next attempt.
  Future<_StatusSyncOutcome> _sendStatusChange(
    PendingStatusChange change, {
    required String token,
  }) async {
    try {
      await ApiClient.updateOrderStatus(
        token: token,
        orderId: change.orderId,
        status: change.status,
        occurredAt: change.occurredAt,
      );
      await _clearPending(change.orderId);
      return const _StatusSyncOutcome(sent: true);
    } on ApiException catch (e) {
      if (e.isRetryable) return const _StatusSyncOutcome(sent: false);

      // The backend has considered it and said no — the order was deleted, or
      // handed to another driver while this phone was offline. Keeping it in
      // the queue would mean retrying it on every poll for the rest of time.
      await _clearPending(change.orderId);
      return _StatusSyncOutcome(sent: false, error: e);
    } catch (_) {
      // Anything unexpected is treated as worth trying again — the cost of a
      // pointless retry is one request, the cost of dropping a delivery is the
      // bug this whole queue exists to fix.
      return const _StatusSyncOutcome(sent: false);
    }
  }

  Future<void> _clearPending(String orderId) async {
    _pendingStatuses = await PendingStatusQueue.remove(orderId);
    _unsyncedCompletedIds.remove(orderId);
    _unsyncedReturnedIds.remove(orderId);
  }

  /// Reads the outbox back from disk, once per session.
  ///
  /// This is what carries a delivery across an app restart: the driver marks an
  /// order delivered underground, the app is killed before signal returns, and
  /// this is where the app finds out it still owes the backend an answer.
  Future<void> loadPendingStatuses() async {
    if (_loadedPendingStatuses) return;
    _loadedPendingStatuses = true;

    try {
      _pendingStatuses = await PendingStatusQueue.load();
      for (final change in _pendingStatuses) {
        // Re-arm the same protection a fresh mark gets, so a fetch that comes
        // back without these orders cannot quietly drop them from their tabs.
        if (change.isDelivered) {
          _unsyncedCompletedIds.add(change.orderId);
        } else {
          _unsyncedReturnedIds.add(change.orderId);
        }
        _statusById[change.orderId] = change.isDelivered
            ? DeliveryStatus.delivered
            : DeliveryStatus.returned;
      }
      if (_pendingStatuses.isNotEmpty) notifyListeners();
    } catch (_) {
      // A queue that cannot be read must not stop the app starting; the
      // deliveries in it are retried on the next launch instead.
    }
  }

  /// Tries to send everything still in the outbox.
  ///
  /// Called on every poll and on every app start. Stops at the first change
  /// that could not be sent: they all go to the same backend, so if one cannot
  /// reach it neither can the rest, and there is nothing to gain from working
  /// through the whole queue timing out on each entry in turn.
  Future<void> flushPendingStatuses({required String token}) async {
    if (token.isEmpty || _isFlushingStatuses) return;
    await loadPendingStatuses();

    // Re-read from disk before deciding there is work to do. The background
    // service flushes this same queue from its own isolate, so entries this
    // mirror still lists may already have reached the backend — without this
    // the app would keep telling the driver a delivery is waiting to sync long
    // after it had synced.
    final previousCount = _pendingStatuses.length;
    _pendingStatuses = await PendingStatusQueue.load(refresh: true);
    if (_pendingStatuses.length != previousCount) notifyListeners();

    if (_pendingStatuses.isEmpty) return;

    _isFlushingStatuses = true;
    var sentAny = false;
    try {
      for (final change in List.of(_pendingStatuses)) {
        final outcome = await _sendStatusChange(change, token: token);
        if (outcome.sent) {
          sentAny = true;
          continue;
        }
        // Refused for good: that one is gone from the queue, and the rest are
        // still worth attempting since the backend is plainly reachable.
        if (outcome.error != null) {
          sentAny = true;
          continue;
        }
        break; // offline — leave the rest for the next round
      }
    } finally {
      _isFlushingStatuses = false;
      if (sentAny) notifyListeners();
    }
  }

  // Applies the outbox to a freshly fetched order list.
  //
  // The backend answers with the world as it knows it, and it does not know
  // about deliveries it has not been told about yet — so an order finished
  // offline comes back still assigned. Left alone, it would reappear in the
  // driver's pending list as if the delivery had never been marked, which is
  // the same confusion from the other direction.
  //
  // Returns the ids it has taken over, for the caller to keep out of the
  // pending list.
  Set<String> _applyPendingStatuses(List<OrderModel> parsed) {
    if (_pendingStatuses.isEmpty) return const <String>{};

    final claimed = <String>{};
    for (final change in _pendingStatuses) {
      final index = parsed.indexWhere((o) => o.id == change.orderId);
      if (index < 0) continue;

      final order = parsed[index];
      claimed.add(order.id);
      _statusById[order.id] = change.isDelivered
          ? DeliveryStatus.delivered
          : DeliveryStatus.returned;

      if (change.isDelivered) {
        _returnedOrders =
            _returnedOrders.where((o) => o.id != order.id).toList();
        if (!_completedOrders.any((o) => o.id == order.id)) {
          _completedOrders = [
            _withDeliveryRecorded(order, at: change.occurredAt),
            ..._completedOrders,
          ];
        }
      } else {
        _completedOrders =
            _completedOrders.where((o) => o.id != order.id).toList();
        if (!_returnedOrders.any((o) => o.id == order.id)) {
          _returnedOrders = [order, ..._returnedOrders];
        }
      }
    }
    return claimed;
  }

  // Local state update for a finished delivery. Removes the order from the
  // pending list and prepends it to completedOrders so the Completed tab and
  // earnings strip update immediately without a refetch.
  void completeDelivery() {
    if (_currentOrder != null) {
      // Create a paid copy of the order before moving it to the completed list.
      // This is the "optimistic UI update" pattern: we assume the backend PATCH
      // will succeed and update the local state immediately so the driver sees
      // "Paid" the instant they tap "Mark as Delivered", without having to wait
      // for the network round-trip to finish. If the API call later fails, the
      // caller (order_detail_screen) shows an error snackbar.
      final paidOrder = _withDeliveryRecorded(_currentOrder!);

      // Remove the order from the active/pending list now that it is done.
      _orders.removeWhere((o) => o.id == _currentOrder!.id);

      // An order can be returned and then sent out again later. Drop it from
      // the Returned tab, otherwise it sits in both tabs at once.
      _returnedOrders =
          _returnedOrders.where((o) => o.id != _currentOrder!.id).toList();
      _unsyncedReturnedIds.remove(_currentOrder!.id);

      // Add the paid copy to the front of the completed list so it appears
      // immediately at the top of the "Done" tab without a refetch.
      if (!_completedOrders.any((o) => o.id == _currentOrder!.id)) {
        _completedOrders = [paidOrder, ..._completedOrders];
      }

      // Also update _currentOrder so any screen still watching it reflects the
      // paid status straight away.
      _currentOrder = paidOrder;
      _finishOrder(paidOrder.id, DeliveryStatus.delivered);
    }
    notifyListeners();
  }

  // Local state update for an order the driver brought back. Moves it out of
  // the pending list and into the Returned tab.
  void completeReturn() {
    final order = _currentOrder;
    if (order != null) {
      _moveToReturned(order);
      _finishOrder(order.id, DeliveryStatus.returned);
    }
    notifyListeners();
  }

  // Closes out one order: records its final status and stops only its own GPS
  // stream, so the driver's other deliveries keep reporting. The status is kept
  // (rather than removed) so a screen still showing this order renders the
  // finished state instead of falling back to "Start Delivery".
  void _finishOrder(String orderId, DeliveryStatus status) {
    _statusById[orderId] = status;
    _pickupLocationById.remove(orderId);
    _pickupAddressById.remove(orderId);
    if (orderId.isNotEmpty) {
      BackgroundLocationService.stopTrackingOrder(orderId);
    }
  }

  // Resets the order on screen so the driver can start it again. Stops that
  // order's GPS stream only — other in-progress deliveries are unaffected.
  void resetDelivery() {
    final orderId = _currentOrder?.id;
    if (orderId != null) {
      _statusById.remove(orderId);
      _pickupLocationById.remove(orderId);
      _pickupAddressById.remove(orderId);
      if (orderId.isNotEmpty) {
        BackgroundLocationService.stopTrackingOrder(orderId);
      }
    }
    notifyListeners();
  }
}

// What became of one attempt to send a queued outcome.
//
// Three results, not two: it landed, it could not be sent and is still queued,
// or the backend refused it for good. The last one carries the exception so the
// caller can decide whether the driver needs to see it — the driver who just
// tapped the button does, a background retry does not.
class _StatusSyncOutcome {
  const _StatusSyncOutcome({required this.sent, this.error});

  final bool sent;
  final ApiException? error;
}
