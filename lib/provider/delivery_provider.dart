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

  // ── Returned orders ───────────────────────────────────────────────────────
  // Orders the driver explicitly marked as returned.
  final List<OrderModel> _returnedOrders = [];

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
    return OrderModel(
      id: order.id,
      customerName: order.customerName,
      customerPhone: order.customerPhone,
      item: order.item,
      quantity: order.quantity,
      lineItems: order.lineItems,
      price: order.price,
      pickupLocation: pickupLocation,
      deliveryLocation: order.deliveryLocation,
      pickupAddress: pickupAddress,
      deliveryAddress: order.deliveryAddress,
      city: order.city,
      area: order.area,
      isPaid: order.isPaid,
      isPrepaid: order.isPrepaid,
      deliveredAt: order.deliveredAt,
    );
  }

  // Returns a copy of the given order with isPaid set to true.
  // This is used when the driver completes a COD delivery — at that moment
  // cash has been collected, so we flip the financial status to paid.
  // Because OrderModel is immutable (every field is final), we cannot just
  // write order.isPaid = true. Instead we must create a fresh instance that
  // is identical in every way except isPaid, which is the standard immutable
  // update pattern in Flutter/Dart.
  OrderModel _withPaid(OrderModel order) {
    return OrderModel(
      id: order.id,
      customerName: order.customerName,
      customerPhone: order.customerPhone,
      item: order.item,
      quantity: order.quantity,
      lineItems: order.lineItems,
      price: order.price,
      pickupLocation: order.pickupLocation,
      deliveryLocation: order.deliveryLocation,
      pickupAddress: order.pickupAddress,
      deliveryAddress: order.deliveryAddress,
      city: order.city,
      area: order.area,
      isPaid: true,
      // isPrepaid describes how the order arrived, so collecting the cash on
      // delivery must not change it — that is exactly the distinction the
      // earnings totals rely on.
      isPrepaid: order.isPrepaid,
      deliveredAt: order.deliveredAt,
    );
  }

  // Fetches the list of assigned (non-delivered) orders for this driver
  // from GET /api/drivers/me/orders. Sets loading state before the call
  // and clears it in the finally block regardless of success or failure.
  Future<void> refreshMyOrders({required String token}) async {
    await _restoreActiveDeliveries();

    // Snapshot every in-progress delivery, not just the one on screen. Orders
    // the driver is carrying must survive a refresh even if the backend list
    // comes back without them.
    final activeIds = activeOrderIds;
    final activeOrdersById = {
      for (final o in [..._orders, if (_currentOrder != null) _currentOrder!])
        if (activeIds.contains(o.id)) o.id: o,
    };
    final previousCurrentId = _currentOrder?.id;

    _isLoadingOrders = true;
    _ordersError = null;
    notifyListeners(); // Triggers skeleton loading UI.

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
      _orders = parsed.where((o) => !finishedIds.contains(o.id)).toList();

      // Do not reset in-progress deliveries just because Home/Orders refreshed.
      // Keep the driver's local progress until each order is delivered or returned.
      _reapplyActiveOrders(activeOrdersById);
      _currentOrder = _pickCurrentOrder(previousCurrentId);
    } catch (e) {
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
  // fetched order list. Orders being delivered keep the pickup point stamped
  // when the driver set off, and an active order the backend no longer returns
  // is put back — the driver is physically holding it, so it cannot vanish
  // from the app just because a list request came back without it.
  void _reapplyActiveOrders(Map<String, OrderModel> activeOrdersById) {
    for (final entry in activeOrdersById.entries) {
      final id = entry.key;
      final held = entry.value;
      final index = _orders.indexWhere((o) => o.id == id);
      final base = index >= 0 ? _orders[index] : held;

      final pickupLocation =
          _pickupLocationById[id] ?? base.pickupLocation ?? held.pickupLocation;
      final pickupAddress =
          _pickupAddressById[id] ?? base.pickupAddress ?? held.pickupAddress;

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

  // Chooses which order the detail screen should show after a refresh: the one
  // the driver already had open if it still exists, otherwise an in-progress
  // delivery, otherwise the top of the list.
  OrderModel? _pickCurrentOrder(String? previousCurrentId) {
    if (_orders.isEmpty) return null;

    final previousIndex = previousCurrentId == null
        ? -1
        : _orders.indexWhere((o) => o.id == previousCurrentId);
    if (previousIndex >= 0) return _orders[previousIndex];

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
  Future<void> refreshCompletedOrders({required String token}) async {
    _isLoadingCompleted = true;
    _completedError = null;
    notifyListeners();

    try {
      final list = await ApiClient.getCompletedOrders(token: token);
      final parsed = <OrderModel>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          parsed.add(OrderModel.fromBackend(item));
        }
      }
      // Merge: keep locally-completed orders that the backend doesn't know about
      // yet (the DELIVERED PATCH may still be in-flight). Without this, opening
      // the Done tab would wipe out the order the driver just delivered.
      final fetchedIds = parsed.map((o) => o.id).toSet();
      _completedOrders = [
        ...parsed,
        ..._completedOrders.where((o) => !fetchedIds.contains(o.id)),
      ];
    } catch (e) {
      _completedError = e.toString();
    } finally {
      _isLoadingCompleted = false;
      notifyListeners();
    }
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
  void startDelivery({required LatLng driverLocation}) {
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
    final index = _orders.indexWhere((o) => o.id == order.id);
    if (index >= 0) _orders[index] = started;

    _statusById[order.id] = DeliveryStatus.delivering;

    if (order.id.isNotEmpty) {
      BackgroundLocationService.startTracking(order.id);
    }

    notifyListeners();
  }

  // Updates UI immediately, then syncs DELIVERED to the backend.
  // Throws if the network call fails so the caller can show an error to the driver.
  Future<void> markDelivered({required String token}) async {
    final orderId = _currentOrder?.id;
    completeDelivery(); // instant UI update — removes from pending, adds to completed
    if (orderId == null || orderId.isEmpty) return;
    try {
      await ApiClient.updateOrderStatus(
        token: token,
        orderId: orderId,
        status: 'DELIVERED',
      );
    } catch (e) {
      rethrow; // caller shows error snackbar
    }
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
