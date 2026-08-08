import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/current_location_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/utils/utils.dart';
import 'package:delivery_boy_app/widgets/custom_button.dart';
import 'package:delivery_boy_app/widgets/dash_vertical_line.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final order = context.watch<DeliveryProvider>().currentOrder;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.orderDetails),
        centerTitle: false,
      ),
      body: order == null
          ? Center(child: Text(l10n.noOrderSelected))
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
                      l10n.customerInformation,
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
                    subtitle: Text('${l10n.delivery} • ${order.customerPhone}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => launchUrl(
                            Uri(scheme: 'tel', path: order.customerPhone),
                          ),
                          child: CircleAvatar(
                            backgroundColor: iconColor,
                            child: Icon(Icons.phone, color: Colors.white),
                          ),
                        ),
                        SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://wa.me/${order.customerPhone.replaceAll(RegExp(r'[^0-9]'), '')}',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: CircleAvatar(
                            backgroundColor: const Color(0xFF25D366),
                            child: FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
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
                      l10n.orderSummary,
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
                          "\$${order.price}",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 10),
                        // Dynamic payment status badge.
                        // Previously this was hardcoded to always show "Paid",
                        // which was misleading for COD orders where the customer
                        // has not yet handed over cash.
                        //
                        // Now we read order.isPaid (a bool on OrderModel) and:
                        //   - If false → orange empty circle + "Unpaid (COD)"
                        //     This is the default for every new incoming order.
                        //   - If true  → green checkmark + "Paid"
                        //     This is set automatically when the driver taps
                        //     "Mark as Delivered" (cash has been collected).
                        // A prepaid order (paid online before dispatch) is
                        // shown as its own state rather than plain "Paid":
                        // the driver must not ask for cash, and the amount is
                        // excluded from the earnings totals for that reason.
                        Icon(
                          order.isPaid ? Icons.check_circle_sharp : Icons.radio_button_unchecked,
                          color: order.isPaid ? iconColor : Colors.orange,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            order.isPrepaid
                                ? l10n.prepaidNoCash
                                : (order.isPaid ? l10n.paid : l10n.unpaidCod),
                            style: TextStyle(
                              fontSize: 16,
                              color: order.isPaid ? iconColor : Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
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
                                l10n.pickupLocation,
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
                                l10n.you,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
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
                                l10n.deliveryLocation,
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
                        // The "navigate here" button used to sit here. Orders
                        // carry a written address but no customer coordinates,
                        // so it had nothing to navigate to.
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // The whole delivery flow lives in this one bar:
      //   • Before starting  → a single "Start Delivery" button.
      //   • After starting   → "Mark as Returned" / "Mark as Delivered".
      // There is no accept/decline step, no pickup step and no in-app map:
      // the dispatcher flips the order to PICKED_UP from the dashboard, which
      // is what reveals the driver on the customer's tracking page. The GPS
      // itself starts flowing as soon as "Start Delivery" is tapped.
      bottomNavigationBar: order == null
          ? null
          : Consumer<DeliveryProvider>(
              builder: (context, provider, child) {
                final isDelivering = provider.isDelivering(order.id);

                return Container(
                  color: Colors.white,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                    child: isDelivering
                        ? Row(
                            children: [
                              Expanded(
                                child: CustomButton(
                                  color: declineOrder,
                                  textColor: Colors.black54,
                                  title: l10n.markAsReturned,
                                  onPressed: () => _finishDelivery(
                                    context,
                                    returned: true,
                                  ),
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: CustomButton(
                                  title: l10n.markAsDelivered,
                                  onPressed: () => _finishDelivery(
                                    context,
                                    returned: false,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : CustomButton(
                            title: l10n.startDelivery,
                            onPressed: () => _startDelivery(context),
                          ),
                  ),
                );
              },
            ),
    );
  }

  // Starts the delivery: stamps the driver's current position as the pickup
  // point and kicks off background GPS sharing for this order. The screen
  // stays where it is — only the buttons at the bottom change.
  void _startDelivery(BuildContext context) {
    final loc = context.read<CurrentLocationProvider>();
    if (loc.isLoading) {
      showAppSnackbar(
        context: context,
        type: SnackbarType.success,
        description: context.l10n.gettingLocationRetry,
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
        .startDelivery(driverLocation: loc.currentLocation);

    showAppSnackbar(
      context: context,
      type: SnackbarType.success,
      description: context.l10n.deliveryStartedSharing,
    );
  }

  // Closes out the order as either delivered or returned, then goes back to
  // the orders list. The provider updates local state straight away and syncs
  // the status to the backend in the background; a failed sync surfaces as an
  // error snackbar rather than blocking the driver.
  Future<void> _finishDelivery(
    BuildContext context, {
    required bool returned,
  }) async {
    final l10n = context.l10n;
    final provider = context.read<DeliveryProvider>();
    final token = context.read<AuthProvider>().token ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final update = returned
        ? provider.markReturned(token: token)
        : provider.markDelivered(token: token);

    showAppSnackbar(
      context: context,
      type: SnackbarType.success,
      description: returned
          ? l10n.orderMarkedReturned
          : l10n.orderMarkedDelivered,
    );

    if (navigator.canPop()) navigator.pop();

    try {
      await update;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.statusSyncFailed('$e')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
