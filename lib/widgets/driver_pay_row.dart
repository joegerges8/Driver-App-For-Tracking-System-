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
// Every completed delivery earns the flat fee in utils/earnings.dart, so the
// caption spells the sum out ("3 × $2 per delivery") and the driver can check
// the figure against the deliveries they remember making.
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
        const Icon(
          Icons.account_balance_wallet_outlined,
          color: Colors.white70,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.yourEarnings,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                l10n.earningsPerDelivery(count, driverFeePerDelivery),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
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
