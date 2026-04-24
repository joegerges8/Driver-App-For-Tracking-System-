import 'dart:math';
import 'package:delivery_boy_app/provider/current_location_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/route.dart';
import 'package:delivery_boy_app/screen/delivery_map_screen.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/utils/utils.dart';
import 'package:delivery_boy_app/widgets/custom_button.dart';
import 'package:delivery_boy_app/widgets/dash_vertical_line.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final order = context.watch<DeliveryProvider>().currentOrder;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text("Order Details"),
        centerTitle: false,
      ),
      body: order == null
          ? const Center(child: Text('No order selected'))
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // customer information
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 20, top: 12),
                    child: Text(
                      "Customer Information",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: CircleAvatar(
                      radius: 25,
                      backgroundImage: NetworkImage(
                        "https://images.pexels.com/photos/771742/pexels-photo-771742.jpeg?auto=compress&cs=tinysrgb&dpr=1&w=500",
                      ),
                    ),
                    title: Text(
                      order.customerName,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text("Delivery • ${order.customerPhone}"),
                    trailing: CircleAvatar(
                      backgroundColor: iconColor,
                      child: Icon(Icons.phone, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            // order summary
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Order Summary",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 7),
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            tenderCoconut,
                            height: 50,
                            width: 50,
                            fit: BoxFit.cover,
                          ),
                        ),
                        SizedBox(width: 5),
                        Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                            children: [
                              TextSpan(text: "${order.item} "),
                              TextSpan(
                                text: " * ${order.quantity}",
                                style: TextStyle(color: Colors.black38),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.credit_card_outlined),
                        SizedBox(width: 10),
                        Text(
                          "₹${order.price}",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 10),
                        Icon(Icons.check_circle_sharp, color: iconColor),
                        SizedBox(width: 10),
                        Text(
                          "Paid",
                          style: TextStyle(
                            fontSize: 16,
                            color: iconColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            // Pickup and delivery locations
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    // setp 1: Pickup.
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
                              height: 80,
                              child: DashVerticalLine(
                                dashHeight: 5,
                                dashGap: 5,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Pickup Location",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                order.pickupAddress,
                                style: TextStyle(fontSize: 13),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "You",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: iconColor,
                          child: Icon(
                            Icons.phone,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        SizedBox(width: 20),
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.red.shade50,
                          child: Transform.rotate(
                            angle: -pi / 4,
                            child: Icon(
                              Icons.send,
                              size: 18,
                              color: buttonMainColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // step 2: delivery
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          color: buttonMainColor,
                          size: 22,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Delivery Location",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                order.deliveryAddress,
                                style: TextStyle(fontSize: 13),
                              ),
                              SizedBox(height: 2),
                              Text(
                                order.customerName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.red.shade50,
                          child: Transform.rotate(
                            angle: -pi / 4,
                            child: Icon(
                              Icons.send,
                              size: 18,
                              color: buttonMainColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Consumer<DeliveryProvider>(
        builder: (context, provider, child) {
          return Container(
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              child: provider.status == DeliveryStatus.orderAccepted
                  ? CustomButton(
                      title: "Start Pickup",
                      onPressed: () {
                        // move delivery boy to pickup location and navigate to map
                        final loc = context.read<CurrentLocationProvider>();
                        if (loc.isLoading) {
                          showAppSnackbar(
                            context: context,
                            type: SnackbarType.success,
                            description:
                                'Getting your current location… try again in a moment.',
                          );
                          return;
                        }
                        if (loc.errorMessage.isNotEmpty) {
                          showAppSnackbar(
                            context: context,
                            type: SnackbarType.error,
                            description: loc.errorMessage,
                          );
                          return;
                        }

                        final delivery = context.read<DeliveryProvider>();
                        delivery.updateDriverPosition(loc.currentLocation);
                        delivery.startPickup();
                        NavigationHelper.pushReplacement(
                          context,
                          DeliveryMapScreen(),
                        );
                      },
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: CustomButton(
                            color: declineOrder,
                            textColor: Colors.black54,
                            title: "Decline Order",
                            onPressed: () {
                              context.read<DeliveryProvider>().rejectOrder();
                              Navigator.pop(context);
                              showAppSnackbar(
                                context: context,
                                type: SnackbarType.error,
                                description: "Order is not accepted",
                              );
                            },
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: CustomButton(
                            title: "Accept Order",
                            onPressed: () {
                              final loc = context.read<CurrentLocationProvider>();
                              if (loc.isLoading) {
                                showAppSnackbar(
                                  context: context,
                                  type: SnackbarType.success,
                                  description: 'Getting your current location… try again in a moment.',
                                );
                                return;
                              }
                              if (loc.errorMessage.isNotEmpty) {
                                showAppSnackbar(
                                  context: context,
                                  type: SnackbarType.error,
                                  description: loc.errorMessage,
                                );
                                return;
                              }

                              context
                                  .read<DeliveryProvider>()
                                  .acceptOrder(pickupLocation: loc.currentLocation);
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}
