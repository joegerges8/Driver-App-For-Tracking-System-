// When the home map's camera may move on its own.
//
// The inputs — map ready, GPS resolved or failed, orders fetched — arrive in
// no fixed order, and every ordering has to end the same way: the run on
// screen as soon as any of it is known, and the camera untouched afterwards.
// The case that actually happened in the field leads the list: orders arriving
// before the GPS fix left a driver staring at a fallback map for half a
// minute, because the framing waited on GPS for no reason.

import 'package:delivery_boy_app/utils/run_framer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const LatLng _driver = LatLng(33.95, 35.62);
const List<LatLng> _pins = [
  LatLng(33.8938, 35.5018), // Beirut
  LatLng(33.9808, 35.6178), // Jounieh
];

void main() {
  group('orders arrive before the GPS fix — the field case', () {
    test('frames the pins immediately instead of waiting on GPS', () {
      final framer = RunFramer();

      final decision = framer.decide(
        orderPoints: _pins,
        driverLocation: null,
        locationSettled: false,
        ordersFetched: true,
      );

      expect(decision, isNotNull);
      expect(decision!.points, _pins);
      expect(decision.isFinal, isFalse,
          reason: 'the driver still has to be added once GPS lands');
    });

    test('offers that provisional frame only once', () {
      // Every rebuild while GPS keeps the driver waiting asks again; saying
      // yes each time would re-fit the camera over and over under their hands.
      final framer = RunFramer();

      framer.commit(framer.decide(
        orderPoints: _pins,
        driverLocation: null,
        locationSettled: false,
        ordersFetched: true,
      )!);

      expect(
        framer.decide(
          orderPoints: _pins,
          driverLocation: null,
          locationSettled: false,
          ordersFetched: true,
        ),
        isNull,
      );
    });

    test('upgrades once to include the driver when the fix lands', () {
      final framer = RunFramer();
      framer.commit(framer.decide(
        orderPoints: _pins,
        driverLocation: null,
        locationSettled: false,
        ordersFetched: true,
      )!);

      final upgrade = framer.decide(
        orderPoints: _pins,
        driverLocation: _driver,
        locationSettled: true,
        ordersFetched: true,
      );

      expect(upgrade, isNotNull);
      expect(upgrade!.points, contains(_driver));
      expect(upgrade.points, containsAll(_pins));
      expect(upgrade.isFinal, isTrue);

      framer.commit(upgrade);
      expect(framer.done, isTrue);
    });

    test('finalises on the pins alone when GPS fails instead', () {
      final framer = RunFramer();
      framer.commit(framer.decide(
        orderPoints: _pins,
        driverLocation: null,
        locationSettled: false,
        ordersFetched: true,
      )!);

      final decision = framer.decide(
        orderPoints: _pins,
        driverLocation: null,
        locationSettled: true,
        ordersFetched: true,
      );

      expect(decision, isNotNull);
      expect(decision!.isFinal, isTrue,
          reason: 'no fix is coming — there is nothing to wait for');
    });
  });

  group('GPS arrives before the orders', () {
    test('does not frame the driver alone while orders are still loading', () {
      // Framing the driver now is the street-level view the whole feature
      // exists to avoid, thrown away seconds later when the pins land.
      final framer = RunFramer();

      expect(
        framer.decide(
          orderPoints: const [],
          driverLocation: _driver,
          locationSettled: true,
          ordersFetched: false,
        ),
        isNull,
      );
    });

    test('frames driver and pins together in one move when orders land', () {
      final framer = RunFramer();

      final decision = framer.decide(
        orderPoints: _pins,
        driverLocation: _driver,
        locationSettled: true,
        ordersFetched: true,
      );

      expect(decision, isNotNull);
      expect(decision!.points, containsAll([_driver, ..._pins]));
      expect(decision.isFinal, isTrue);
    });
  });

  group('after the final frame', () {
    RunFramer framed() {
      final framer = RunFramer();
      framer.commit(framer.decide(
        orderPoints: _pins,
        driverLocation: _driver,
        locationSettled: true,
        ordersFetched: true,
      )!);
      return framer;
    }

    test('a new order arriving mid-session does not move the camera', () {
      final framer = framed();

      expect(
        framer.decide(
          orderPoints: [..._pins, const LatLng(34.4367, 35.8497)],
          driverLocation: _driver,
          locationSettled: true,
          ordersFetched: true,
        ),
        isNull,
        reason: 'the camera belongs to the driver once the run is framed',
      );
    });

    test('the background poll rebuilding the screen does not either', () {
      final framer = framed();

      expect(
        framer.decide(
          orderPoints: _pins,
          driverLocation: _driver,
          locationSettled: true,
          ordersFetched: true,
        ),
        isNull,
      );
    });
  });

  group('a driver with no orders', () {
    test('is framed on their own position once the empty answer is in', () {
      final framer = RunFramer();

      final decision = framer.decide(
        orderPoints: const [],
        driverLocation: _driver,
        locationSettled: true,
        ordersFetched: true,
      );

      expect(decision, isNotNull);
      expect(decision!.points, [_driver]);
      expect(decision.isFinal, isTrue);
    });

    test('with GPS failed too leaves the camera alone but keeps the door open',
        () {
      final framer = RunFramer();

      expect(
        framer.decide(
          orderPoints: const [],
          driverLocation: null,
          locationSettled: true,
          ordersFetched: true,
        ),
        isNull,
      );
      expect(framer.done, isFalse,
          reason: 'whichever of the two shows up first still gets framed');

      // An order assigned later is the first thing worth looking at, and the
      // camera was never meaningfully placed — so this one does move it.
      expect(
        framer.decide(
          orderPoints: _pins,
          driverLocation: null,
          locationSettled: true,
          ordersFetched: true,
        ),
        isNotNull,
      );
    });
  });

  group('a failed camera animation', () {
    test('is offered again because nothing was committed', () {
      // The Android map throws on newLatLngBounds when it has no size yet; the
      // screen catches that and simply does not commit. The same decision must
      // come back on the next rebuild.
      final framer = RunFramer();

      final first = framer.decide(
        orderPoints: _pins,
        driverLocation: _driver,
        locationSettled: true,
        ordersFetched: true,
      );
      // No commit — the animation failed.
      final second = framer.decide(
        orderPoints: _pins,
        driverLocation: _driver,
        locationSettled: true,
        ordersFetched: true,
      );

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(second!.points, first!.points);
    });
  });
}
