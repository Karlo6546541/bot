import 'boxnow_stub.dart'
    if (dart.library.js_interop) 'boxnow_web.dart'
    as impl;
import '../../l10n/tr.dart';
import 'lockers.dart';

export 'lockers.dart';

/// Paketomat (BOX NOW, GLS ili DPD) odabran na karti ili s popisa.
class BoxNowLocker {
  const BoxNowLocker({
    required this.id,
    required this.address,
    this.postalCode = '',
    this.name = '',
    this.network = LockerNetwork.boxNow,
  });

  final LockerNetwork network;

  /// ID paketomata (`boxnowLockerId`) — treba ga BOX NOW Partner API pri
  /// izradi pošiljke (`destination.locationId`).
  final String id;
  final String address;
  final String postalCode;
  final String name;

  /// Opis bez broja: "Konzum Ilica, Ilica 1, 10000".
  String get place => [
    if (name.isNotEmpty) name,
    address,
    if (postalCode.isNotEmpty) postalCode,
  ].join(', ');

  /// Zapis u pošiljci: "BOX NOW #1234 · Ilica 1, 10000" (ili "GLS #…").
  String get destination => '${network.prefix}$id · $place';

  /// Čita paketomat iz zapisa u pošiljci (null ako nije paketomat s
  /// kartom).
  static BoxNowLocker? parse(String? destination) {
    final d = destination?.trim() ?? '';
    final n = LockerNetwork.ofDestination(d);
    if (n == null) return null;
    final rest = d.substring(n.prefix.length);
    final sep = rest.indexOf(' · ');
    if (sep <= 0 || sep + 3 >= rest.length) return null;
    return BoxNowLocker(
      network: n,
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
  static Future<BoxNowPick> pick() =>
      impl.boxNowPick(partnerId, scriptUrl, Tr.lang.name);
}

/// Karte paketomata za sve mreže.
///
/// - BOX NOW: službeni widget ([BoxNow]).
/// - GLS: službena karta `gls-dpm` (web komponenta s GLS poslužitelja
///   države, npr. map.gls-croatia.com), samo paketomati
///   (`filter-type="parcel-locker"`). Adresa se može zamijeniti s
///   `--dart-define=GLS_WIDGET_JS=...`.
/// - DPD: karta DPD Pickup točaka u iframeu (`--dart-define=DPD_WIDGET_URL=...`,
///   URL daje DPD partneru); odabir stiže porukom (`postMessage`).
/// Bez karte (APK, nepoznata država) bira se s popisa paketomata.
/// Izrada pošiljke (MyGLS API, DPD API, BOX NOW Partner API) traži tajne
/// ključeve pa ide na poslužitelj; u demo verziji broj i PIN-ovi su
/// simulirani.
class LockerMaps {
  const LockerMaps._();

  static const glsScript = String.fromEnvironment('GLS_WIDGET_JS');
  static const dpdUrl = String.fromEnvironment('DPD_WIDGET_URL');

  /// GLS poslužitelji karte po državi.
  static const _glsHosts = {
    'HR': 'map.gls-croatia.com',
    'SI': 'map.gls-slovenia.com',
    'HU': 'map.gls-hungary.com',
    'CZ': 'map.gls-czech.com',
    'SK': 'map.gls-slovakia.sk',
    'RO': 'map.gls-romania.ro',
  };

  static String? _glsScriptFor(String country) {
    if (glsScript.isNotEmpty) return glsScript;
    final host = _glsHosts[country];
    return host == null ? null : 'https://$host/widget/gls-dpm.js';
  }

  /// Ima li mreža kartu za tu državu (i je li ovo preglednik).
  static bool available(LockerNetwork n, String country) {
    if (!impl.boxNowAvailable) return false;
    return switch (n) {
      LockerNetwork.boxNow => country == 'HR' || country == 'GR',
      LockerNetwork.gls => _glsScriptFor(country) != null,
      LockerNetwork.dpd => dpdUrl.isNotEmpty,
    };
  }

  /// Zatvara otvorene karte (Natrag dok je karta otvorena).
  static void closeAll() => impl.closeMaps();

  static Future<BoxNowPick> pick(LockerNetwork n, String country) {
    if (!available(n, country)) {
      return Future.value(const BoxNowUnavailable());
    }
    return switch (n) {
      LockerNetwork.boxNow => BoxNow.pick(),
      LockerNetwork.gls => impl.glsPick(
        _glsScriptFor(country)!,
        country.toLowerCase(),
      ),
      LockerNetwork.dpd => impl.dpdPick(dpdUrl, country),
    };
  }
}
