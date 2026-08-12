import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/route.dart';
import 'package:delivery_boy_app/screen/order_detail_screen.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/utils/phone.dart';
import 'package:delivery_boy_app/utils/utils.dart';
import 'package:delivery_boy_app/widgets/custom_button.dart';
import 'package:delivery_boy_app/widgets/order_title.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OrderCard extends StatelessWidget {
  final OrderModel order;
  const OrderCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final delivery = context.watch<DeliveryProvider>();
    final isOngoing = delivery.isDelivering(order.id);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Row(
            children: [
              Text(
                isOngoing ? l10n.ongoingOrder : l10n.newOrderAvailable,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 15),
              Text(
                "\$${order.price}",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: buttonMainColor,
                ),
              ),
            ],
          ),
        ),
        // Details
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Item info
              Material(
                color: Colors.white,
                elevation: 1,
                shadowColor: Colors.black26,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.brown[100],
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: NetworkImage(tenderCoconut),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // The order number and the store it came from. A "* 1"
                    // used to trail the number, printed from an
                    // OrderModel.quantity field that was hardcoded to 1 and
                    // never reflected what was in the order; the real
                    // per-product counts live on the order detail screen.
                    Expanded(child: OrderTitle(order: order)),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Delivery row.
              // The pickup row above it is gone: it always read "Current
              // location / You", which tells the driver nothing they do not
              // already know, so only the destination is shown.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    color: buttonMainColor,
                    size: 22,
                  ),
                  const SizedBox(width: 5),
                  _locationInfo(
                    l10n.deliveryLabel,
                    order.deliveryAddress,
                    order.customerName,
                    order.customerPhone,
                  ),
                ],
              ),
              const SizedBox(height: 15),
              // Action button
              SizedBox(
                width: double.maxFinite,
                child: CustomButton(
                  title: isOngoing
                      ? l10n.viewOngoingOrder
                      : l10n.viewOrderDetails,
                  onPressed: () {
                    context.read<DeliveryProvider>().setCurrentOrder(order);
                    NavigationHelper.push(context, const OrderDetailScreen());
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Expanded _locationInfo(
    String title,
    String address,
    String subtitle,
    String phone,
  ) {
    // Without the +961 a store may have saved — see displayPhone. The raw
    // number is what the detail screen dials; this is only how it reads.
    final phoneText = displayPhone(phone);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Expanded(
                flex: 9,
                child: Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          Text(subtitle, style: const TextStyle(color: Colors.black38)),
          if (phoneText.isNotEmpty)
            Text(
              phoneText,
              style: const TextStyle(
                color: Colors.black38,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}
