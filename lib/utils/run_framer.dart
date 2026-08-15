// When the home map's camera may move on its own, and what it frames.
//
// The inputs arrive in no fixed order — the map becomes ready, GPS resolves or
// fails, the orders come back from the network — and the camera has one job
// across all of it: get the whole run on screen as soon as any of it is known,
// and then leave the driver alone.
//
// The bug this class exists to prevent happened once already: the framing was
// woven into the screen's rebuild timing, one of its triggers was lost in a
// refactor, and a driver sat looking at the location provider's San Francisco
// fallback for half a minute until the 30-second poll happened to rebuild the
// screen. Pulling the decision out of the widget makes every ordering of those
// events a plain unit test.
//
// The policy, in full:
//
//  * Orders are never kept waiting for GPS. The pins are usually known within
//    a couple of seconds; a GPS fix can take ten or more, and on a phone with
//    location off it never comes. The moment there are pins, they are framed.
//
//  * When GPS lands after that, the frame is upgraded once to include the
//    driver — that is the one extra camera move allowed, and it happens inside
//    the first seconds of the session, not under a driver already navigating.
//
//  * After the final frame the camera belongs to the driver, permanently. A
//    new order arriving mid-session does not move it: being yanked across the
//    map mid-navigation costs more than the new pin being off-screen, and the
//    new card announcing itself below the map is what says an order arrived.
//
//  * A driver with no orders at all is framed on their own position, once. If
//    nothing is known at all — GPS failed and no orders — the camera stays
//    put, and the first thing that does become known is framed then.

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// One camera move the screen should make now.
class FrameDecision {
  /// What must be on screen together.
  final List<LatLng> points;

  /// True when no automatic camera move may follow this one.
  final bool isFinal;

  const FrameDecision(this.points, {required this.isFinal});
}

class RunFramer {
  bool _done = false;
  bool _framedOrdersProvisionally = false;

  /// Whether the camera has been handed over to the driver for good.
  bool get done => _done;

  /// The camera move warranted by the current state of the world, or null to
  /// leave the camera where it is.
  ///
  /// [driverLocation] is the driver's real position, or null while GPS is
  /// still resolving or after it failed. [locationSettled] says GPS is no
  /// longer being waited on, whichever way it ended. [ordersFetched] says the
  /// first orders response has come back, however it came back — it is what
  /// separates "no pins yet" from "no pins at all".
  ///
  /// The decision is not recorded here: the screen animates the camera, which
  /// can fail (the Android map throws if it has no size yet), and a decision
  /// that failed to run must be offered again. Call [commit] once the move
  /// actually happened.
  FrameDecision? decide({
    required List<LatLng> orderPoints,
    required LatLng? driverLocation,
    required bool locationSettled,
    required bool ordersFetched,
  }) {
    if (_done) return null;

    if (orderPoints.isNotEmpty) {
      if (driverLocation != null) {
        return FrameDecision(
          [driverLocation, ...orderPoints],
          isFinal: true,
        );
      }
      // GPS failed for good: the orders are the whole picture.
      if (locationSettled) {
        return FrameDecision(List.of(orderPoints), isFinal: true);
      }
      // GPS still resolving: frame the pins now rather than make the driver
      // wait on a fix that may take ten seconds — but only once, so the map
      // is not re-fitted on every rebuild while GPS keeps them waiting.
      if (_framedOrdersProvisionally) return null;
      return FrameDecision(List.of(orderPoints), isFinal: false);
    }

    // No pins. Until the first orders response lands this means "not yet",
    // and framing the driver alone now would be a street-level view about to
    // be thrown away.
    if (!ordersFetched) return null;

    // No orders at all: the driver is the whole picture, when known. When GPS
    // failed too there is nothing on earth to frame, and returning null keeps
    // the door open for whichever of the two shows up first.
    if (driverLocation != null) {
      return FrameDecision([driverLocation], isFinal: true);
    }
    return null;
  }

  /// Records that [decision]'s camera move actually ran.
  void commit(FrameDecision decision) {
    if (decision.isFinal) {
      _done = true;
    } else {
      _framedOrdersProvisionally = true;
    }
  }
}
