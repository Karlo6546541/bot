import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Javlja `web/index.html` da je aplikacija spremna: jedini uvodni ekran
/// (HTML) se tada lagano ugasi.
void signalAppReady() {
  final w = web.window as JSObject;
  if (w.has('subhastoReady')) w.callMethod('subhastoReady'.toJS);
}
