import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';

// One product line of an order: what it is and how many of it the driver is
// carrying. Comes from the backend's orders.line_items column, which the
// webhook copies off the Shopify order.
class OrderLineItem {
  final String title;

  // The variant, when it says something ('500ml', 'Large'). Null for products
  // with a single variant — the backend strips Shopify's "Default Title".
  final String? variantTitle;

  final int quantity;

  const OrderLineItem({
    required this.title,
    this.variantTitle,
    this.quantity = 1,
  });

  // The product as one line: "Tender Coconut (500ml)".
  String get displayName =>
      variantTitle == null || variantTitle!.isEmpty
          ? title
          : '$title ($variantTitle)';

  factory OrderLineItem.fromBackend(Map<String, dynamic> json) {
    final quantity = int.tryParse('${json['quantity']}') ?? 1;
    final variant = (json['variant_title'] ?? '').toString().trim();

    return OrderLineItem(
      title: (json['title'] ?? '').toString().trim(),
      variantTitle: variant.isEmpty ? null : variant,
      quantity: quantity > 0 ? quantity : 1,
    );
  }
}

class OrderModel {
  final String id;
  final String customerName;
  final String customerPhone;
  final String item;
  final int price;

  // The products in this order. Empty for orders imported before the backend
  // stored line items — the order detail screen falls back to showing just the
  // order number in that case.
  final List<OrderLineItem> lineItems;
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

  // True when the customer had already paid online before the order went out
  // for delivery. Unlike isPaid — which flips to true for every order the
  // moment it is delivered — this reflects how the order arrived and never
  // changes afterwards.
  //
  // It exists because the driver collects no cash for these orders, so
  // counting their price as earnings would report the same money twice: once
  // where the customer actually paid, and again in the driver's total.
  final bool isPrepaid;

  // The city extracted from the backend shipping address.
  final String city;

  // The delivery area (Lebanese caza) the backend derived from the city, e.g.
  // 'Keserwan', 'Metn', 'Zahle'. Used for the filter chips on the orders page.
  // Customers type city names freely, so grouping by city produced dozens of
  // one-order chips ("Zahle Madine", "zahle", "Zahlé"); the backend collapses
  // those onto one area. 'Other' when the city could not be placed, empty for
  // orders written before the area column existed.
  final String area;

  // When the order was marked delivered. Null for orders predating the
  // delivered_at column migration. Used in the Shipment tab for grouping
  // history by date and filtering earnings by period.
  final DateTime? deliveredAt;

  OrderModel({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.item,
    required this.price,
    required this.pickupLocation,
    required this.deliveryLocation,
    required this.pickupAddress,
    required this.deliveryAddress,
    this.lineItems = const [],
    this.city = '',
    this.area = '',
    this.isPaid = false,
    this.isPrepaid = false,
    this.deliveredAt,
  });

  // What this order actually contributes to the driver's earnings: the cash
  // collected on delivery, which is nothing for an order paid online.
  int get earnedPrice => isPrepaid ? 0 : price;

  factory OrderModel.fromBackend(Map<String, dynamic> json) {
    final id = json['id'];

    // order_number comes from Shopify's order.name, which already carries the
    // '#' ("#2672"); shopify_order_id, the fallback, does not. Strip whatever
    // leading '#' is there so the label below adds exactly one — otherwise the
    // card reads "Order ##2672".
    final rawOrderNumber = (json['order_number'] ?? json['shopify_order_id'])
        ?.toString()
        .trim()
        .replaceFirst(RegExp(r'^#+'), '');
    final orderNumber =
        rawOrderNumber == null || rawOrderNumber.isEmpty ? null : rawOrderNumber;

    final firstName = (json['customer_first_name'] ?? '').toString().trim();
    final lastName = (json['customer_last_name'] ?? '').toString().trim();
    final customerName =
        [firstName, lastName].where((p) => p.isNotEmpty).join(' ');

    final shippingAddress = (json['shipping_address'] ?? '').toString().trim();
    final city = (json['city'] ?? '').toString().trim();
    final area = (json['area'] ?? '').toString().trim();
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

    // Pickup is always the driver's live location (set when the delivery starts).
    const pickupLocation = LatLng(0.0, 0.0);

    final totalPrice = _asDouble(json['total_price']);

    // Read the financial_status field that comes from the backend database.
    // Shopify sends this field on every order (e.g. 'pending', 'paid', 'voided').
    // For COD orders Shopify sets it to 'pending' initially; our backend later
    // updates it to 'paid' when the driver confirms delivery.
    // We normalise to lowercase so comparisons are case-insensitive.
    final financialStatus = (json['financial_status'] ?? '').toString().toLowerCase();

    final deliveredAt = json['delivered_at'] != null
        ? DateTime.tryParse(json['delivered_at'].toString())
        : null;

    // The backend stores how the order arrived in a dedicated 'prepaid' column,
    // because financial_status is overwritten with 'paid' on delivery.
    // Older backends don't send the column at all; there, an order that reads
    // as paid while still undelivered is the same signal, and a delivered one
    // is assumed COD since that is the normal case.
    final bool isPrepaid = json.containsKey('prepaid')
        ? json['prepaid'] == true || json['prepaid'].toString() == 'true'
        : financialStatus == 'paid' && deliveredAt == null;

    return OrderModel(
      id: id == null ? '' : id.toString(),
      customerName: customerName.isNotEmpty ? customerName : 'Customer',
      customerPhone: (json['customer_phone'] ?? '').toString(),
      item: orderNumber == null ? 'Order' : 'Order #$orderNumber',
      lineItems: _parseLineItems(json['line_items']),
      price: totalPrice == null ? 0 : totalPrice.round(),
      pickupLocation: pickupLocation,
      deliveryLocation: deliveryLocation,
      pickupAddress: 'Current location',
      deliveryAddress:
          deliveryAddress.isNotEmpty ? deliveryAddress : 'Delivery address',
      city: city,
      area: area,
      // isPaid is true only if the backend explicitly says 'paid'.
      // Any other value ('pending', '', null) means the cash has not yet
      // been collected, so we treat the order as unpaid.
      isPaid: financialStatus == 'paid',
      isPrepaid: isPrepaid,
      deliveredAt: deliveredAt,
    );
  }

  // Reads the backend's line_items column. Postgres JSONB normally arrives
  // already decoded as a List, but a driver that hands it back as a JSON string
  // is decoded here rather than dropping the products.
  static List<OrderLineItem> _parseLineItems(dynamic value) {
    dynamic raw = value;

    if (raw is String) {
      if (raw.trim().isEmpty) return const [];
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }

    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((item) => OrderLineItem.fromBackend(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .where((item) => item.title.isNotEmpty)
        .toList();
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
