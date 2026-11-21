import 'package:flutter/services.dart';

import 'live_sound_stub.dart'
    if (dart.library.js_interop) 'live_sound_web.dart'
    as impl;

/// Zvuk i vibracija u liveu: nadmašen, zadnjih 5 s, pobjeda, reakcija.
/// U pregledniku se zvukovi sintetiziraju (Web Audio) — bez datoteka.
/// [muted] postavlja soba (prekidač 🔊/🔇, pamti se).
class LiveSound {
  const LiveSound._();

  static bool muted = false;

  /// Netko je ponudio više od tebe: dva niska tona + jaka vibracija.
  static void outbid() {
    HapticFeedback.heavyImpact();
    impl.vibrate([120, 60, 120]);
    if (!muted) impl.tones([(330, 0.0, 0.12), (247, 0.14, 0.18)]);
  }

  /// Zadnjih 5 s: kratki "tik" (zadnja sekunda viši).
  static void tick({bool last = false}) {
    HapticFeedback.selectionClick();
    impl.vibrate([last ? 40 : 15]);
    if (!muted) impl.tones([(last ? 1320 : 880, 0.0, 0.05)], volume: 0.12);
  }

  /// Pobjeda: "cha-ching" (rastući akord) + vibracija.
  static void win() {
    HapticFeedback.heavyImpact();
    impl.vibrate([60, 40, 60, 40, 200]);
    if (!muted) {
      impl.tones([
        (1047, 0.0, 0.09),
        (1319, 0.08, 0.09),
        (1568, 0.16, 0.09),
        (2093, 0.24, 0.35),
      ]);
    }
  }

  /// Moja ponuda je prošla: lagani klik.
  static void bid() {
    HapticFeedback.lightImpact();
    impl.vibrate([20]);
    if (!muted) impl.tones([(660, 0.0, 0.06), (990, 0.06, 0.08)], volume: 0.1);
  }

  /// Reakcija: samo lagana vibracija.
  static void pop() {
    HapticFeedback.selectionClick();
    impl.vibrate([10]);
  }
}
