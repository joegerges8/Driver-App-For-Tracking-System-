// The outbox that carries a delivery marked with no signal.
//
// The promise these lock down is the one the driver assumes when they tap
// "Mark as Delivered" in a basement: the app has taken the answer, and the
// dashboard gets it whenever the phone next reaches the server — even if that
// is after the app has been killed and reopened.

import 'package:delivery_boy_app/services/pending_status_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

PendingStatusChange _change(
  String orderId, {
  String status = 'DELIVERED',
  DateTime? at,
}) =>
    PendingStatusChange(
      orderId: orderId,
      status: status,
      occurredAt: at ?? DateTime(2026, 8, 14, 18, 30),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PendingStatusQueue', () {
    test('starts empty', () async {
      expect(await PendingStatusQueue.load(), isEmpty);
    });

    test('keeps a queued outcome across a fresh read of the store', () async {
      await PendingStatusQueue.enqueue(_change('11'));

      // A second load is what the app does after being killed and relaunched:
      // nothing is held in memory, everything comes back off disk.
      final restored = await PendingStatusQueue.load();

      expect(restored.length, 1);
      expect(restored.single.orderId, '11');
      expect(restored.single.status, 'DELIVERED');
      expect(restored.single.isDelivered, isTrue);
    });

    test('keeps the moment the driver marked it, not the moment it syncs',
        () async {
      final markedAt = DateTime(2026, 8, 14, 18, 30, 45);
      await PendingStatusQueue.enqueue(_change('11', at: markedAt));

      final restored = await PendingStatusQueue.load();

      expect(
        restored.single.occurredAt.toUtc(),
        markedAt.toUtc(),
      );
    });

    test('holds one entry per order, the last outcome winning', () async {
      await PendingStatusQueue.enqueue(_change('11', status: 'RETURNED'));
      await PendingStatusQueue.enqueue(_change('11', status: 'DELIVERED'));

      final queued = await PendingStatusQueue.load();

      expect(queued.length, 1);
      expect(queued.single.status, 'DELIVERED');
    });

    test('queues several orders in the order they were finished', () async {
      await PendingStatusQueue.enqueue(_change('11'));
      await PendingStatusQueue.enqueue(_change('12', status: 'RETURNED'));
      await PendingStatusQueue.enqueue(_change('13'));

      final queued = await PendingStatusQueue.load();

      expect(queued.map((c) => c.orderId), ['11', '12', '13']);
    });

    test('drops only the order that was confirmed', () async {
      await PendingStatusQueue.enqueue(_change('11'));
      await PendingStatusQueue.enqueue(_change('12'));

      await PendingStatusQueue.remove('11');

      final queued = await PendingStatusQueue.load();
      expect(queued.map((c) => c.orderId), ['12']);
    });

    test('removing an order that is not queued changes nothing', () async {
      await PendingStatusQueue.enqueue(_change('11'));

      await PendingStatusQueue.remove('99');

      expect((await PendingStatusQueue.load()).single.orderId, '11');
    });

    test('a malformed stored entry does not block the rest', () async {
      // An entry written by an older build, or a half-written one. The queue
      // must still hand back the deliveries it can read: refusing to parse the
      // lot would leave every later delivery unsyncable too.
      SharedPreferences.setMockInitialValues({
        PendingStatusQueue.prefsKey: [
          'not json at all',
          '{"orderId":"","status":"DELIVERED","occurredAt":"2026-08-14T18:30:00Z"}',
          '{"orderId":"12","status":"DELIVERED","occurredAt":"not a date"}',
          '{"orderId":"13","status":"DELIVERED","occurredAt":"2026-08-14T18:30:00Z"}',
        ],
      });

      final queued = await PendingStatusQueue.load();

      expect(queued.map((c) => c.orderId), ['13']);
    });

    test('clear empties the outbox', () async {
      await PendingStatusQueue.enqueue(_change('11'));

      await PendingStatusQueue.clear();

      expect(await PendingStatusQueue.load(), isEmpty);
    });
  });

  group('isRetryableStatusCode', () {
    test('retries what the server may yet accept', () {
      // 401 included on purpose: a session that lapsed while the driver was out
      // of signal is fixed by logging back in, and the delivery must survive
      // until then.
      for (final code in [401, 408, 429, 500, 502, 503, 504]) {
        expect(isRetryableStatusCode(code), isTrue, reason: 'HTTP $code');
      }
    });

    test('gives up on what the server has refused for good', () {
      // The order was deleted or handed to another driver — retrying it on
      // every poll for the rest of time would never turn into a delivery.
      for (final code in [400, 403, 404, 409, 422]) {
        expect(isRetryableStatusCode(code), isFalse, reason: 'HTTP $code');
      }
    });
  });
}
