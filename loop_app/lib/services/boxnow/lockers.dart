import '../../l10n/tr.dart';
import '../../models/country.dart';
import '../../models/delivery.dart';
import 'boxnow.dart';

/// Mreža paketomata s kartom, brojem pošiljke i PIN-ovima (kao BOX NOW).
/// Ostali paketomati (InPost, Foxpost…) upisuju se rukom.
enum LockerNetwork {
  boxNow('BOX NOW', 0xFF6BBE45, 'BOX NOW #'),
  gls('GLS', 0xFF061AB1, 'GLS #'),
  dpd('DPD', 0xFFDC0032, 'DPD #');

  const LockerNetwork(this.brand, this.color, this.prefix);

  final String brand;

  /// Boja brenda (ARGB).
  final int color;

  /// Početak zapisa u pošiljci ("GLS #2001-HRLOCK1 · …").
  final String prefix;

  /// Mreža dostavljača (null: nije paketomat s kartom).
  static LockerNetwork? ofCarrier(Carrier? c) {
    if (c == null || c.kind != CarrierKind.locker) return null;
    if (c.id.endsWith('-boxnow')) return boxNow;
    if (c.id.endsWith('-gls-locker')) return gls;
    if (c.id.endsWith('-dpd-locker')) return dpd;
    return null;
  }

  /// Mreža iz zapisa paketomata u pošiljci.
  static LockerNetwork? ofDestination(String? destination) {
    final d = destination?.trim() ?? '';
    for (final n in values) {
      if (d.startsWith(n.prefix)) return n;
    }
    return null;
  }

  /// Mreža pošiljke (stare pošiljke bez dostavljača su BOX NOW).
  static LockerNetwork ofDelivery(Delivery d) {
    final byDest = ofDestination(d.destination);
    if (byDest != null) return byDest;
    final c = d.carrier ?? '';
    if (c.startsWith('GLS')) return gls;
    if (c.startsWith('DPD')) return dpd;
    return boxNow;
  }

  /// Kako prodavač predaje paket.
  String get dropOffHint => switch (this) {
    boxNow => t(
      'Na bilo kojem BOX NOW paketomatu odaberi "Pošalji paket" i upiši PIN.',
    ),
    gls => t(
      'Na bilo kojem GLS paketomatu odaberi "Predaja paketa" i upiši PIN — ili paket predaj u GLS ParcelShopu.',
    ),
    dpd => t(
      'Na bilo kojem DPD Pickup paketomatu odaberi "Pošalji paket" i upiši PIN — ili paket predaj u DPD Pickup točki.',
    ),
  };

  /// Praćenje pošiljke, korak po korak.
  List<String> get eventLabels => [
    t('Pošiljka prijavljena u {0}', [brand]),
    t('Prodavač predao paket u paketomat'),
    t('{0}: u transportu', [brand]),
    t('Stiglo u paketomat kupca'),
    t('Kupac preuzeo paket'),
  ];
}

/// Demo paketomati (kad se karta ne učita ili nije dostupna, npr. u APK-u).
/// S pravim API-jem popis dolazi od dostavljača.
List<BoxNowLocker> demoLockers(LockerNetwork n, String countryCode) {
  final c = countryOf(countryCode);
  final spots = c.code == 'HR' ? _hrSpots : _spotsIn(_capitals[c.code] ?? '');
  final where = switch (n) {
    LockerNetwork.boxNow => const ['Konzum', 'Tisak', 'INA', 'Lidl'],
    LockerNetwork.gls => const ['GLS paketomat', 'SPAR', 'Studenac', 'OMV'],
    LockerNetwork.dpd => const [
      'DPD Pickup paketomat',
      'Kaufland',
      'Petrol',
      'Tisak',
    ],
  };
  return [
    for (var i = 0; i < spots.length; i++)
      BoxNowLocker(
        network: n,
        id: switch (n) {
          LockerNetwork.boxNow => '${c.code}${4100 + i * 7}',
          LockerNetwork.gls => '${2001 + i}-${c.code}LOCK${i + 1}',
          LockerNetwork.dpd => '${c.code}1${(3200 + i * 11)}',
        },
        name: '${where[i % where.length]} ${spots[i].$1}',
        address: spots[i].$2,
        postalCode: spots[i].$3,
      ),
  ];
}

const _hrSpots = [
  ('Zagreb', 'Trg bana Jelačića 1, Zagreb', '10000'),
  ('Zagreb', 'Avenija Dubrovnik 16, Zagreb', '10020'),
  ('Zagreb', 'Ilica 242, Zagreb', '10000'),
  ('Split', 'Domovinskog rata 49, Split', '21000'),
  ('Rijeka', 'Korzo 18, Rijeka', '51000'),
  ('Osijek', 'Trg Ante Starčevića 2, Osijek', '31000'),
  ('Zadar', 'Široka ulica 5, Zadar', '23000'),
  ('Pula', 'Giardini 2, Pula', '52100'),
];

List<(String, String, String)> _spotsIn(String city) => city.isEmpty
    ? const []
    : [
        (city, '${t('Centar')}, $city', ''),
        (city, '${t('Glavni kolodvor')}, $city', ''),
        (city, '${t('Trgovački centar')}, $city', ''),
      ];

const _capitals = {
  'SI': 'Ljubljana',
  'AT': 'Wien',
  'HU': 'Budapest',
  'IT': 'Roma',
  'DE': 'Berlin',
  'SK': 'Bratislava',
  'CZ': 'Praha',
  'PL': 'Warszawa',
  'RO': 'București',
  'BG': 'Sofia',
  'FR': 'Paris',
  'BE': 'Bruxelles',
  'NL': 'Amsterdam',
  'LU': 'Luxembourg',
  'DK': 'København',
  'ES': 'Madrid',
  'PT': 'Lisboa',
  'GR': 'Athína',
  'IE': 'Dublin',
  'SE': 'Stockholm',
  'FI': 'Helsinki',
  'EE': 'Tallinn',
  'LV': 'Rīga',
  'LT': 'Vilnius',
  'CY': 'Lefkosía',
  'MT': 'Valletta',
};
