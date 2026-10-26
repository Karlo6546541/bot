import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.AudioContext? _ctx;

/// Tonovi (frekvencija Hz, početak s, trajanje s) — kratki "bip" s
/// mekim početkom i krajem. Preglednik dopušta zvuk tek nakon dodira.
void tones(List<(double, double, double)> notes, {double volume = 0.18}) {
  try {
    final ctx = _ctx ??= web.AudioContext();
    if (ctx.state == 'suspended') ctx.resume();
    final now = ctx.currentTime;
    for (final (freq, start, dur) in notes) {
      final osc = ctx.createOscillator()
        ..type = 'triangle'
        ..frequency.value = freq;
      final gain = ctx.createGain();
      final t0 = now + start;
      gain.gain
        ..setValueAtTime(0.0001, t0)
        ..exponentialRampToValueAtTime(volume, t0 + 0.01)
        ..exponentialRampToValueAtTime(0.0001, t0 + dur);
      osc
        ..connect(gain)
        ..start(t0)
        ..stop(t0 + dur + 0.02);
      gain.connect(ctx.destination);
    }
  } catch (_) {
    // Bez zvuka (npr. preglednik bez Web Audija).
  }
}

/// Vibracija na mobitelu (Android Chrome; iOS Safari je ignorira).
void vibrate(List<int> pattern) {
  try {
    web.window.navigator.vibrate([for (final p in pattern) p.toJS].toJS);
  } catch (_) {}
}
