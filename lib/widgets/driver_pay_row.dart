import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/utils/earnings.dart';
import 'package:flutter/material.dart';

// The "Your Earnings" row: what the store owes this driver in delivery fees.
//
// Shown on the red banner of both the Orders tab and the Shipment tab, under
// the collected total. It lives in one widget so the two screens cannot drift
// apart — they are showing the same fact about the same driver, and a driver
// who reads two different figures for their pay stops trusting either.
//
// The rate itself is not spelled out here: it is a standing arrangement the
// driver already knows, and the delivery count it multiplies is on the same
// banner either way.
class DriverPayRow extends StatelessWidget {
  // How many deliveries the figure covers. On the Shipment tab this is the
  // selected period's count, on the Orders tab it is every completed order.
  final int count;

  const DriverPayRow({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      children: [
        // No icon: the label sits flush with "Total Earned" on the line above,
        // which is the figure it belongs beside.
        Expanded(
          child: Text(
            l10n.yourEarnings,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '\$${driverPayFor(count)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}
