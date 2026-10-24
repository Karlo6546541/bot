import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'boxnow.dart';

bool get boxNowAvailable => true;

Completer<BoxNowPick>? _pending;
Future<void>? _loading;
bool _listening = false;

/// Podaci koje šalje BOX NOW karta (`boxnowLockerId`, adresa, poštanski
/// broj…) — kao JS objekt ili JSON tekst.
BoxNowLocker? _read(JSAny? data) {
  if (data == null) return null;
  JSObject? o;
  if (data.isA<JSString>()) {
    try {
      final json = (globalContext['JSON'] as JSObject).callMethod<JSAny?>(
        'parse'.toJS,
        data,
      );
      o = json.isA<JSObject>() ? json as JSObject : null;
    } catch (_) {
      return null;
    }
  } else if (data.isA<JSObject>()) {
    o = data as JSObject;
  }
  if (o == null) return null;
  String field(String k) {
    final v = o![k];
    return v == null ? '' : v.dartify().toString().trim();
  }

  final id = field('boxnowLockerId');
  if (id.isEmpty) return null;
  return BoxNowLocker(
    id: id,
    address: field('boxnowLockerAddressLine1'),
    postalCode: field('boxnowLockerPostalCode'),
    name: field('boxnowLockerName'),
  );
}

void _finish(BoxNowPick result) {
  final c = _pending;
  _pending = null;
  if (c != null && !c.isCompleted) c.complete(result);
}

void _listen() {
  if (_listening) return;
  _listening = true;
  // Rezerva: karta javlja odabir i porukom prozoru.
  web.window.addEventListener(
    'message',
    ((web.MessageEvent e) {
      if (!e.origin.contains('boxnow')) return;
      final locker = _read(e.data);
      if (locker != null) _finish(BoxNowPicked(locker));
    }).toJS,
  );
}

/// Gumb koji BOX NOW skripta veže na kartu i element u koji se crta.
web.HTMLElement _ensureElements() {
  final doc = web.document;
  if (doc.getElementById('boxnowmap') == null) {
    final map = doc.createElement('div') as web.HTMLDivElement
      ..id = 'boxnowmap';
    doc.body!.append(map);
  }
  var button =
      doc.querySelector('.boxnow-map-widget-button') as web.HTMLElement?;
  if (button == null) {
    button = doc.createElement('a') as web.HTMLAnchorElement
      ..className = 'boxnow-map-widget-button'
      ..href = 'javascript:;'
      ..style.display = 'none';
    doc.body!.append(button);
  }
  return button;
}

void _configure(String partnerId) {
  final config = JSObject()
    ..['parentElement'] = '#boxnowmap'.toJS
    ..['type'] = 'popup'.toJS
    ..['autoclose'] = true.toJS
    ..['afterSelect'] = ((JSAny? data) {
      final locker = _read(data);
      if (locker != null) _finish(BoxNowPicked(locker));
    }).toJS;
  final id = int.tryParse(partnerId.trim());
  if (id != null) config['partnerId'] = id.toJS;
  globalContext['_bn_map_widget_config'] = config;
}

Future<void> _load(String scriptUrl) {
  final done = Completer<void>();
  final s = web.document.createElement('script') as web.HTMLScriptElement
    ..src = scriptUrl
    ..async = true;
  s.addEventListener('load', ((web.Event _) => done.complete()).toJS);
  s.addEventListener(
    'error',
    ((web.Event _) {
      if (!done.isCompleted) done.completeError('load');
    }).toJS,
  );
  web.document.head!.append(s);
  return done.future.timeout(const Duration(seconds: 10));
}

Future<BoxNowPick> boxNowPick(String partnerId, String scriptUrl) async {
  _listen();
  final button = _ensureElements();
  _configure(partnerId);
  // Prethodno otvaranje (zatvoreno bez odabira) više ne čeka.
  final old = _pending;
  if (old != null && !old.isCompleted) old.complete(const BoxNowClosed());
  final c = _pending = Completer<BoxNowPick>();
  try {
    await (_loading ??= _load(scriptUrl));
  } catch (_) {
    _loading = null;
    _finish(const BoxNowUnavailable());
    return c.future;
  }
  button.click();
  return c.future;
}
