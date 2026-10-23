import 'package:flutter/foundation.dart' show kIsWeb;

/// Dijeljena poveznica s kojom je aplikacija otvorena: `?item=<id>` (oglas)
/// ili `?shop=<korisničko ime>` (trgovina). Pamti se do prijave, a zatim
/// se jednom otvori.
class PendingLink {
  PendingLink._();

  static String? item;
  static String? shop;

  /// Lista želja: "korisnikId.listaId".
  static String? list;

  /// Live aukcija (ID emisije).
  static String? live;

  static bool get isPending =>
      item != null || shop != null || list != null || live != null;

  /// Čita parametre iz adrese (samo web).
  static void readFromUrl([Uri? uri]) {
    if (uri == null && !kIsWeb) return;
    final q = (uri ?? Uri.base).queryParameters;
    final i = q['item']?.trim();
    final s = q['shop']?.trim().replaceFirst('@', '');
    final l = q['list']?.trim();
    final v = q['live']?.trim();
    live = v == null || v.isEmpty ? null : v;
    list = l == null || !l.contains('.') ? null : l;
    item = i == null || i.isEmpty ? null : i;
    shop = s == null || s.isEmpty ? null : s.toLowerCase();
  }

  static void clear() {
    item = null;
    shop = null;
    list = null;
    live = null;
  }
}
