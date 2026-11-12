import 'package:flutter/widgets.dart';

import '../deep_link.dart';
import 'url_stub.dart' if (dart.library.js_interop) 'url_web.dart' as url;

/// Mjesto u aplikaciji zapisano u adresi stranice (`?item=…`, `?live=…`,
/// `?shop=…`, `?new=item`…). Osvježavanje stranice ga ponovno otvori
/// (vidi [PendingLink]), a isto mjesto se otvori i nakon prijave.
class AppPlace {
  const AppPlace(this.query);

  /// Upit bez `?`, npr. `item=abc`.
  final String query;

  static AppPlace of(String key, String value) =>
      AppPlace('$key=${Uri.encodeQueryComponent(value)}');

  /// Postavke rute s mjestom (za [MaterialPageRoute]).
  RouteSettings get settings => RouteSettings(arguments: this);
}

class AppLocation {
  AppLocation._();

  static final _routes = <Route<dynamic>>[];

  /// Početni zaslon (tab), npr. `tab=live`.
  static String _home = '';

  /// Objava koja se trenutno gleda u feedu na početnoj (live, oglas).
  static String? _feed;

  /// Kamo se vratiti nakon prijave (gost je htio licitirati, objaviti…).
  static (String, DateTime)? _returnTo;

  /// Najviši otvoreni ekran s mjestom (oglas, live, trgovina…).
  static String? get _route {
    // Ekrani starog navigatora (promjena jezika/teme gradi novi) otpadaju.
    _routes.removeWhere((r) => r.navigator == null);
    for (final r in _routes.reversed) {
      final a = r.settings.arguments;
      if (a is AppPlace) return a.query;
    }
    return null;
  }

  /// Mjesto u adresi: otvoreni ekran ili tab početne.
  static String get current => _route ?? _home;

  /// Gdje je korisnik sada (i objava u feedu) — za povratak nakon prijave.
  static String get here => _route ?? _feed ?? _home;

  static void setHome(String query) {
    _home = query;
    _apply();
  }

  static void setFeed(String? query) {
    _feed = query;
    _apply();
  }

  static void _apply() => url.replaceQuery(current);

  /// Gost je krenuo nešto napraviti — nakon prijave/registracije se otvara
  /// isto mjesto (aplikacija se nakon registracije gradi ispočetka).
  static void rememberForLogin([String? place]) {
    final q = place ?? here;
    _returnTo = q.isEmpty ? null : (q, DateTime.now());
  }

  /// Mjesto za povratak (jednom, najviše 15 minuta staro).
  static String? takeReturn() {
    final r = _returnTo;
    _returnTo = null;
    if (r == null) return null;
    if (DateTime.now().difference(r.$2) > const Duration(minutes: 15)) {
      return null;
    }
    return r.$1;
  }

  /// Korisnik je i dalje na mjestu za povratak (prijava nije ništa
  /// zatvorila) — povratak više ne treba.
  static void clearReturnIfHere() {
    final r = _returnTo;
    if (r != null && r.$1 == here) _returnTo = null;
  }

  /// Ponovno otvori mjesto: zapiše ga kao dijeljenu poveznicu.
  static void restore(String query) =>
      PendingLink.readFromUrl(Uri.parse('?$query'));
}

/// Prati otvorene ekrane i zapisuje mjesto u adresu.
class AppLocationObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLocation._routes.add(route);
    AppLocation._apply();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLocation._routes.remove(route);
    AppLocation._apply();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLocation._routes.remove(route);
    AppLocation._apply();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : AppLocation._routes.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      AppLocation._routes[i] = newRoute;
    } else if (newRoute != null) {
      AppLocation._routes.add(newRoute);
    }
    AppLocation._apply();
  }
}
