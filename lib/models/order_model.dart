import 'dart:convert';

import 'package:delivery_boy_app/utils/address.dart';
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
  // Stands in for a customer whose order carries no name at all. Kept as a
  // constant rather than a bare literal because it is a placeholder, not a
  // name, and anything addressing the customer directly — the WhatsApp
  // message — has to recognise it and greet them without it.
  static const String unknownCustomerName = 'Customer';

  final String id;
  final String customerName;
  final String customerPhone;
  final String item;

  // The order number on its own — '2672', no '#' and no 'Order' in front of it.
  // `item` above is the display label built from this ('Order #2672') and reads
  // wrong mid-sentence, which is what the WhatsApp message needs. Empty for an
  // order the backend sent with neither an order_number nor a shopify_order_id.
  final String orderNumber;

  // Which shop this order belongs to, for the driver's message to the customer:
  // several stores share one delivery app, so "your order" on its own leaves
  // the customer guessing who is at the door. Comes from the stores table via
  // the driver order endpoints; empty against a backend that does not send it
  // yet, and the message then simply omits the shop.
  final String storeName;

  final int price;

  // The products in this order. Empty for orders imported before the backend
  // stored line items — the order detail screen falls back to showing just the
  // order number in that case.
  final List<OrderLineItem> lineItems;

  // Instructions written on the order in the Shopify admin — "leave with the
  // concierge", "call before arriving". Comes from the backend's orders.note
  // column, which mirrors the Shopify order note. Empty when the order carries
  // no note, and the detail screen then shows no note card at all.
  final String note;

  // What the driver themselves wrote about this order — "nobody home, tried
  // 3pm", "gate code 4412". Unlike note above, the app writes this one: it is
  // saved to the backend's orders.driver_note column and never goes to
  // Shopify. Empty until the driver writes something.
  final String driverNote;
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

  // Where the backend thinks this order is in its lifecycle: 'UNFULFILLED',
  // 'ASSIGNED', 'PICKED_UP', 'OUT_FOR_DELIVERY'. The app has its own local
  // notion of a delivery being under way (DeliveryProvider's status map), but
  // that one only knows what happened on this phone — the dispatcher marking
  // an order PICKED_UP from the dashboard is invisible to it. This field is
  // what carries that decision to the app, and it is what starts the driver's
  // location sharing without them having to open anything. Empty against a
  // backend that does not send the column.
  final String orderStatus;

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
    this.orderNumber = '',
    this.storeName = '',
    this.lineItems = const [],
    this.note = '',
    this.driverNote = '',
    this.city = '',
    this.area = '',
    this.isPaid = false,
    this.isPrepaid = false,
    this.deliveredAt,
    this.orderStatus = '',
  });

  // Returns a copy with only the named fields changed. OrderModel is immutable
  // — every field is final — so an update means building a new instance, and
  // listing all seventeen fields by hand at each call site is how a field ends
  // up silently reset to its default when a new one is added.
  OrderModel copyWith({
    LatLng? pickupLocation,
    String? pickupAddress,
    String? driverNote,
    bool? isPaid,
    DateTime? deliveredAt,
  }) {
    return OrderModel(
      id: id,
      customerName: customerName,
      customerPhone: customerPhone,
      item: item,
      orderNumber: orderNumber,
      storeName: storeName,
      price: price,
      lineItems: lineItems,
      note: note,
      driverNote: driverNote ?? this.driverNote,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      deliveryLocation: deliveryLocation,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      deliveryAddress: deliveryAddress,
      city: city,
      area: area,
      isPaid: isPaid ?? this.isPaid,
      // isPrepaid describes how the order arrived, so nothing that happens
      // during the delivery may change it — that is the distinction the
      // earnings totals rely on. It is deliberately not a parameter here.
      isPrepaid: isPrepaid,
      // The moment the delivery was completed. Passed in when the driver marks
      // an order delivered on this phone, so the finished order carries a
      // completion time before the backend has confirmed one — that timestamp
      // is what puts it in today's Done tab and takes it back out at midnight.
      deliveredAt: deliveredAt ?? this.deliveredAt,
      orderStatus: orderStatus,
    );
  }

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
    // The country the backend stores is deliberately left out: every order is
    // delivered inside Lebanon, so the word only ate room on the card. The
    // town is left out too when the address already names it — see
    // buildDeliveryAddress, which is where that rule is written down and
    // tested. Note that only the display drops these: the city and area
    // fields below keep what the backend sent, since the area filter on the
    // orders screen is built from them.
    final deliveryAddress = buildDeliveryAddress(shippingAddress, city);

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
      customerName:
          customerName.isNotEmpty ? customerName : unknownCustomerName,
      customerPhone: (json['customer_phone'] ?? '').toString(),
      item: orderNumber == null ? 'Order' : 'Order #$orderNumber',
      orderNumber: orderNumber ?? '',
      storeName: _parseStoreName(json),
      lineItems: _parseLineItems(json['line_items']),
      // Null for orders from a backend without the note column, and for the
      // many orders that simply have no note.
      note: (json['note'] ?? '').toString().trim(),
      driverNote: (json['driver_note'] ?? '').toString().trim(),
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
      orderStatus:
          (json['order_status'] ?? '').toString().trim().toUpperCase(),
    );
  }

  // The shop this order came from, as the customer would recognise it.
  //
  // store_name is what the merchant calls themselves in Shopify, but the column
  // is nullable — a store installed before the backend started recording it has
  // none. The shop domain is the next best thing, minus the '.myshopify.com'
  // that would only confuse a customer; the backend uses the same fallback when
  // it greets a store admin. Empty when the backend sends neither, which is the
  // case for any release predating the store join on the driver endpoints.
  static String _parseStoreName(Map<String, dynamic> json) {
    final storeName = (json['store_name'] ?? '').toString().trim();
    if (storeName.isNotEmpty) return storeName;

    final shopDomain = (json['shop_domain'] ?? '').toString().trim();
    if (shopDomain.isEmpty) return '';

    return shopDomain.replaceFirst(RegExp(r'\.myshopify\.com$'), '');
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
