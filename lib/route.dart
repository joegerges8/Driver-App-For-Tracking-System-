import 'package:flutter/material.dart';

// Insted of using navigator every time we have create a common navigation helper
class NavigationHelper {
  // Handed to MaterialApp so code with no BuildContext — AuthProvider ending
  // a session the backend has stopped accepting — can still put the login
  // screen up. Every screen keeps using the context-based helpers below.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // Drops every route and lands on [screen]. What a session ending needs:
  // the main screen was pushed over AuthGate on login, so nothing short of
  // clearing the stack gets the driver off it.
  static void resetTo(Widget screen) {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  // Push a new screen
  static void push(BuildContext context, Widget screen) { // go to new screen
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }

  // Replace current screen
  static void pushReplacement(BuildContext context, Widget screen) { //go to screen and remove previous
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }
}
