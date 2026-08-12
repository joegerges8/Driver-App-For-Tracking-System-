// Which orders the driver's per-order GPS is flowing for.
//
// These are the pings the customer's tracking page is built on, so the rule
// they follow is the one a customer would expect: their driver appears once
// the driver has said they are setting off, and not before. Two inputs decide
// it — what this phone started, and what the backend still considers open —
// and only the first can ever start a stream.
//
// The driver's own position, which the dispatcher's map runs on, is a separate
// stream with a separate rule and is deliberately not covered here: it flows
// whenever the app is open, order or no order, and never reaches a customer.

import 'package:delivery_boy_app/services/background_location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The SharedPreferences keys the service reads. Duplicated here on purpose:
// they are a storage contract shared with a background isolate, and a test
// that imported them could not notice one of them being renamed out from under
// a driver mid-delivery.
const startedKey = 'bg_active_order_ids';
const openKey = 'bg_backend_open_ids';
const legacyKey = 'bg_active_order_id';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<String>> tracked({
    List<String>? started,
    List<String>? open,
    String? legacy,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (started != null) startedKey: started,
      if (open != null) openKey: open,
      if (legacy != null) legacyKey: legacy,
    });

    final ids = await BackgroundLocationService.trackedOrderIds();
    ids.sort();
    return ids;
  }

  group('trackedOrderIds', () {
    test('follows an order the driver started on this phone', () async {
      expect(await tracked(started: ['1'], open: ['1']), ['1']);
    });

    test('does NOT follow an order only the dispatcher marked picked up', () async {
      // The order is open and assigned — the dashboard has moved it to
      // PICKED_UP — but the driver has not tapped "Start Delivery". Their
      // customer must not see them on the map yet. This is the whole point of
      // the rule: picking the paperwork up is not setting off.
      expect(await tracked(started: [], open: ['7']), isEmpty);
    });

    test('drops an order the backend has closed, even one started here', () async {
      // The driver marked it returned, or the dispatcher did. Either way the
      // backend stops listing it and the pings must stop with it.
      expect(await tracked(started: ['1', '2'], open: ['2']), ['2']);
    });

    test('follows several started deliveries at once', () async {
      // A batch run: each order has its own customer watching its own page.
      expect(
        await tracked(started: ['1', '2', '3'], open: ['1', '2', '3']),
        ['1', '2', '3'],
      );
    });

    test('keeps streaming when the backend has never been reached', () async {
      // No open list stored at all: first run, or offline since launch. A
      // delivery in progress must not be cut off by a list we do not have.
      expect(await tracked(started: ['4'], open: null), ['4']);
    });

    test('tracks nothing for a driver who has started nothing', () async {
      expect(await tracked(started: [], open: ['5', '6']), isEmpty);
    });

    test('carries a mid-delivery upgrade over from the single-order key', () async {
      // An app updated while the driver was on the road: the pre-batch key is
      // migrated rather than dropped, so their customer's map does not freeze.
      expect(await tracked(legacy: '12', open: ['12']), ['12']);
    });
  });
}
