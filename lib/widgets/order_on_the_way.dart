import 'package:delivery_boy_app/models/order_model.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/widgets/custom_button.dart';
import 'package:flutter/material.dart';

class OrderOnTheWay extends StatelessWidget {
  final OrderModel order;
  final DeliveryStatus status;
  final VoidCallback? onButtonPressed;
  const OrderOnTheWay({
    super.key,
    required this.order,
    required this.status,
    required this.onButtonPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 10),
          Container(
            height: 5,
            width: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: Colors.black26,
            ),
          ),
          // pickup location row with icon, text and phone button
          ListTile(
            leading: Icon(_getPickupIcon(), color: _getPickupIconColor()),
            title: Text(
              "Pickup Location",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Text(order.pickupAddress),
            trailing: CircleAvatar(
              radius: 18,
              backgroundColor: iconColor,
              child: Icon(Icons.phone, color: Colors.white),
            ),
          ),

          // delivery location row with icon text and phone button
          ListTile(
            leading: Icon(_getDeliveryiIcon(), color: _getDeliveryIconColor()),
            title: Text(
              "Delivery - ${order.customerName}",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Text(order.deliveryAddress),
            trailing: CircleAvatar(
              radius: 18,
              backgroundColor: iconColor,
              child: Icon(Icons.phone, color: Colors.white),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(20),
            child: SizedBox(width: double.maxFinite, child: _buttonStyle()),
          ),
        ],
      ),
    );
  }

  // returns appropriate button widget basee on current delivery status
  // difference button type for mark as destination reached button and same button stye for remaining all, only change the icon and color
  Widget _buttonStyle() {
    switch (status) {
      case DeliveryStatus.destinationReached:
        // special button style with arrow icon when destination is reached
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: GestureDetector(
            onTap: _isButtonEnabled() ? (onButtonPressed ?? () {}) : () {},
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: pickedUpColor.withAlpha(170),
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(30),
                      ),
                    ),
                    child: Icon(Icons.arrow_forward, color: Colors.white),
                  ),
                ),
                Expanded(
                  flex: 17,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: _getButtonColor(),
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(30),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _getButtonTitle(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      default:
        // standard button for all other states
        return CustomButton(
          title: _getButtonTitle(),
          onPressed: _isButtonEnabled() ? (onButtonPressed ?? () {}) : () {},
          color: _getButtonColor(),
        );
    }
  }

  // returns button color based on delivery status
  Color _getButtonColor() {
    switch (status) {
      case DeliveryStatus.pickingUp:
        return pickedUpColor;
      case DeliveryStatus.destinationReached:
        return pickedUpColor;
      case DeliveryStatus.markingAsDelivered:
        return buttonMainColor;
      case DeliveryStatus.delivered:
        return Colors.red.withAlpha(150);
      default:
        return buttonMainColor;
    }
  }

  // returns button text based on delivery status
  String _getButtonTitle() {
    switch (status) {
      case DeliveryStatus.pickingUp:
        return "Mark as Picked Up";
      case DeliveryStatus.destinationReached:
        return "Mark as Destination Reached";
      case DeliveryStatus.markingAsDelivered:
        return "Mark as Delivered";
      case DeliveryStatus.delivered:
        return "Marking as Delivered...";
      default:
        return "Start Pickup";
    }
  }

  // returns whether button should be enabled/clickable
  bool _isButtonEnabled() {
    switch (status) {
      case DeliveryStatus.delivered:
        return false;
      default:
        return true;
    }
  }

  // returns appropriate icon from pickup location base on status
  IconData _getPickupIcon() {
    switch (status) {
      case DeliveryStatus.destinationReached:
      case DeliveryStatus.markingAsDelivered:
      case DeliveryStatus.delivered:
        return Icons.check_circle;
      default:
        return Icons.radio_button_checked;
    }
  }

  // return color for pickup icon based on status
  Color _getPickupIconColor() {
    switch (status) {
      case DeliveryStatus.destinationReached:
      case DeliveryStatus.markingAsDelivered:
      case DeliveryStatus.delivered:
        return buttonMainColor;
      default:
        return Colors.grey;
    }
  }

  // returns appropriate icon for pickup/delivery location based on status
  IconData _getDeliveryiIcon() {
    switch (status) {
      case DeliveryStatus.markingAsDelivered:
      case DeliveryStatus.delivered:
        // check only after "mark as destination reached " is clicked
        return Icons.check_circle;
      default:
        // location pin until user clicks "mark as destination reached"
        return Icons.location_on_outlined;
    }
  }

  // returns color for pickup/delivery icon based on status
  Color _getDeliveryIconColor() {
    switch (status) {
      case DeliveryStatus.markingAsDelivered:
      case DeliveryStatus.delivered:
        // check(completed icon) only after "mark as destination reached " is clicked
        return buttonMainColor;
      default:
        // red location pin until user clicks "mark as destination reached"
        return Colors.red;
    }
  }
}
