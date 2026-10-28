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
    // Obje klase: dokumentacija spominje i jednu i drugu.
    button = doc.createElement('a') as web.HTMLAnchorElement
      ..className = 'boxnow-map-widget-button boxnow-widget-button'
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
    ..['buttonSelector'] = '.boxnow-map-widget-button'.toJS
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
  // Ako se karta nakon nekoliko sekundi ne pojavi (npr. drukčija verzija
  // skripte ili blokirana), prelazi se na popis paketomata.
  Future<void>.delayed(const Duration(seconds: 5), () {
    if (identical(_pending, c) && !c.isCompleted && !_mapVisible()) {
      _finish(const BoxNowUnavailable());
    }
  });
  return c.future;
}

/// Je li BOX NOW karta otvorena (iframe ili sadržaj u #boxnowmap).
bool _mapVisible() {
  final doc = web.document;
  if (doc.querySelector('iframe[src*="boxnow"]') != null) return true;
  final map = doc.getElementById('boxnowmap');
  return map != null && map.childElementCount > 0;
}

// ---------------------------------------------------------------------------
// GLS i DPD karte.

/// JS objekt iz podataka (objekt ili JSON tekst).
JSObject? _obj(JSAny? data) {
  if (data == null) return null;
  if (data.isA<JSString>()) {
    try {
      final json = (globalContext['JSON'] as JSObject).callMethod<JSAny?>(
        'parse'.toJS,
        data,
      );
      return json.isA<JSObject>() ? json as JSObject : null;
    } catch (_) {
      return null;
    }
  }
  return data.isA<JSObject>() ? data as JSObject : null;
}

/// Prvo neprazno polje od [keys].
String _field(JSObject? o, List<String> keys) {
  if (o == null) return '';
  for (final k in keys) {
    final v = o[k];
    if (v == null || v.isA<JSObject>() && !v.isA<JSString>()) continue;
    final s = v.dartify().toString().trim();
    if (s.isNotEmpty && s != 'null') return s;
  }
  return '';
}

JSObject? _child(JSObject? o, List<String> keys) {
  if (o == null) return null;
  for (final k in keys) {
    final v = o[k];
    if (v != null && v.isA<JSObject>() && !v.isA<JSString>()) {
      return v as JSObject;
    }
  }
  return null;
}

/// Točka koju vrati GLS ili DPD karta (polja se razlikuju po verziji).
BoxNowLocker? _readPoint(JSAny? data, LockerNetwork n) {
  var o = _obj(data);
  // DPD widget šalje { dpdWidget: {...} }.
  o = _child(o, const ['dpdWidget', 'pickupPoint', 'point', 'detail']) ?? o;
  final id = _field(o, const [
    'id',
    'pickupPointId',
    'parcelShopId',
    'pudoId',
    'code',
  ]);
  if (id.isEmpty) return null;
  final contact = _child(o, const ['contact', 'location', 'address']);
  final street = _field(contact ?? o, const ['address', 'street', 'street1']);
  final city = _field(contact ?? o, const ['city', 'town']);
  final zip = _field(contact ?? o, const ['postalCode', 'zipCode', 'zip']);
  return BoxNowLocker(
    network: n,
    id: id,
    name: _field(o, const ['name', 'companyName', 'title']),
    address: [street, city].where((x) => x.isNotEmpty).join(', '),
    postalCode: zip,
  );
}

Future<void>? _glsLoading;
Completer<BoxNowPick>? _glsPending;
String? _glsCountry;

Future<void> _loadModule(String url) {
  final done = Completer<void>();
  final s = web.document.createElement('script') as web.HTMLScriptElement
    ..type = 'module'
    ..src = url;
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

const _glsLanguages = {
  'hr': 'hr',
  'si': 'sl',
  'hu': 'hu',
  'cz': 'cs',
  'sk': 'sk',
  'ro': 'ro',
};

Future<BoxNowPick> glsPick(String scriptUrl, String country) async {
  final old = _glsPending;
  if (old != null && !old.isCompleted) old.complete(const BoxNowClosed());
  final c = _glsPending = Completer<BoxNowPick>();
  void finish(BoxNowPick r) {
    if (identical(_glsPending, c) && !c.isCompleted) c.complete(r);
  }

  try {
    await (_glsLoading ??= _loadModule(scriptUrl));
    await (globalContext['customElements'] as JSObject)
        .callMethod<JSPromise<JSAny?>>(
          'whenDefined'.toJS,
          'gls-dpm-dialog'.toJS,
        )
        .toDart
        .timeout(const Duration(seconds: 5));
  } catch (_) {
    _glsLoading = null;
    finish(const BoxNowUnavailable());
    return c.future;
  }
  final doc = web.document;
  var el = doc.getElementById('gls-dpm');
  if (el != null && _glsCountry != country) {
    el.remove();
    el = null;
  }
  if (el == null) {
    _glsCountry = country;
    el = doc.createElement('gls-dpm-dialog')
      ..id = 'gls-dpm'
      ..setAttribute('country', country)
      ..setAttribute('language', _glsLanguages[country] ?? 'en')
      ..setAttribute('filter-type', 'parcel-locker');
    el.addEventListener(
      'change',
      ((web.Event e) {
        final point = _readPoint(
          (e as web.CustomEvent).detail,
          LockerNetwork.gls,
        );
        final p = _glsPending;
        if (point != null && p != null && !p.isCompleted) {
          p.complete(BoxNowPicked(point));
        }
      }).toJS,
    );
    doc.body!.append(el);
  }
  try {
    (el as JSObject).callMethod<JSAny?>('showModal'.toJS);
  } catch (_) {
    finish(const BoxNowUnavailable());
  }
  return c.future;
}

Completer<BoxNowPick>? _dpdPending;
bool _dpdListening = false;

Future<BoxNowPick> dpdPick(String url, String country) async {
  final old = _dpdPending;
  if (old != null && !old.isCompleted) old.complete(const BoxNowClosed());
  final c = _dpdPending = Completer<BoxNowPick>();
  final doc = web.document;
  doc.getElementById('dpd-map')?.remove();
  void close(BoxNowPick r) {
    doc.getElementById('dpd-map')?.remove();
    if (identical(_dpdPending, c) && !c.isCompleted) c.complete(r);
  }

  if (!_dpdListening) {
    _dpdListening = true;
    web.window.addEventListener(
      'message',
      ((web.MessageEvent e) {
        if (doc.getElementById('dpd-map') == null) return;
        final point = _readPoint(e.data, LockerNetwork.dpd);
        final p = _dpdPending;
        if (point != null && p != null && !p.isCompleted) {
          doc.getElementById('dpd-map')?.remove();
          p.complete(BoxNowPicked(point));
        }
      }).toJS,
    );
  }
  final sep = url.contains('?') ? '&' : '?';
  final overlay = doc.createElement('div') as web.HTMLDivElement
    ..id = 'dpd-map'
    ..style.cssText =
        'position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,.6);'
        'display:flex;align-items:center;justify-content:center';
  final frame = doc.createElement('iframe') as web.HTMLIFrameElement
    ..src = '$url${sep}country=${country.toLowerCase()}'
    ..style.cssText =
        'width:min(960px,96vw);height:min(720px,90vh);border:0;'
        'border-radius:16px;background:#fff';
  final x = doc.createElement('button') as web.HTMLButtonElement
    ..textContent = '✕'
    ..style.cssText =
        'position:absolute;top:12px;right:12px;width:40px;height:40px;'
        'border-radius:20px;border:0;font-size:18px;background:#fff';
  x.addEventListener(
    'click',
    ((web.Event _) => close(const BoxNowClosed())).toJS,
  );
  overlay
    ..append(frame)
    ..append(x);
  doc.body!.append(overlay);
  // Ako se iframe ne učita, kupac bira s popisa.
  frame.addEventListener(
    'error',
    ((web.Event _) => close(const BoxNowUnavailable())).toJS,
  );
  return c.future;
}
