import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool _isLoaded() {
  try {
    final google = globalContext['google'];
    if (google == null) return false;
    final maps = (google as JSObject)['maps'];
    return maps != null;
  } catch (_) {
    return false;
  }
}

Future<bool> ensureGoogleMapsLoaded({required String apiKey}) async {
  final key = apiKey.trim();
  if (key.isEmpty) return false;
  if (_isLoaded()) return true;

  final completer = Completer<bool>();

  final script = web.HTMLScriptElement()
    ..src = 'https://maps.googleapis.com/maps/api/js?key=$key'
    ..type = 'text/javascript'
    ..async = true
    ..defer = true;

  script.addEventListener(
    'error',
    (web.Event _) {
      if (!completer.isCompleted) completer.complete(false);
    }.toJS,
  );

  script.addEventListener(
    'load',
    (web.Event _) {
      if (!completer.isCompleted) completer.complete(_isLoaded());
    }.toJS,
  );

  web.document.head?.append(script);

  try {
    return await completer.future.timeout(const Duration(seconds: 25));
  } catch (_) {
    return _isLoaded();
  }
}
