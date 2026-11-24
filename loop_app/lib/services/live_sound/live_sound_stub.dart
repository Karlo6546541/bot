import 'package:flutter/services.dart';

/// Aplikacija: sistemski zvuk umjesto sintetiziranih tonova.
void tones(List<(double, double, double)> notes, {double volume = 0.18}) =>
    SystemSound.play(SystemSoundType.click);

/// Vibracija ide preko HapticFeedback (u [LiveSound]).
void vibrate(List<int> pattern) {}
