import 'package:flutter/material.dart';

// Insted of using navigator every time we have create a common navigation helper
class NavigationHelper {
  // Push a new screen
  static void push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }

  // Replace current screen
  static void pushReplacement(BuildContext context, Widget screen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }
}
