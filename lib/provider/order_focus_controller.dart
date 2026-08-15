// Which order the driver just asked to see.
//
// The home screen shows the same run twice — as pins on the map and as cards
// underneath — and until now the two halves did not know about each other. A
// driver could see a pin sitting somewhere awkward and have no way to find out
// which order it was except swiping the cards and reading addresses.
//
// This is the one thing they need to say to each other: tapping a pin names an
// order, and the cards bring that order to the front. It is deliberately a
// request rather than a piece of state — nothing reads "the focused order"
// afterwards, and the cards are free to move on as soon as the driver swipes,
// without having to report back.
//
// Tapping the same pin twice notifies twice. That is the point: after swiping
// away, tapping that pin again has to bring its card back, and a controller
// that only fired on a change of value would sit silent the second time.

import 'package:flutter/foundation.dart';

class OrderFocusController extends ChangeNotifier {
  String? _orderId;

  /// The order last asked for, or null if nothing has been asked for yet.
  String? get orderId => _orderId;

  /// Asks whoever is listening to bring [orderId] in front of the driver.
  void focus(String orderId) {
    _orderId = orderId;
    notifyListeners();
  }
}
