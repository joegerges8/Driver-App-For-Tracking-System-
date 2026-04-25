import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum DeliveryStatus {
  waitingForAcceptance,
  orderAccepted,
  pickingUp,
  destinationReached,
  markingAsDelivered,
  delivered,
  rejected,
}

class DeliveryProvider extends ChangeNotifier {
  DeliveryStatus _status = DeliveryStatus.waitingForAcceptance;
  OrderModel? _currentOrder;
  List<OrderModel> _orders = [];
  bool _isLoadingOrders = false;
  String? _ordersError;
  List<LatLng> _routePoints = [];
  LatLng? _currentDeliveryBoyPosition;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  LatLng? _pickupLocation;
  String? _pickupAddress;

  DeliveryStatus get status => _status;
  OrderModel? get currentOrder => _currentOrder;
  List<OrderModel> get orders => List.unmodifiable(_orders);
  bool get isLoadingOrders => _isLoadingOrders;
  String? get ordersError => _ordersError;
  List<LatLng> get routePoints => _routePoints;
  LatLng? get currentDeliveryBoyPosition => _currentDeliveryBoyPosition;
  Set<Polyline> get polylines => _polylines;
  Set<Marker> get markers => _markers;

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

  Future<void> refreshMyOrders({required String token}) async {
    _isLoadingOrders = true;
    _ordersError = null;
    notifyListeners();

    try {
      final list = await ApiClient.getMyOrders(token: token);
      final parsed = <OrderModel>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          parsed.add(OrderModel.fromBackend(item));
        }
      }
      _orders = parsed;
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
      notifyListeners();
    }
  }

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

  void acceptOrder({required LatLng pickupLocation}) {
    if (_currentOrder == null) return;

    _pickupLocation = pickupLocation;
    _pickupAddress = 'Current location';

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

  void setRoutePoints(List<LatLng> points) {
    _routePoints = points;
    notifyListeners();
  }

  void rejectOrder() {
    _status = DeliveryStatus.rejected;
    _routePoints.clear();
    _polylines.clear();
    _markers.clear();
    _currentDeliveryBoyPosition = null;
    notifyListeners();
  }

  void startPickup() {
    _status = DeliveryStatus.pickingUp;
    _currentDeliveryBoyPosition =
        _currentDeliveryBoyPosition ?? _pickupLocation ?? _currentOrder?.pickupLocation;
    notifyListeners();
  }

  void updateDriverPosition(LatLng position) {
    _currentDeliveryBoyPosition = position;
    notifyListeners();
  }

  void markAsPickedUp() {
    _status = DeliveryStatus.destinationReached;
    notifyListeners();
  }

  void markAdDelivered() {
    _status = DeliveryStatus.markingAsDelivered;
    notifyListeners();
  }

  void completeDeliveery() {
    _status = DeliveryStatus.delivered;
    notifyListeners();
  }

  void reseDelivery() {
    _status = DeliveryStatus.waitingForAcceptance;
    _routePoints = [];
    _polylines.clear();
    _markers.clear();
    _currentDeliveryBoyPosition = null;
    notifyListeners();
  }
}
