import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/route.dart';
import 'package:delivery_boy_app/screen/order_detail_screen.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/utils/utils.dart';
import 'package:delivery_boy_app/widgets/custom_button.dart';
import 'package:delivery_boy_app/widgets/dash_vertical_line.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OrderCard extends StatelessWidget {
  final OrderModel order;
  const OrderCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final delivery = context.watch<DeliveryProvider>();
    final isOngoing =
        delivery.hasActiveDelivery && delivery.currentOrder?.id == order.id;

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
                isOngoing ? "Ongoing Order" : "New Order Available",
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
              const Spacer(),
              if (!isOngoing)
                GestureDetector(
                  onTap: () {
                    context.read<DeliveryProvider>().dismissOrder(order);
                  },
                  child: const Icon(Icons.close),
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
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                        children: [
                          TextSpan(text: order.item),
                          TextSpan(
                            text: " * ${order.quantity}",
                            style: const TextStyle(color: Colors.black38),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Pickup row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      const Icon(
                        Icons.radio_button_checked,
                        color: Colors.black54,
                        size: 20,
                      ),
                      SizedBox(
                        height: 35,
                        child: DashVerticalLine(dashHeight: 6, dashGap: 5),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  _locationInfo("Pickup - ", order.pickupAddress, "You"),
                ],
              ),
              // Delivery row
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
                      "Delivery - ", order.deliveryAddress, order.customerName),
                ],
              ),
              const SizedBox(height: 15),
              // Action button
              SizedBox(
                width: double.maxFinite,
                child: CustomButton(
                  title: isOngoing
                      ? "View ongoing order"
                      : "View order details",
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

  Expanded _locationInfo(String title, String address, String subtitle) {
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
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              Expanded(
                flex: 9,
                child: Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 15),
                ),
              ),
            ],
          ),
          Text(subtitle, style: const TextStyle(color: Colors.black38)),
        ],
      ),
    );
  }
}
