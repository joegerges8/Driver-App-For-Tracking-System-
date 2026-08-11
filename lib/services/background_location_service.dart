import 'dart:async';
import 'dart:convert';

import 'package:delivery_boy_app/services/api_config.dart';
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

// The backend's own view of this driver's work, refreshed by the service on
// its own timer so it holds true while the app is merely put away and the
// screen-bound polling in DeliveryProvider has stopped.
//
//   _backendOnRoadKey — orders the backend says are on the road (PICKED_UP or
//                       OUT_FOR_DELIVERY). The dispatcher flipping an order to
//                       PICKED_UP from the dashboard shows up here, and that
//                       is what starts this driver sharing location without
//                       them tapping anything.
//   _backendOpenKey   — every order still assigned to the driver and not
//                       finished. Anything absent from it has been delivered,
//                       returned, cancelled or taken away, and must stop being
//                       pinged for even if this phone started it.
const _backendOnRoadKey = 'bg_backend_on_road_ids';
const _backendOpenKey = 'bg_backend_open_ids';

// Order statuses that mean the driver is carrying this order right now.
const _onRoadStatuses = {'PICKED_UP', 'OUT_FOR_DELIVERY'};

// Shared with the rest of the app so a --dart-define pointing at a staging
// backend reaches the background isolate too, instead of it quietly carrying
// on posting to production.
String get _baseUrl => ApiConfig.baseUrl;

// The foreground-service notification, cut down to the least Android will
// accept. GPS that survives the app being backgrounded or force-killed has to
// run in a foreground service, and Android has required every foreground
// service to post a visible notification since Oreo — there is no flag that
// removes it. What is left is making it say as little as possible: no body
// text, and a channel (see MainActivity.kt) at IMPORTANCE_MIN so it is silent,
// carries no status-bar icon, no badge and no lock-screen entry, and sits
// collapsed at the bottom of the shade. On Android 13+ the driver can also
// swipe it away and it stays gone for that run.
//
// The channel id is versioned because a channel's importance is fixed at
// creation: existing installs already have 'driver_location_channel', and
// re-creating it with a lower importance is a no-op. A new id is the only way
// to get the quieter settings onto phones the old build already touched.
const _notificationChannelId = 'driver_location_channel_v2';
const _notificationTitle = 'Driver App';

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

/// Which orders should be receiving GPS right now.
///
/// Two things can put an order on the road, and either is enough:
///   - the driver tapped "Start Delivery" on this phone, or
///   - the dispatcher marked it PICKED_UP on the dashboard.
///
/// One thing takes it off, and it overrules both: the backend no longer
/// listing it as open. That is what stops a delivered or returned order from
/// pinning the driver to the map — this phone's memory of having started it is
/// not evidence that it is still going.
///
/// The backend's list is only applied once it has actually been fetched. Until
/// then — first run, or offline since launch — a locally started delivery
/// keeps streaming rather than being second-guessed by a list we do not have.
Future<List<String>> _resolveTrackedOrderIds(SharedPreferences prefs) async {
  final started = await _readActiveOrderIds(prefs);
  final onRoad = prefs.getStringList(_backendOnRoadKey) ?? const [];
  final open = prefs.getStringList(_backendOpenKey);

  final wanted = <String>{...started, ...onRoad};
  if (open == null) return wanted.toList();

  return wanted.where(open.contains).toList();
}

class BackgroundLocationService {
  static final _svc = FlutterBackgroundService();

  /// Call once from main() before runApp to register the service configuration.
  static Future<void> initialize() async {
    await _svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        // The plugin restarts the service after a reboot or an app update by
        // default, which would put a driver back on the dashboard without the
        // app ever being opened. Location sharing here is meant to last no
        // longer than the app the driver chose to open.
        autoStartOnBoot: false,
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

  /// Starts watching for work, for as long as the app is running.
  ///
  /// This is what makes "the dispatcher marks it PICKED_UP and the driver
  /// starts being tracked" work without the driver tapping anything: while it
  /// runs it asks the backend what this driver is carrying, and turns GPS on
  /// by itself the moment an order comes back on the road. With nothing to
  /// carry it costs one small request every half minute and does not touch the
  /// GPS at all.
  ///
  /// It is deliberately tied to the app's life, not the driver's shift. The
  /// service is declared android:stopWithTask="true" and does not start on
  /// boot, so swiping the app away from recents ends it, and with it every
  /// order's location stream — a driver who has closed the app is a driver the
  /// dashboard stops following. Opening the app again picks everything back up.
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
  /// often just asked the same question — passing the answer along means a
  /// dispatcher's PICKED_UP takes effect on the next tick rather than waiting
  /// for the service to get round to asking too.
  static Future<void> publishBackendOrders({
    required Iterable<String> openOrderIds,
    required Iterable<String> onRoadOrderIds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_backendOpenKey, openOrderIds.toList());
    await prefs.setStringList(_backendOnRoadKey, onRoadOrderIds.toList());
  }

  /// Removes a single order from the tracked set, leaving the driver's other
  /// deliveries streaming.
  ///
  /// This no longer stops the service when the last order finishes. The
  /// service outlives any one delivery: finishing everything on the list means
  /// it goes quiet and stops touching the GPS, but it stays listening for the
  /// next order the dispatcher sends. Closing the app is what ends it.
  ///
  /// The order is struck off the backend's on-road list as well as this
  /// phone's. Marking a delivery done here is the most recent word on it, and
  /// without this the pings would carry on for the half-minute or so until the
  /// next refresh caught up with what the driver already knows.
  static Future<void> stopTrackingOrder(String orderId) async {
    final prefs = await SharedPreferences.getInstance();

    final started = await _readActiveOrderIds(prefs);
    await prefs.setStringList(
      _orderIdsKey,
      started.where((id) => id != orderId).toList(),
    );

    final onRoad = prefs.getStringList(_backendOnRoadKey);
    if (onRoad != null) {
      await prefs.setStringList(
        _backendOnRoadKey,
        onRoad.where((id) => id != orderId).toList(),
      );
    }
  }

  /// Stops tracking every order and shuts the service down. Clears everything
  /// it decides from — including the backend's view, which would otherwise
  /// start the next driver to log in on this phone straight into the previous
  /// one's deliveries — and signals the isolate to stop.
  static Future<void> stopTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_orderIdsKey);
    await prefs.remove(_legacyOrderIdKey);
    await prefs.remove(_backendOnRoadKey);
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
      content: '',
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

    // Logging out ends it. Having nothing to deliver does not: a driver with
    // the app open and no order yet is exactly who needs someone still
    // listening for the dispatcher to hand them a job. Closing the app ends it
    // too, but that is Android's doing via stopWithTask, not this check.
    if (token == null) {
      service.stopSelf();
      return;
    }

    if (tick % 2 == 0) await _refreshBackendOrders(prefs, token);
    tick++;

    final orderIds = await _resolveTrackedOrderIds(prefs);

    // Nothing on the road: no GPS fix, no requests, nothing but the wait.
    if (orderIds.isEmpty) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      // One GPS read, fanned out to every active order. The driver has a single
      // position; each order simply records it against its own tracking token.
      final responses = await Future.wait(
        orderIds.map(
          (orderId) => http.post(
            Uri.parse('$_baseUrl/api/drivers/me/orders/$orderId/location'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'latitude': position.latitude,
              'longitude': position.longitude,
            }),
          ),
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
      // Silent — a missed ping is acceptable
    }
  });
}

// Asks the backend what this driver is carrying and records the answer for
// _resolveTrackedOrderIds to act on.
//
// A failed request deliberately writes nothing. The stored lists are what
// decide whether GPS flows, and treating a dropped connection as "no orders"
// would cut a delivery's tracking dead every time the driver went through a
// tunnel. Stale is the safe direction here: keep pinging what we last knew
// about, and correct it when the network comes back.
Future<void> _refreshBackendOrders(
  SharedPreferences prefs,
  String token,
) async {
  try {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/drivers/me/orders'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) return;

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return;

    final open = <String>[];
    final onRoad = <String>[];

    for (final item in decoded) {
      if (item is! Map) continue;
      final id = item['id']?.toString();
      if (id == null || id.isEmpty) continue;

      // The endpoint only returns orders that are still the driver's problem —
      // delivered, returned and cancelled ones are already filtered out server
      // side — so everything here is open by definition.
      open.add(id);

      final status = (item['order_status'] ?? '').toString().toUpperCase();
      if (_onRoadStatuses.contains(status)) onRoad.add(id);
    }

    await prefs.setStringList(_backendOpenKey, open);
    await prefs.setStringList(_backendOnRoadKey, onRoad);
  } catch (_) {
    // Offline or a bad response — keep the last known lists.
  }
}
