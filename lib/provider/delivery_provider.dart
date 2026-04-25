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
//   - The current order being delivered and its delivery status.
//   - The driver's live GPS position and the route polyline on the map.

import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/services/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Represents the step-by-step stages of a single delivery lifecycle.
// The UI uses this enum to decide which buttons and messages to show
// on the delivery map and order detail screens.
enum DeliveryStatus {
  waitingForAcceptance, // Order assigned, driver has not yet accepted it.
  orderAccepted,        // Driver accepted — navigating to pickup point.
  pickingUp,            // Driver has started moving to pickup location.
  destinationReached,   // Driver arrived at the delivery destination.
  markingAsDelivered,   // Driver tapped "Mark as Delivered".
  delivered,            // Delivery confirmed complete.
  rejected,             // Driver declined the order.
}

class DeliveryProvider extends ChangeNotifier {

  // ── Delivery state ────────────────────────────────────────────────────────
  DeliveryStatus _status = DeliveryStatus.waitingForAcceptance;
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

  // ── Map state ─────────────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];
  LatLng? _currentDeliveryBoyPosition;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  LatLng? _pickupLocation;
  String? _pickupAddress;

  // ── Public getters ────────────────────────────────────────────────────────
  // Exposing unmodifiable views prevents external code from mutating the lists
  // directly — all changes must go through the provider's methods.
  DeliveryStatus get status => _status;
  OrderModel? get currentOrder => _currentOrder;
  List<OrderModel> get orders => List.unmodifiable(_orders);
  bool get isLoadingOrders => _isLoadingOrders;
  String? get ordersError => _ordersError;
  List<OrderModel> get completedOrders => List.unmodifiable(_completedOrders);
  bool get isLoadingCompleted => _isLoadingCompleted;
  String? get completedError => _completedError;
  List<LatLng> get routePoints => _routePoints;
  LatLng? get currentDeliveryBoyPosition => _currentDeliveryBoyPosition;
  Set<Polyline> get polylines => _polylines;
  Set<Marker> get markers => _markers;

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
    );
  }

  // Fetches the list of assigned (non-delivered) orders for this driver
  // from GET /api/drivers/me/orders. Sets loading state before the call
  // and clears it in the finally block regardless of success or failure.
  Future<void> refreshMyOrders({required String token}) async {
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
      // Filter out orders the driver has already delivered locally. This prevents
      // a race condition where the PATCH request to mark an order DELIVERED hasn't
      // reached the server yet by the time refreshMyOrders runs, causing the
      // order to reappear in the list from the backend response.
      final completedIds = _completedOrders.map((o) => o.id).toSet();
      _orders = parsed.where((o) => !completedIds.contains(o.id)).toList();
      _currentOrder = _orders.isNotEmpty ? _orders.first : null;
      _status = DeliveryStatus.waitingForAcceptance;
      _pickupLocation = null;
      _pickupAddress = null;
    } catch (e) {
      _ordersError = e.toString();
      _orders = [];
      _currentOrder = null;
      _status = DeliveryStatus.waitingForAcceptance;
      _pickupLocation = null;
      _pickupAddress = null;
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

  // Clears the current order and resets all map state (route, markers, position).
  // Called when the driver finishes or cancels a delivery.
  void dismissCurrentOrder() {
    _currentOrder = null;
    _pickupLocation = null;
    _pickupAddress = null;
    _routePoints.clear();
    _polylines.clear();
    _markers.clear();
    _currentDeliveryBoyPosition = null;
    notifyListeners();
  }

  // Removes a specific order from the pending list (swipe-to-dismiss on the
  // orders screen). If the dismissed order was the current one, the current
  // order is reset to the next available order (or null if the list is empty).
  void dismissOrder(OrderModel order) {
    _orders.removeWhere((o) => o.id == order.id);
    if (_currentOrder?.id == order.id) {
      _currentOrder = _orders.isNotEmpty ? _orders.first : null;
      if (_currentOrder == null) {
        _pickupLocation = null;
        _pickupAddress = null;
        _routePoints.clear();
        _polylines.clear();
        _markers.clear();
        _currentDeliveryBoyPosition = null;
      }
    }
    notifyListeners();
  }

  // Sets the selected order and resets all delivery state so the driver
  // starts fresh with each new order detail view.
  void setCurrentOrder(OrderModel order) {
    _currentOrder = order;
    _status = DeliveryStatus.waitingForAcceptance;
    _pickupLocation = null;
    _pickupAddress = null;
    _routePoints.clear();
    _polylines.clear();
    _markers.clear();
    _currentDeliveryBoyPosition = null;
    notifyListeners();
  }

  // Called when the driver taps "Accept". Records the driver's current GPS
  // position as the pickup location and advances the status.
  void acceptOrder({required LatLng pickupLocation}) {
    if (_currentOrder == null) return;

    _pickupLocation = pickupLocation;
    _pickupAddress = 'Current location';

    // Rebuild the current order with the now-known pickup coordinates.
    _currentOrder = _withPickup(
      _currentOrder!,
      pickupLocation: pickupLocation,
      pickupAddress: _pickupAddress!,
    );

    _status = DeliveryStatus.orderAccepted;
    _routePoints.clear();
    _polylines.clear();
    _markers.clear();
    _currentDeliveryBoyPosition = pickupLocation;
    notifyListeners();
  }

  // Stores the decoded route polyline points for drawing on the map.
  void setRoutePoints(List<LatLng> points) {
    _routePoints = points;
    notifyListeners();
  }

  // Called when the driver declines an order.
  void rejectOrder() {
    _status = DeliveryStatus.rejected;
    _routePoints.clear();
    _polylines.clear();
    _markers.clear();
    _currentDeliveryBoyPosition = null;
    notifyListeners();
  }

  // Advances from "accepted" to "picking up" — driver is now en route to pickup.
  void startPickup() {
    _status = DeliveryStatus.pickingUp;
    _currentDeliveryBoyPosition =
        _currentDeliveryBoyPosition ?? _pickupLocation ?? _currentOrder?.pickupLocation;
    notifyListeners();
  }

  // Updates the blue dot on the map as the driver moves.
  void updateDriverPosition(LatLng position) {
    _currentDeliveryBoyPosition = position;
    notifyListeners();
  }

  // Called when the driver arrives at the customer's address.
  void markAsPickedUp() {
    _status = DeliveryStatus.destinationReached;
    notifyListeners();
  }

  // Updates UI immediately, then syncs the status to the backend.
  // Throws if the network call fails so the caller can show an error to the driver.
  Future<void> markPickedUp({required String token}) async {
    final orderId = _currentOrder?.id;
    markAsPickedUp(); // instant UI update
    if (orderId == null || orderId.isEmpty) return;
    try {
      await ApiClient.updateOrderStatus(
        token: token,
        orderId: orderId,
        status: 'PICKED_UP',
      );
    } catch (e) {
      rethrow; // caller shows error snackbar
    }
  }

  // Called when the driver taps "Mark as Delivered".
  void markAdDelivered() {
    _status = DeliveryStatus.markingAsDelivered;
    notifyListeners();
  }

  // Updates UI immediately, then syncs DELIVERED to the backend.
  // Throws if the network call fails so the caller can show an error to the driver.
  Future<void> markDelivered({required String token}) async {
    final orderId = _currentOrder?.id;
    completeDeliveery(); // instant UI update — removes from pending, adds to completed
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

  // Called after the backend confirms the delivery — order is fully complete.
  // Removes the order from the pending list and prepends it to completedOrders
  // so the Completed tab and earnings strip update immediately without a refetch.
  void completeDeliveery() {
    if (_currentOrder != null) {
      _orders.removeWhere((o) => o.id == _currentOrder!.id);
      if (!_completedOrders.any((o) => o.id == _currentOrder!.id)) {
        _completedOrders = [_currentOrder!, ..._completedOrders];
      }
    }
    _status = DeliveryStatus.delivered;
    notifyListeners();
  }

  // Resets the delivery state so the driver is ready to accept a new order.
  void reseDelivery() {
    _status = DeliveryStatus.waitingForAcceptance;
    _routePoints = [];
    _polylines.clear();
    _markers.clear();
    _currentDeliveryBoyPosition = null;
    notifyListeners();
  }
}
