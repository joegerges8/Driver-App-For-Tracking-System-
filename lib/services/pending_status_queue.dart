// pending_status_queue.dart
//
// The outbox for delivery outcomes: an order the driver marked delivered or
// returned, written to disk before it is sent, and kept there until the
// backend has confirmed it.
//
// This exists because of the one failure the app could not recover from. The
// driver taps "Mark as Delivered" in a basement, a lift, a village with no
// signal — the app moves the order to the Done tab straight away, the PATCH
// that tells the backend fails, and that was the end of it. The order stayed
// delivered on the phone and still out for delivery on the dispatcher's
// dashboard, and nothing in the app ever tried again. The only record that the
// delivery had happened lived in memory and died with the next app restart.
//
// Everything here is deliberately kept on disk rather than in the provider:
//   - a driver who marks an order delivered and puts the phone in their pocket
//     is the normal case, and the app is often killed before signal returns;
//   - the background location service, which keeps running when the app does
//     not, can flush the same queue from its own isolate.
//
// Entries are keyed by order id, one each: the last outcome the driver chose
// for an order is the true one. Marking an order returned and then delivered
// leaves one entry saying delivered, not two contradicting each other.
//
// Each entry carries the moment the driver actually tapped the button. That
// timestamp is sent with the retry, so a delivery that syncs the next morning
// is still recorded — in the dashboard, in the day's takings, and in the
// dispatcher's average delivery time — as having happened when it happened.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Whether a status the backend answered with is worth trying again.
///
/// The line is between "the server never really considered this" and "the
/// server considered it and said no". A refusal on the second side — a
/// malformed request, an order that is no longer this driver's — will be
/// refused just as firmly in an hour, and retrying it forever only keeps a
/// dead entry in the queue.
///
/// 401 sits on the retryable side on purpose: an expired token is replaced by
/// logging in again, and a delivery must not be thrown away because the
/// session lapsed while the driver was out of signal.
///
/// Lives here rather than in ApiClient because both senders need the same
/// rule — the app, and the background service that flushes this queue from its
/// own isolate while the app is closed.
bool isRetryableStatusCode(int code) =>
    code == 401 || code == 408 || code == 429 || code >= 500;

/// One delivery outcome waiting to reach the backend.
class PendingStatusChange {
  const PendingStatusChange({
    required this.orderId,
    required this.status,
    required this.occurredAt,
    this.paymentMethod,
  });

  /// Backend order id.
  final String orderId;

  /// 'DELIVERED' or 'RETURNED' — what the driver chose.
  final String status;

  /// When the driver chose it, which is not when it will be sent.
  final DateTime occurredAt;

  /// 'WHISH' when the driver used "Delivered & Paid by Whish" — the customer
  /// transferred instead of handing over cash. Null for ordinary deliveries.
  /// Stored with the outcome so a Whish delivery marked in a dead spot still
  /// reaches the backend as a Whish delivery, however much later it syncs.
  final String? paymentMethod;

  bool get isDelivered => status == 'DELIVERED';
  bool get isReturned => status == 'RETURNED';
  bool get isPaidByWhish => paymentMethod == 'WHISH';

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'status': status,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
      };

  static PendingStatusChange? fromJson(Map<String, dynamic> json) {
    final orderId = json['orderId'];
    final status = json['status'];
    final occurredAt = DateTime.tryParse('${json['occurredAt']}');
    // Optional, and absent from entries written by older builds — those are
    // ordinary deliveries, which null already means.
    final paymentMethod = json['paymentMethod'];

    if (orderId is! String || orderId.isEmpty) return null;
    if (status is! String || status.isEmpty) return null;
    if (occurredAt == null) return null;

    return PendingStatusChange(
      orderId: orderId,
      status: status,
      occurredAt: occurredAt.toLocal(),
      paymentMethod:
          paymentMethod is String && paymentMethod.isNotEmpty
              ? paymentMethod
              : null,
    );
  }
}

/// The stored queue. Every method reads the current contents before writing so
/// the UI isolate and the background isolate — which both flush it — cannot
/// overwrite each other's removals with a stale copy.
class PendingStatusQueue {
  /// Shared with the background isolate, so it must be a plain constant string
  /// rather than anything derived at runtime.
  static const String prefsKey = 'pending_order_status_changes';

  /// Everything still waiting to be sent, oldest first.
  ///
  /// Unparseable entries are dropped rather than throwing: a queue that cannot
  /// be read would block every later delivery from syncing, which is a far
  /// worse failure than losing one malformed row written by an older build.
  ///
  /// [refresh] re-reads the underlying store first, which matters because two
  /// isolates flush this queue. Without it the app would keep showing — and
  /// keep retrying — a delivery the background service had already sent while
  /// the app was closed.
  static Future<List<PendingStatusChange>> load({
    SharedPreferences? prefs,
    bool refresh = false,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    if (refresh) await store.reload();
    final raw = store.getStringList(prefsKey) ?? const <String>[];

    final changes = <PendingStatusChange>[];
    for (final entry in raw) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is! Map<String, dynamic>) continue;
        final change = PendingStatusChange.fromJson(decoded);
        if (change != null) changes.add(change);
      } catch (_) {
        // Skip and keep going — see above.
      }
    }
    return changes;
  }

  /// Adds an outcome, replacing any earlier one for the same order.
  ///
  /// Returns the queue as it now stands, so the caller does not have to read it
  /// back to know what is outstanding.
  static Future<List<PendingStatusChange>> enqueue(
    PendingStatusChange change, [
    SharedPreferences? prefs,
  ]) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final current = await load(prefs: store, refresh: true);
    final next = [
      ...current.where((c) => c.orderId != change.orderId),
      change,
    ];
    await _write(store, next);
    return next;
  }

  /// Drops an order's entry — it has been accepted by the backend, or the
  /// backend has said it will never accept it.
  static Future<List<PendingStatusChange>> remove(
    String orderId, [
    SharedPreferences? prefs,
  ]) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    // The other isolate may have written since we last read.
    final current = await load(prefs: store, refresh: true);
    final next = current.where((c) => c.orderId != orderId).toList();
    await _write(store, next);
    return next;
  }

  static Future<void> clear([SharedPreferences? prefs]) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    await store.remove(prefsKey);
  }

  static Future<void> _write(
    SharedPreferences prefs,
    List<PendingStatusChange> changes,
  ) async {
    await prefs.setStringList(
      prefsKey,
      changes.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }
}
