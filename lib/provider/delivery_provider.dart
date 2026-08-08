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
  delivered,  // Driver confirmed the delivery was completed.
  returned,   // Driver could not deliver and returned the order.
}

class DeliveryProvider extends ChangeNotifier {

  // ── Delivery state ────────────────────────────────────────────────────────
  DeliveryStatus _status = DeliveryStatus.notStarted;
  OrderModel? _currentOrder;   // The order currently selected or being delivered.

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
  // Orders the driver swiped away or explicitly marked as returned.
  final List<OrderModel> _returnedOrders = [];

  // Where the driver was when they started the delivery. Shown as the pickup
  // point on the order detail screen.
  LatLng? _pickupLocation;
  String? _pickupAddress;


  // ── Public getters ────────────────────────────────────────────────────────
  // Exposing unmodifiable views prevents external code from mutating the lists
  // directly — all changes must go through the provider's methods.
  DeliveryStatus get status => _status;
  OrderModel? get currentOrder => _currentOrder;
  bool get hasActiveDelivery =>
      _currentOrder != null && _status == DeliveryStatus.delivering;
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
      price: order.price,
      pickupLocation: pickupLocation,
      deliveryLocation: order.deliveryLocation,
      pickupAddress: pickupAddress,
      deliveryAddress: order.deliveryAddress,
      city: order.city,
      isPaid: order.isPaid,
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
      price: order.price,
      pickupLocation: order.pickupLocation,
      deliveryLocation: order.deliveryLocation,
      pickupAddress: order.pickupAddress,
      deliveryAddress: order.deliveryAddress,
      city: order.city,
      isPaid: true,
    );
  }

  // Fetches the list of assigned (non-delivered) orders for this driver
  // from GET /api/drivers/me/orders. Sets loading state before the call
  // and clears it in the finally block regardless of success or failure.
  Future<void> refreshMyOrders({required String token}) async {
    final activeOrderId = hasActiveDelivery ? _currentOrder?.id : null;
    final activeStatus = _status;
    final activeOrder = _currentOrder;
    final activePickupLocation = _pickupLocation;
    final activePickupAddress = _pickupAddress;

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

      // Do not reset an in-progress delivery just because Home/Orders refreshed.
      // Keep the driver's local progress until the order is delivered or returned.
      if (activeOrderId != null) {
        final refreshedIndex = _orders.indexWhere((o) => o.id == activeOrderId);
        if (refreshedIndex >= 0) {
          final refreshed = _orders[refreshedIndex];
          final pickupLocation =
              activePickupLocation ??
              activeOrder?.pickupLocation ??
              refreshed.pickupLocation;
          final pickupAddress =
              activePickupAddress ??
              activeOrder?.pickupAddress ??
              refreshed.pickupAddress;
          final preserved = _withPickup(
            refreshed,
            pickupLocation: pickupLocation,
            pickupAddress: pickupAddress,
          );
          _orders[refreshedIndex] = preserved;
          _currentOrder = preserved;
        } else {
          _currentOrder = activeOrder;
        }
        _status = activeStatus;
        _pickupLocation = activePickupLocation;
        _pickupAddress = activePickupAddress;
      } else {
        _currentOrder = _orders.isNotEmpty ? _orders.first : null;
        _status = DeliveryStatus.notStarted;
        _pickupLocation = null;
        _pickupAddress = null;
      }
    } catch (e) {
      _ordersError = e.toString();
      if (activeOrderId != null) {
        _currentOrder = activeOrder;
        _status = activeStatus;
        _pickupLocation = activePickupLocation;
        _pickupAddress = activePickupAddress;
      } else {
        _orders = [];
        _currentOrder = null;
        _status = DeliveryStatus.notStarted;
        _pickupLocation = null;
        _pickupAddress = null;
      }
    } finally {
      _isLoadingOrders = false;
      notifyListeners(); // Triggers rebuild with real data or error message.
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

  // Clears the current order. Called when the driver finishes a delivery.
  void dismissCurrentOrder() {
    _currentOrder = null;
    _pickupLocation = null;
    _pickupAddress = null;
    notifyListeners();
  }

  // Removes a specific order from the pending list (swipe-to-dismiss on the
  // orders screen). If the dismissed order was the current one, the current
  // order is reset to the next available order (or null if the list is empty).
  // The dismissed order is kept in _returnedOrders for the Returned tab.
  void dismissOrder(OrderModel order) {
    _moveToReturned(order);
    if (_currentOrder?.id == order.id) {
      _currentOrder = _orders.isNotEmpty ? _orders.first : null;
      if (_currentOrder == null) {
        _pickupLocation = null;
        _pickupAddress = null;
      }
    }
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

  // Sets the selected order. If the selected order is already in progress,
  // keep its current step instead of restarting the delivery flow.
  void setCurrentOrder(OrderModel order) {
    if (hasActiveDelivery && _currentOrder?.id == order.id) {
      notifyListeners();
      return;
    }

    _currentOrder = order;
    _status = DeliveryStatus.notStarted;
    _pickupLocation = null;
    _pickupAddress = null;
    notifyListeners();
  }

  // Called when the driver taps "Start Delivery". Records where the driver was
  // when they set off and starts sharing GPS with the backend so the customer
  // tracking page can plot the driver once the dispatcher flips the order to
  // PICKED_UP from the dashboard.
  void startDelivery({required LatLng driverLocation}) {
    if (_currentOrder == null) return;

    _pickupLocation = driverLocation;
    _pickupAddress = 'Current location';

    // Rebuild the current order with the now-known pickup coordinates.
    _currentOrder = _withPickup(
      _currentOrder!,
      pickupLocation: driverLocation,
      pickupAddress: _pickupAddress!,
    );

    _status = DeliveryStatus.delivering;

    final orderId = _currentOrder!.id;
    if (orderId.isNotEmpty) {
      BackgroundLocationService.startTracking(orderId);
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
    }
    _status = DeliveryStatus.delivered;
    BackgroundLocationService.stopTracking();
    notifyListeners();
  }

  // Local state update for an order the driver brought back. Moves it out of
  // the pending list and into the Returned tab.
  void completeReturn() {
    final order = _currentOrder;
    if (order != null) {
      _moveToReturned(order);
    }
    _status = DeliveryStatus.returned;
    BackgroundLocationService.stopTracking();
    notifyListeners();
  }

  // Resets the delivery state so the driver is ready to start the next order.
  void resetDelivery() {
    _status = DeliveryStatus.notStarted;
    BackgroundLocationService.stopTracking();
    notifyListeners();
  }
}
