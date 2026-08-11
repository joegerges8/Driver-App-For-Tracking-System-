// Which orders the driver's GPS is flowing for.
//
// This is the rule that decides whether a customer sees a moving map and
// whether the dispatcher sees the driver at all, and it has three inputs that
// disagree with each other often enough to be worth pinning down: what this
// phone started, what the dispatcher started from the dashboard, and what the
// backend still considers open.

import 'package:delivery_boy_app/services/background_location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The SharedPreferences keys the service reads. Duplicated here on purpose:
// they are a storage contract shared with a background isolate, and a test
// that imported them could not notice one of them being renamed out from under
// a driver mid-delivery.
const startedKey = 'bg_active_order_ids';
const onRoadKey = 'bg_backend_on_road_ids';
const openKey = 'bg_backend_open_ids';
const legacyKey = 'bg_active_order_id';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<String>> tracked({
    List<String>? started,
    List<String>? onRoad,
    List<String>? open,
    String? legacy,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (started != null) startedKey: started,
      if (onRoad != null) onRoadKey: onRoad,
      if (open != null) openKey: open,
      if (legacy != null) legacyKey: legacy,
    });

    final ids = await BackgroundLocationService.trackedOrderIds();
    ids.sort();
    return ids;
  }

  group('trackedOrderIds', () {
    test('follows an order the driver started on this phone', () async {
      expect(
        await tracked(started: ['1'], onRoad: [], open: ['1']),
        ['1'],
      );
    });

    test('follows an order the dispatcher marked PICKED_UP', () async {
      // Nothing was tapped on the phone — this is the whole point of the
      // change: the dashboard put the order on the road and the driver's
      // location starts flowing without them opening anything.
      expect(
        await tracked(started: [], onRoad: ['7'], open: ['7']),
        ['7'],
      );
    });

    test('merges both sources without duplicating an order', () async {
      expect(
        await tracked(started: ['1', '2'], onRoad: ['2', '3'], open: ['1', '2', '3']),
        ['1', '2', '3'],
      );
    });

    test('drops an order the backend has closed, even one started here', () async {
      // The driver marked it returned, or the dispatcher did. Either way the
      // backend stops listing it, and the pings must stop with it — this is
      // what kept a finished delivery pinned to the dispatcher's map.
      expect(
        await tracked(started: ['1', '2'], onRoad: [], open: ['2']),
        ['2'],
      );
    });

    test('drops an order the backend closed while it was on the road', () async {
      expect(
        await tracked(started: [], onRoad: ['9'], open: []),
        isEmpty,
      );
    });

    test('keeps streaming when the backend has never been reached', () async {
      // No open list stored at all: first run, or offline since launch. A
      // delivery in progress must not be cut off by a list we do not have.
      expect(
        await tracked(started: ['4'], onRoad: null, open: null),
        ['4'],
      );
    });

    test('tracks nothing for an idle driver', () async {
      expect(
        await tracked(started: [], onRoad: [], open: ['5', '6']),
        isEmpty,
      );
    });

    test('carries a mid-delivery upgrade over from the single-order key', () async {
      // An app updated while the driver was on the road: the pre-batch key is
      // migrated rather than dropped, so their customer's map does not freeze.
      expect(
        await tracked(legacy: '12', open: ['12']),
        ['12'],
      );
    });
  });
}
