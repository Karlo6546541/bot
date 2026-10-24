import 'boxnow_stub.dart'
    if (dart.library.js_interop) 'boxnow_web.dart'
    as impl;

/// BOX NOW paketomat odabran na karti.
class BoxNowLocker {
  const BoxNowLocker({
    required this.id,
    required this.address,
    this.postalCode = '',
    this.name = '',
  });

  /// ID paketomata (`boxnowLockerId`) — treba ga BOX NOW Partner API pri
  /// izradi pošiljke (`destination.locationId`).
  final String id;
  final String address;
  final String postalCode;
  final String name;

  static const _prefix = 'BOX NOW #';

  /// Zapis u pošiljci: "BOX NOW #1234 · Ilica 1, 10000".
  String get destination =>
      '$_prefix$id · ${[if (name.isNotEmpty) name, address, if (postalCode.isNotEmpty) postalCode].join(', ')}';

  /// Čita paketomat iz zapisa u pošiljci (null ako nije BOX NOW).
  static BoxNowLocker? parse(String? destination) {
    final d = destination?.trim() ?? '';
    if (!d.startsWith(_prefix)) return null;
    final rest = d.substring(_prefix.length);
    final sep = rest.indexOf(' · ');
    if (sep <= 0 || sep + 3 >= rest.length) return null;
    return BoxNowLocker(
      id: rest.substring(0, sep),
      address: rest.substring(sep + 3),
    );
  }
}

/// Što je vratila karta.
sealed class BoxNowPick {
  const BoxNowPick();
}

/// Kupac je odabrao paketomat.
class BoxNowPicked extends BoxNowPick {
  const BoxNowPicked(this.locker);
  final BoxNowLocker locker;
}

/// Karta se nije učitala (nema mreže, blokirano…) — koristi se popis.
class BoxNowUnavailable extends BoxNowPick {
  const BoxNowUnavailable();
}

/// Karta je zatvorena bez odabira (otvorena je ponovno).
class BoxNowClosed extends BoxNowPick {
  const BoxNowClosed();
}

/// BOX NOW integracija (testna): službeni widget s kartom paketomata.
///
/// - Na webu se učitava BOX NOW skripta ([scriptUrl]) i otvara karta kao
///   skočni prozor; odabir stiže preko `afterSelect` (i `postMessage`).
/// - [partnerId] je ID partnera koji daje BOX NOW
///   (`--dart-define=BOXNOW_PARTNER_ID=...`); bez njega karta radi u
///   općem načinu.
/// - Izrada pošiljke (Partner API, `delivery-requests`) traži client
///   ID i tajni ključ, pa ide na poslužitelj (npr. Supabase Edge Function),
///   nikad u aplikaciju. U demo verziji status pošiljke je simuliran.
class BoxNow {
  static const partnerId = String.fromEnvironment('BOXNOW_PARTNER_ID');
  static const scriptUrl = String.fromEnvironment(
    'BOXNOW_WIDGET_JS',
    defaultValue: 'https://widget-cdn.boxnow.hr/map-widget/client/v5.js',
  );

  /// Karta postoji samo u pregledniku.
  static bool get available => impl.boxNowAvailable;

  /// Otvara kartu; završava kad kupac odabere paketomat (ili kad se karta
  /// ne može učitati). Ako kupac samo zatvori kartu, ne završava.
  static Future<BoxNowPick> pick() => impl.boxNowPick(partnerId, scriptUrl);
}
