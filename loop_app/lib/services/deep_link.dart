import 'package:flutter/foundation.dart' show kIsWeb;

/// Dijeljena poveznica s kojom je aplikacija otvorena: `?item=<id>` (oglas)
/// ili `?shop=<korisničko ime>` (trgovina). Pamti se do prijave, a zatim
/// se jednom otvori.
class PendingLink {
  PendingLink._();

  static String? cloud;
  static String? cloudRoom;
  static String? item;
  static String? shop;

  /// Lista želja: "korisnikId.listaId".
  static String? list;

  /// Live aukcija (ID emisije).
  static String? live;

  /// Aukcija (ID).
  static String? auction;

  /// Novi oglas ili live (`item` / `live`) — npr. nakon osvježavanja.
  static String? create;

  /// Tab na početnoj (`live`, `following`, `moje`, `profil`).
  static String? tab;

  static bool get isPending =>
      cloud != null ||
      item != null ||
      shop != null ||
      list != null ||
      live != null ||
      auction != null ||
      create != null ||
      tab != null;

  /// Čita parametre iz adrese (samo web).
  static void readFromUrl([Uri? uri]) {
    if (uri == null && !kIsWeb) return;
    final q = (uri ?? Uri.base).queryParameters;
    final i = q['item']?.trim();
    final s = q['shop']?.trim().replaceFirst('@', '');
    final l = q['list']?.trim();
    final v = q['live']?.trim();
    String? opt(String k) {
      final x = q[k]?.trim();
      return x == null || x.isEmpty ? null : x;
    }

    final cloudTarget = opt('cloud');
    cloud = const {'orders', 'live', 'catalog'}.contains(cloudTarget) ? cloudTarget : null;
    cloudRoom = cloud == 'live' ? opt('room') : null;
    auction = opt('auction');
    create = opt('new');
    tab = opt('tab');
    live = v == null || v.isEmpty ? null : v;
    list = l == null || !l.contains('.') ? null : l;
    item = i == null || i.isEmpty ? null : i;
    shop = s == null || s.isEmpty ? null : s.toLowerCase();
  }

  static void clear() {
    cloud = null;
    cloudRoom = null;
    auction = null;
    create = null;
    tab = null;
    item = null;
    shop = null;
    list = null;
    live = null;
  }
}
