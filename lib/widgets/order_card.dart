import 'package:delivery_boy_app/route.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/screen/order_detail_screen.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/utils/utils.dart';
import 'package:delivery_boy_app/widgets/custom_button.dart';
import 'package:delivery_boy_app/widgets/dash_vertical_line.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OrderCard extends StatelessWidget {
  const OrderCard({super.key});

  @override
  Widget build(BuildContext context) {
    final order = context.watch<DeliveryProvider>().currentOrder;
    if (order == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // new order availabe header,
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                Text(
                  "New Order Available",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 15),
                Text(
                  "₹${order.price}",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: buttonMainColor,
                  ),
                ),
                Spacer(),
                GestureDetector(
                  onTap: () {
                    context.read<DeliveryProvider>().dismissCurrentOrder();
                  },
                  child: Icon(Icons.close),
                ),
              ],
            ),
          ),
          // order details,
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // items info
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
                      SizedBox(width: 12),
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                          children: [
                            TextSpan(text: order.item),
                            TextSpan(
                              text: " * ${order.quantity}",
                              style: TextStyle(color: Colors.black38),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                // pickup and delivery
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Column(
                      children: [
                        Icon(
                          Icons.radio_button_checked,
                          color: Colors.black54,
                          size: 20,
                        ),
                        SizedBox(
                          height: 35,
                          child: DashVerticalLine(dashHeight: 6, dashGap: 5,),
                        ),
                      ],
                    ),
                    SizedBox(width: 4),
                    pickupAndDeliveryInfo(
                      "Pickup - ",
                      order.pickupAddress,
                      "You",
                    ),
                  ],
                ),
                // steps 2: Delivery
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      color: buttonMainColor,
                      size: 22,
                    ),
                    SizedBox(width: 5),
                    pickupAndDeliveryInfo(
                      "Delivery - ",
                      order.deliveryAddress,
                      order.customerName,
                    ),
                  ],
                ),
                SizedBox(height: 15),
                // action buttons ,
                SizedBox(
                  width: double.maxFinite,
                  child: CustomButton(
                    title: "View order details",
                    onPressed: () {
                      NavigationHelper.push(context, OrderDetailScreen());
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Expanded pickupAndDeliveryInfo(title, address, subtitle) {
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              Expanded(
                flex: 9,
                child: Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                ),
              ),
            ],
          ),
          Text(subtitle, style: TextStyle(color: Colors.black38)),
        ],
      ),
    );
  }
}
