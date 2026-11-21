import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Preglednik na mobitelu ima `navigator.share` (sistemski izbornik s
/// WhatsAppom, Viberom, SMS-om…); većina preglednika na računalu nema.
bool canNativeShare() => web.window.navigator.has('share');
