import 'package:google_maps_flutter/google_maps_flutter.dart';

class OrderModel {
  final String id;
  final String customerName;
  final String customerPhone;
  final String item;
  final int quantity;
  final int price;
  final LatLng pickupLocation;
  final LatLng deliveryLocation;
  final String pickupAddress;
  final String deliveryAddress;

  // Tracks whether the customer has paid for this order.
  // For COD (Cash on Delivery) orders, this starts as false when the order
  // arrives from Shopify and becomes true only when the driver marks delivery
  // complete (at which point cash has been collected). Defaults to false so
  // that any new order is treated as unpaid until confirmed otherwise.
  final bool isPaid;

  // The city extracted from the backend shipping address. Used in the
  // Pending tab's city filter chips.
  final String city;

  // When the order was marked delivered. Null for orders predating the
  // delivered_at column migration. Used in the Shipment tab for grouping
  // history by date and filtering earnings by period.
  final DateTime? deliveredAt;

  OrderModel({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.item,
    required this.quantity,
    required this.price,
    required this.pickupLocation,
    required this.deliveryLocation,
    required this.pickupAddress,
    required this.deliveryAddress,
    this.city = '',
    this.isPaid = false,
    this.deliveredAt,
  });

  factory OrderModel.fromBackend(Map<String, dynamic> json) {
    final id = json['id'];
    final orderNumber = json['order_number'] ?? json['shopify_order_id'];

    final firstName = (json['customer_first_name'] ?? '').toString().trim();
    final lastName = (json['customer_last_name'] ?? '').toString().trim();
    final customerName =
        [firstName, lastName].where((p) => p.isNotEmpty).join(' ');

    final shippingAddress = (json['shipping_address'] ?? '').toString().trim();
    final city = (json['city'] ?? '').toString().trim();
    final country = (json['country'] ?? '').toString().trim();
    final deliveryAddress = [shippingAddress, city, country]
        .where((p) => p.isNotEmpty)
        .join(', ');

    // 1. Try explicit lat/lng columns first.
    LatLng? deliveryLocation = _tryLatLng(
      _asDouble(json['customer_latitude']),
      _asDouble(json['customer_longitude']),
    );

    // 2. Fall back to parsing the Google Maps link stored by the webhook.
    deliveryLocation ??= _parseGoogleMapsLink(
      json['google_maps_link']?.toString(),
    );

    // 3. Last resort: sentinel (0,0) — the map screen skips routing for this.
    deliveryLocation ??= const LatLng(0.0, 0.0);

    // Pickup is always the driver's live location (set when accepting).
    const pickupLocation = LatLng(0.0, 0.0);

    final totalPrice = _asDouble(json['total_price']);

    // Read the financial_status field that comes from the backend database.
    // Shopify sends this field on every order (e.g. 'pending', 'paid', 'voided').
    // For COD orders Shopify sets it to 'pending' initially; our backend later
    // updates it to 'paid' when the driver confirms delivery.
    // We normalise to lowercase so comparisons are case-insensitive.
    final financialStatus = (json['financial_status'] ?? '').toString().toLowerCase();

    return OrderModel(
      id: id == null ? '' : id.toString(),
      customerName: customerName.isNotEmpty ? customerName : 'Customer',
      customerPhone: (json['customer_phone'] ?? '').toString(),
      item: orderNumber == null ? 'Order' : 'Order #$orderNumber',
      quantity: 1,
      price: totalPrice == null ? 0 : totalPrice.round(),
      pickupLocation: pickupLocation,
      deliveryLocation: deliveryLocation,
      pickupAddress: 'Current location',
      deliveryAddress:
          deliveryAddress.isNotEmpty ? deliveryAddress : 'Delivery address',
      city: city,
      // isPaid is true only if the backend explicitly says 'paid'.
      // Any other value ('pending', '', null) means the cash has not yet
      // been collected, so we treat the order as unpaid.
      isPaid: financialStatus == 'paid',
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'].toString())
          : null,
    );
  }

  // Returns a LatLng only when both values are present and geographically sane.
  static LatLng? _tryLatLng(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    if (!_validCoords(lat, lng)) return null;
    return LatLng(lat, lng);
  }

  // A coordinate pair is valid when both values are non-trivially non-zero and
  // within geographic bounds. lat=0 or lng=0 almost always means missing data.
  static bool _validCoords(double lat, double lng) {
    return lat.abs() > 0.001 &&
        lng.abs() > 0.001 &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
  }

  // Extracts coordinates from common Google Maps URL formats:
  //   https://maps.google.com/?q=34.1234,35.6789
  //   https://www.google.com/maps/@34.1234,35.6789,15z
  //   https://maps.google.com/maps?q=loc:34.1234,35.6789
  static LatLng? _parseGoogleMapsLink(String? url) {
    if (url == null || url.isEmpty) return null;

    // @lat,lng pattern (appears in most full Google Maps URLs)
    final atMatch =
        RegExp(r'@(-?\d+\.?\d*),(-?\d+\.?\d*)').firstMatch(url);
    if (atMatch != null) {
      final lat = double.tryParse(atMatch.group(1)!);
      final lng = double.tryParse(atMatch.group(2)!);
      if (lat != null && lng != null && _validCoords(lat, lng)) {
        return LatLng(lat, lng);
      }
    }

    // ?q=lat,lng or ?q=loc:lat,lng pattern
    final qMatch =
        RegExp(r'[?&]q=(?:loc:)?(-?\d+\.?\d*),(-?\d+\.?\d*)').firstMatch(url);
    if (qMatch != null) {
      final lat = double.tryParse(qMatch.group(1)!);
      final lng = double.tryParse(qMatch.group(2)!);
      if (lat != null && lng != null && _validCoords(lat, lng)) {
        return LatLng(lat, lng);
      }
    }

    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }
}
