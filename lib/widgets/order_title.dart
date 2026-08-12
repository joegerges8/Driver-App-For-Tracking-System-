import 'package:delivery_boy_app/models/order_model.dart';
import 'package:flutter/material.dart';

// The order number, and next to it the store the order came from. Several
// stores share this one delivery app, so the number alone does not tell the
// driver who they are collecting the order from.
//
// The number keeps its full width and the store name is what gives way when
// there is not room for both — the number is how the driver looks an order up,
// and a truncated store name still names the store.
//
// Used by every card that heads itself with the order number: the Orders
// screen's pending and completed cards, the Shipment screen's history card,
// and the home screen's swipeable order card.

class OrderTitle extends StatelessWidget {
  final OrderModel order;

  // The order number's size. The home card sets its own — it prints the number
  // in the card body rather than in a grey header, where the surrounding text
  // is a different size. The store name scales with it.
  final double fontSize;

  const OrderTitle({super.key, required this.order, this.fontSize = 15});

  @override
  Widget build(BuildContext context) {
    final store = order.storeName.trim();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Deliberately not Flexible: the order number takes the width it needs
        // and the Flexible store name below takes what is left over. Two
        // flexible children would split the shortfall between them and clip
        // the number too.
        Text(
          order.item, // e.g. "Order #1664"
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: fontSize),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Empty against a backend that does not send the store, and the card
        // then reads exactly as it did before.
        if (store.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '• $store',
              style: TextStyle(
                color: Colors.black54,
                fontSize: fontSize - 2,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
