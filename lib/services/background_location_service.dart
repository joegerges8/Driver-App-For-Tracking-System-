import 'dart:async';
import 'dart:convert';
// Directly rather than through WidgetsBinding: this isolate has no widget
// binding, so PlatformDispatcher.instance is the only way to reach the phone's
// language from here.
import 'dart:ui' show PlatformDispatcher;

import 'package:delivery_boy_app/services/api_config.dart';
import 'package:delivery_boy_app/services/pending_status_queue.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// SharedPreferences keys — must match auth_provider.dart's _tokenKey
const _tokenKey = 'driver_auth_token';

// The set of orders the driver has started and not yet finished. A driver can
// carry several orders at once (a batch run), and every one of them needs its
// own stream of GPS pings — each order has its own customer watching its own
// tracking page. Storing a list rather than a single id is what makes that
// possible: the previous single-id key meant starting a second delivery
// silently replaced the first, freezing the first customer's map.
const _orderIdsKey = 'bg_active_order_ids';

// The single-order key used before batch delivery existed. Read once on
// startup so an app upgrade mid-delivery keeps sharing location instead of
// going dark, then cleared.
const _legacyOrderIdKey = 'bg_active_order_id';

// Every order still assigned to this driver and not finished, refreshed by the
// service on its own timer so it holds true while the app is merely put away
// and the screen-bound polling in DeliveryProvider has stopped.
//
// Anything absent from it has been delivered, returned, cancelled or taken
// away, and must stop being pinged for even if this phone started it. It is a
// stop condition only — it never starts a delivery. What starts one is the
// driver tapping "Start Delivery", and nothing else.
const _backendOpenKey = 'bg_backend_open_ids';

// Shared with the rest of the app so a --dart-define pointing at a staging
// backend reaches the background isolate too, instead of it quietly carrying
// on posting to production.
String get _baseUrl => ApiConfig.baseUrl;

// Every request here gets a deadline, for the same reason ApiClient's do: the
// http package has none, and a connection the phone drops without closing
// leaves a request hanging forever. A tick that never finishes is a tick whose
// GPS never gets posted, so this is what keeps a delivery streaming through a
// dead spot rather than going quiet until the app is restarted. Shorter than
// the UI's twenty seconds because these run on a 15-second tick.
const Duration _requestTimeout = Duration(seconds: 12);

// The foreground-service notification. Android has required every foreground
// service to post one since Oreo, and this app now leans on that rather than
// hiding from it: the notification is the only thing that tells a driver in the
// field whether their location is still reaching the dispatcher.
//
// An earlier build ran the channel at IMPORTANCE_MIN with VISIBILITY_SECRET so
// it carried no status-bar icon and no lock-screen entry. That made the failure
// this whole change is about undiagnosable — on a phone whose vendor had
// stopped the service, the notification the driver never saw simply stopped
// being there, and the first anyone knew was a customer ringing to ask where
// their order was. It is now IMPORTANCE_LOW (see MainActivity.kt): still
// silent, no sound, no vibration, no badge, but visible, and its text is
// rewritten every tick with the time of the last successful fix or a warning.
//
// The channel id is versioned because a channel's importance is fixed at
// creation, so raising it on a phone that already ran an older build is a no-op
// unless the id changes. Must match LOCATION_CHANNEL_ID in MainActivity.kt.
const _notificationChannelId = 'driver_location_channel_v3';
const _notificationTitle = 'Driver App';

// Consecutive ticks that failed to report a position, shared with the UI
// isolate so the home screen can put the tracking setup screen in front of a
// driver whose location has actually stopped flowing. Must match
// kPingFailureStreakKey in tracking_permissions.dart.
const _failureStreakKey = 'bg_ping_failure_streak';

// Chosen language, written by LocaleProvider. Read here so the notification —
// the one piece of UI this isolate owns — is not stuck in English for a driver
// using the app in Arabic.
const _localeKey = 'driver_locale';

// A GPS read with no deadline can hang for as long as the radio wants, and this
// one used to have none: a single stalled fix took the tick with it and the
// timer's next run found nothing wrong, so the app went quiet without any error
// to notice. Ten seconds leaves room for the next tick to try again, and a
// stalled read falls back to the last known fix rather than reporting nothing —
// a slightly old position still tells the dispatcher which street the driver is
// on, which is more than a blank map does.
const Duration _gpsTimeout = Duration(seconds: 10);

// Reads the active order ids, migrating the legacy single-id key if present.
// Shared by the UI isolate and the background isolate — both need the same
// view of which orders are active, and only SharedPreferences is visible to both.
Future<List<String>> _readActiveOrderIds(SharedPreferences prefs) async {
  final ids = prefs.getStringList(_orderIdsKey);
  if (ids != null) return ids;

  final legacy = prefs.getString(_legacyOrderIdKey);
  if (legacy != null && legacy.isNotEmpty) {
    await prefs.setStringList(_orderIdsKey, [legacy]);
    await prefs.remove(_legacyOrderIdKey);
    return [legacy];
  }

  return const [];
}

/// Which orders should be receiving per-order GPS right now.
///
/// These pings are what the customer's tracking page is built on, so exactly
/// one thing starts them: the driver tapping "Start Delivery" on this phone.
/// The dispatcher marking an order PICKED_UP deliberately does not — a
/// customer must not watch their driver moving around before the driver has
/// said they are setting off, whatever the paperwork says. (This is separate
/// from the driver's own position, which goes to the dispatcher's map for as
/// long as the app is open and never reaches a customer.)
///
/// One thing stops them, and it overrules the tap: the backend no longer
/// listing the order as open. That is what stops a delivered or returned
/// delivery from streaming on — this phone's memory of having started it is
/// not evidence that it is still going.
///
/// The backend's list is only applied once it has actually been fetched. Until
/// then — first run, or offline since launch — a started delivery keeps
/// streaming rather than being second-guessed by a list we do not have.
Future<List<String>> _resolveTrackedOrderIds(SharedPreferences prefs) async {
  final started = await _readActiveOrderIds(prefs);
  final open = prefs.getStringList(_backendOpenKey);

  if (open == null) return started;

  return started.where(open.contains).toList();
}

class BackgroundLocationService {
  static final _svc = FlutterBackgroundService();

  /// Call once from main() before runApp to register the service configuration.
  static Future<void> initialize() async {
    await _svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        // Comes back after a reboot or an app update. Previously false, on the
        // reasoning that location sharing should last no longer than the app
        // the driver chose to open — but the service is also what the phone's
        // power manager kills, and a driver mid-shift whose phone restarted had
        // no way of knowing they had gone dark. Nothing is reported without a
        // token: the first tick after an unattended start finds no login and
        // stops the service, so this only ever resumes a driver who was already
        // signed in and working.
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: _notificationTitle,
        initialNotificationContent: '',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// Starts reporting, for as long as the app is running.
  ///
  /// Two separate streams come out of this, and they answer to different
  /// people. The driver's own position goes to the dispatcher's map every
  /// tick, order or no order, so a free driver can be seen and given work.
  /// The per-order pings that feed a customer's tracking page are not started
  /// here at all — only "Start Delivery" does that.
  ///
  /// It is tied to the driver's shift, not the app's window. The service is
  /// declared android:stopWithTask="false" and starts on boot, so it survives
  /// the app being backgrounded, swiped away, or killed by the phone's power
  /// manager — the last of which is what used to make Infinix and Tecno drivers
  /// drop off the dispatcher's map a few minutes after switching to Maps.
  /// Logging out is what ends it: the next tick finds no token and stops.
  ///
  /// Safe to call on every app start and resume; it does nothing if the
  /// service is already running.
  static Future<void> startWatching() async {
    final isRunning = await _svc.isRunning();
    if (!isRunning) await _svc.startService();
  }

  /// Adds an order to the tracked set and starts the service if it is not
  /// already running. Safe to call multiple times for the same order.
  static Future<void> startTracking(String orderId) async {
    if (orderId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final ids = await _readActiveOrderIds(prefs);
    if (!ids.contains(orderId)) {
      await prefs.setStringList(_orderIdsKey, [...ids, orderId]);
    }

    final isRunning = await _svc.isRunning();
    if (!isRunning) await _svc.startService();
  }

  /// Hands the app's freshly fetched order list to the service.
  ///
  /// The service polls for this itself, but the app in the foreground has
  /// often just asked the same question — passing the answer along means an
  /// order that has left the driver's hands stops being pinged for on the next
  /// tick, rather than waiting for the service to get round to asking too.
  static Future<void> publishBackendOrders({
    required Iterable<String> openOrderIds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_backendOpenKey, openOrderIds.toList());
  }

  /// Removes a single order from the tracked set, leaving the driver's other
  /// deliveries streaming.
  ///
  /// This no longer stops the service when the last order finishes. The
  /// service outlives any one delivery: finishing everything on the list means
  /// it stops posting to customer tracking pages, but it stays running for the
  /// next order the dispatcher sends. Logging out is what ends it.
  ///
  /// Striking the order off this phone's started list is enough to stop its
  /// pings immediately, since that list is the only thing that starts them.
  static Future<void> stopTrackingOrder(String orderId) async {
    final prefs = await SharedPreferences.getInstance();

    final started = await _readActiveOrderIds(prefs);
    await prefs.setStringList(
      _orderIdsKey,
      started.where((id) => id != orderId).toList(),
    );
  }

  /// Stops tracking every order and shuts the service down. Clears everything
  /// it decides from — including the backend's view, which would otherwise
  /// start the next driver to log in on this phone straight into the previous
  /// one's deliveries — and signals the isolate to stop.
  static Future<void> stopTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_orderIdsKey);
    await prefs.remove(_legacyOrderIdKey);
    await prefs.remove(_backendOpenKey);
    _svc.invoke('stopService');
  }

  /// The orders currently being tracked. Used on app start to restore the
  /// in-progress deliveries after the app was killed mid-run.
  static Future<List<String>> activeOrderIds() async {
    final prefs = await SharedPreferences.getInstance();
    return _readActiveOrderIds(prefs);
  }

  /// The orders whose GPS is actually flowing right now — this phone's started
  /// deliveries and the dispatcher's, minus anything the backend has closed.
  /// See [_resolveTrackedOrderIds] for the rule.
  static Future<List<String>> trackedOrderIds() async {
    final prefs = await SharedPreferences.getInstance();
    return _resolveTrackedOrderIds(prefs);
  }

  static Future<bool> isRunning() => _svc.isRunning();
}

// ── Background isolate entry points ──────────────────────────────────────────
// These functions run in a separate Dart isolate with no access to Provider,
// BuildContext, or any Flutter UI. They communicate only via SharedPreferences
// and the ServiceInstance event bus.

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {

  // Allow the main isolate to stop the service via invoke('stopService')
  service.on('stopService').listen((_) => service.stopSelf());

  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: _notificationTitle,
      content: _startingText(await _isArabic()),
    );
  }

  // Ticks every 15 seconds. Using a timer (instead of a stream) is more
  // reliable in background isolates.
  //
  // Two jobs, on different clocks: ask the backend what this driver is
  // carrying (every other tick, ~30s — it is a small request and the answer
  // changes at human speed), and post GPS for whatever that turns out to be
  // (every tick, but only while there is something to post it for).
  var tick = 0;

  Timer.periodic(const Duration(seconds: 15), (_) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // pick up ids written by the UI isolate
    final token = prefs.getString(_tokenKey);

    // Logging out ends it, and is now the only thing that does. The service no
    // longer dies with the app's task (see AndroidManifest.xml) because that
    // could not tell a driver swiping the app away from a vendor power manager
    // clearing it — so it keeps running until the driver says otherwise, with
    // the notification visible the whole time.
    if (token == null) {
      service.stopSelf();
      return;
    }

    // Deliveries the driver finished with no signal, sent before anything
    // else. This is the half of the retry that does not need the app to be
    // open: a driver who marks the last order of the day delivered in a
    // basement and then puts the phone away never reopens the app, and the
    // dispatcher would be left looking at an order that was delivered hours
    // ago. Runs every tick — it costs nothing when the queue is empty, which
    // is almost always.
    await _flushPendingStatuses(prefs, token);

    if (tick % 2 == 0) await _refreshBackendOrders(prefs, token);
    tick++;

    final orderIds = await _resolveTrackedOrderIds(prefs);
    final arabic = await _isArabic(prefs);

    // The tick's verdict is recorded exactly once. Without this, a per-order
    // POST timing out after the driver-level one had already succeeded would
    // fall into the catch below and count as a failure — three slow orders in a
    // row would then warn a driver whose location was in fact arriving fine.
    var recorded = false;

    Future<void> record({required bool reported}) async {
      if (recorded) return;
      recorded = true;
      await _recordTick(service, prefs, arabic: arabic, reported: reported);
    }

    try {
      final position = await _readPosition();

      if (position == null) {
        await record(reported: false);
        return;
      }

      // One GPS read, reported to two different audiences.
      //
      // The dispatcher gets it unconditionally, order or no order: their map
      // exists to answer "who is out there", and a driver waiting at the shop
      // with nothing assigned is precisely who they are looking for when the
      // next order lands. This is why the fix is read even when the order list
      // below is empty.
      final reported = await _postDriverLocation(token, position);

      // Whether the tick counts as a success is decided on the driver-level
      // post alone. It is the one request that happens on every tick, so it is
      // the only one that can tell "this phone has stopped reporting" from
      // "this driver happens to have no orders on".
      await record(reported: reported);

      // The customer gets it only through the orders actually under way —
      // unchanged, and deliberately so. A tracking page must never show a
      // driver moving around before their delivery has started.
      if (orderIds.isEmpty) return;

      // One position, fanned out to every active order. Each order simply
      // records it against its own tracking token.
      final responses = await Future.wait(
        orderIds.map(
          (orderId) => http.post(
            Uri.parse('$_baseUrl/api/drivers/me/orders/$orderId/location'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(_locationBody(position)),
          ).timeout(_requestTimeout),
        ),
      );

      // A 404 means the backend no longer has that order for this driver: the
      // dispatcher deleted it or reassigned it. Nothing will ever accept its
      // pings again, so drop it here — otherwise a deleted order kept the GPS
      // radio alive indefinitely.
      //
      // Only this phone's own "I started this" list is edited. The backend's
      // two lists are its to write, and the next refresh will have dropped the
      // order from them anyway. The service itself keeps running: the app is
      // still open, they have just lost one job.
      final gone = <String>{};
      for (var i = 0; i < orderIds.length; i++) {
        if (responses[i].statusCode == 404) gone.add(orderIds[i]);
      }

      if (gone.isNotEmpty) {
        final started = await _readActiveOrderIds(prefs);
        await prefs.setStringList(
          _orderIdsKey,
          started.where((id) => !gone.contains(id)).toList(),
        );
      }
    } catch (_) {
      // A missed ping is survivable; a run of them is not, and this used to be
      // where that distinction was lost. The tick is still swallowed rather
      // than crashing the service, but it is counted first — unless the
      // driver-level post already reported for this tick, in which case the
      // failure was somewhere further down and the phone is clearly still able
      // to reach the server.
      await record(reported: false);
    }
  });
}

/// One GPS fix, or null if the phone could not produce one.
///
/// Falls back to the last known position when the radio does not answer inside
/// [_gpsTimeout]. That fix may be a minute old, but the alternative is the
/// driver disappearing from the dispatcher's map entirely, and a stale dot is
/// far more useful to whoever is looking at it than no dot.
Future<Position?> _readPosition() async {
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: _gpsTimeout,
      ),
    );
  } catch (_) {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }
}

/// The POST body for both location endpoints.
///
/// `sent_at` is the phone's own clock at the moment of the fix. The server
/// timestamps rows on arrival, which cannot tell a ping delayed by a bad signal
/// from one delayed by the phone having been asleep — the difference between
/// "the network is slow here" and "this device stopped reporting", which is
/// exactly the failure being chased. Extra fields are ignored by the API.
Map<String, dynamic> _locationBody(Position position) => {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'sent_at': DateTime.now().toUtc().toIso8601String(),
    };

/// Records the outcome of a tick and rewrites the notification to match.
///
/// The streak is what the home screen reads to decide whether to put the
/// tracking setup screen back in front of the driver, and the notification text
/// is what the driver themselves sees. Both exist for the same reason: on a
/// phone whose vendor has throttled the app, everything looks fine right up
/// until a customer calls to ask where their order is.
Future<void> _recordTick(
  ServiceInstance service,
  SharedPreferences prefs, {
  required bool arabic,
  required bool reported,
}) async {
  final streak = reported ? 0 : (prefs.getInt(_failureStreakKey) ?? 0) + 1;
  await prefs.setInt(_failureStreakKey, streak);

  if (service is! AndroidServiceInstance) return;

  await service.setForegroundNotificationInfo(
    title: _notificationTitle,
    content: reported
        ? _activeText(arabic, DateTime.now())
        : _stalledText(arabic, streak),
  );
}

// The notification is the only text this isolate shows, and it has no access to
// AppLocalizations — that lives in the UI isolate behind a BuildContext. Four
// strings inline is cheaper than making the whole translation table reachable
// from here, and they are the only ones that will ever be needed.
String _startingText(bool arabic) =>
    arabic ? 'جارٍ بدء التتبع…' : 'Starting location sharing…';

String _activeText(bool arabic, DateTime at) {
  final time = '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
  return arabic ? 'التتبع يعمل · آخر تحديث $time' : 'Tracking on · last sent $time';
}

String _stalledText(bool arabic, int streak) {
  // Two misses is 30 seconds, still inside what a tunnel explains. Past that,
  // say so plainly — the driver is the only one who can go and fix it.
  if (streak < 3) {
    return arabic ? 'جارٍ إعادة المحاولة…' : 'Retrying…';
  }
  return arabic
      ? '⚠ توقف التتبع — افتح التطبيق'
      : '⚠ Location stopped — open the app';
}

/// Whether the driver picked Arabic, falling back to the phone's own language
/// the same way MaterialApp does when no explicit choice has been stored.
Future<bool> _isArabic([SharedPreferences? loaded]) async {
  try {
    final prefs = loaded ?? await SharedPreferences.getInstance();
    final stored = prefs.getString(_localeKey);
    if (stored != null) return stored == 'ar';
    return PlatformDispatcher.instance.locale.languageCode == 'ar';
  } catch (_) {
    return false;
  }
}

// Reports where the driver is to the dispatcher's live map, with no order
// attached. Still best-effort — a failed post must never take down the
// per-order pings a waiting customer is watching — but it now says whether it
// worked, because a run of failures here is the app's own early warning that
// this phone has stopped reporting.
Future<bool> _postDriverLocation(String token, Position position) async {
  try {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/drivers/me/location'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(_locationBody(position)),
    ).timeout(_requestTimeout);

    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (_) {
    return false;
  }
}

/// Sends every delivery outcome still sitting in the outbox.
///
/// The same queue the app flushes (DeliveryProvider.flushPendingStatuses) and
/// the same rules: an entry leaves the queue when the backend accepts it, or
/// when the backend refuses it in a way that will not change. Anything else
/// stops the round — they all go to one server, so if one cannot reach it
/// neither can the rest.
///
/// Sending the same outcome twice is harmless. Both isolates may flush at once
/// when the app is open, and the backend simply writes the status and the
/// timestamp it is given again — the timestamp travels with the entry, so a
/// second write lands on the same value as the first.
Future<void> _flushPendingStatuses(
  SharedPreferences prefs,
  String token,
) async {
  // prefs has already been reloaded by the caller this tick, so what is read
  // here includes anything the app queued while the service was between ticks.
  final pending = await PendingStatusQueue.load(prefs: prefs);
  if (pending.isEmpty) return;

  for (final change in pending) {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/api/drivers/me/orders/${change.orderId}/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'status': change.status,
          'occurred_at': change.occurredAt.toUtc().toIso8601String(),
        }),
      ).timeout(_requestTimeout);

      final code = response.statusCode;
      if (code >= 200 && code < 300) {
        await PendingStatusQueue.remove(change.orderId, prefs);
        continue;
      }

      if (isRetryableStatusCode(code)) return; // the next tick tries again
      await PendingStatusQueue.remove(change.orderId, prefs);
    } catch (_) {
      return; // no connection — the queue is exactly where it should be
    }
  }
}

// Asks the backend which orders this driver still holds and records the answer
// for _resolveTrackedOrderIds to act on.
//
// A failed request deliberately writes nothing. This list is what can stop GPS
// flowing, and treating a dropped connection as "no orders" would cut a
// delivery's tracking dead every time the driver went through a tunnel. Stale
// is the safe direction here: keep pinging what we last knew about, and
// correct it when the network comes back.
Future<void> _refreshBackendOrders(
  SharedPreferences prefs,
  String token,
) async {
  try {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/drivers/me/orders'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_requestTimeout);

    if (response.statusCode != 200) return;

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return;

    final open = <String>[];

    for (final item in decoded) {
      if (item is! Map) continue;
      final id = item['id']?.toString();
      if (id == null || id.isEmpty) continue;

      // The endpoint only returns orders that are still the driver's problem —
      // delivered, returned and cancelled ones are already filtered out server
      // side — so everything here is open by definition.
      open.add(id);
    }

    await prefs.setStringList(_backendOpenKey, open);
  } catch (_) {
    // Offline or a bad response — keep the last known lists.
  }
}
