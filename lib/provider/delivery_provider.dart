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
//   - The list of returned orders.
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
// There is no in-app map, no accept/decline step and no "picked up" step.
// PICKED_UP is set by the dispatcher from the dashboard — that status is what
// makes the driver's marker appear on the customer's tracking page, while the
// coordinates themselves are posted by the background location service that
// starts the moment the driver taps "Start Delivery".

import 'dart:async';

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/services/api_client.dart';
import 'package:delivery_boy_app/services/background_location_service.dart';
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
  // Orders the driver explicitly marked as returned.
  final List<OrderModel> _returnedOrders = [];

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

  List<OrderModel> get orders => List.unmodifiable(_orders);
  bool get isLoadingOrders => _isLoadingOrders;
  String? get ordersError => _ordersError;
  List<OrderModel> get completedOrders => List.unmodifiable(_completedOrders);
  bool get isLoadingCompleted => _isLoadingCompleted;
  String? get completedError => _completedError;
  List<OrderModel> get returnedOrders => List.unmodifiable(_returnedOrders);

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

  // Returns a copy of the given order with isPaid set to true.
  // This is used when the driver completes a COD delivery — at that moment
  // cash has been collected, so we flip the financial status to paid.
  //
  // isPrepaid is deliberately left alone: it describes how the order arrived,
  // so collecting the cash on delivery must not change it — that is exactly
  // the distinction the earnings totals rely on.
  OrderModel _withPaid(OrderModel order) {
    return order.copyWith(isPaid: true);
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
      final finishedIds = {
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
      await refreshMyOrders(token: token, silent: true);
      // Only worth a request once the driver has actually opened the Done tab.
      if (_completedLoadedOnce) {
        await refreshCompletedOrders(token: token, silent: true);
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
      _returnedOrders.removeWhere((o) => o.id == order.id);
      _completedOrders =
          _completedOrders.where((o) => o.id != order.id).toList();
    }

    _statusById[order.id] = DeliveryStatus.delivering;

    if (order.id.isNotEmpty) {
      BackgroundLocationService.startTracking(order.id);
    }

    notifyListeners();

    if (!isRestart || order.id.isEmpty || token.isEmpty) return;

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
      _undoRestart(order, previousStatus);
      rethrow;
    }
  }

  // Puts a finished order that failed to re-open back where the driver found
  // it, exactly as it was before they tapped "Start Delivery".
  void _undoRestart(OrderModel order, DeliveryStatus previousStatus) {
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
  // Throws if the network call fails so the caller can show an error to the driver.
  Future<void> markDelivered({required String token}) async {
    final orderId = _currentOrder?.id;
    completeDelivery(); // instant UI update — removes from pending, adds to completed
    if (orderId == null || orderId.isEmpty) return;
    // Marked until the backend confirms: this is what protects the order from
    // being dropped by a completed-orders fetch that raced the PATCH.
    _unsyncedCompletedIds.add(orderId);
    try {
      await ApiClient.updateOrderStatus(
        token: token,
        orderId: orderId,
        status: 'DELIVERED',
      );
      _unsyncedCompletedIds.remove(orderId);
    } catch (e) {
      rethrow; // caller shows error snackbar; the id stays marked unsynced
    }
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

  // Updates UI immediately, then syncs RETURNED to the backend.
  // Throws if the network call fails so the caller can show an error to the driver.
  Future<void> markReturned({required String token}) async {
    final orderId = _currentOrder?.id;
    completeReturn(); // instant UI update — moves the order to the Returned tab
    if (orderId == null || orderId.isEmpty) return;
    try {
      await ApiClient.updateOrderStatus(
        token: token,
        orderId: orderId,
        status: 'RETURNED',
      );
    } catch (e) {
      rethrow; // caller shows error snackbar
    }
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
      final paidOrder = _withPaid(_currentOrder!);

      // Remove the order from the active/pending list now that it is done.
      _orders.removeWhere((o) => o.id == _currentOrder!.id);

      // An order can be returned and then sent out again later. Drop it from
      // the Returned tab, otherwise it sits in both tabs at once — and because
      // the returned list only lives in memory, that only came right after a
      // restart wiped it.
      _returnedOrders.removeWhere((o) => o.id == _currentOrder!.id);

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
