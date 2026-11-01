import 'dart:math' as math;

import '../l10n/tr.dart';

/// Vrsta usluge dostavljača.
enum CarrierKind { courier, locker, post, express }

/// Dostavljač (GLS, DPD, pošta…) s cijenom za mali paket.
class Carrier {
  const Carrier(
    this.id,
    this.name,
    this.kind,
    this.cost,
    this.days, {
    this.international = false,
  });

  /// Jedinstveno, npr. 'hr-gls' ili 'intl-gls'.
  final String id;
  final String name;
  final CarrierKind kind;

  /// Cijena za mali paket (€); veći paketi dobivaju doplatu.
  final double cost;

  /// Približno trajanje ("1–2").
  final String days;
  final bool international;

  String get subtitle {
    final what = switch (kind) {
      CarrierKind.locker => t('Paketomat'),
      CarrierKind.post => t('Pošta na adresu'),
      CarrierKind.express => t('Ekspres na adresu'),
      CarrierKind.courier => t('Kurir na adresu'),
    };
    return '$what · ${t('{0} dana', [days])}';
  }
}

/// Država računa: zastavica, lokalni dostavljači i položaj (za cijenu
/// slanja u drugu državu).
class Country {
  const Country(
    this.code,
    this._nameHr,
    this.flag,
    this.lat,
    this.lon,
    this.carriers,
  );

  final String code;
  final String _nameHr;
  String get name => t(_nameHr);
  String get nameHr => _nameHr;
  final String flag;
  final double lat;
  final double lon;

  /// Dostavljači unutar države.
  final List<Carrier> carriers;

  String get label => '$flag $name';
}

List<Carrier> _std(
  String code,
  String post, {
  double base = 5,
  List<Carrier> extra = const [],
}) => [
  Carrier('$code-gls', 'GLS', CarrierKind.courier, base, '1–2'),
  Carrier('$code-dpd', 'DPD', CarrierKind.courier, base + 0.5, '1–2'),
  Carrier('$code-post', post, CarrierKind.post, base - 1, '2–4'),
  Carrier(
    '$code-gls-locker',
    'GLS paketomat',
    CarrierKind.locker,
    base - 1.5,
    '1–2',
  ),
  Carrier(
    '$code-dpd-locker',
    'DPD Pickup paketomat',
    CarrierKind.locker,
    base - 1.5,
    '1–3',
  ),
  ...extra,
];

/// Države (Hrvatska + EU). Imena su hrvatska (prevode se preko t()).
const _hr = 'HR';
final kCountries = <Country>[
  Country(_hr, 'Hrvatska', '🇭🇷', 45.8, 16.0, [
    const Carrier('hr-boxnow', 'BOX NOW', CarrierKind.locker, 3, '1–2'),
    const Carrier(
      'hr-gls-locker',
      'GLS paketomat',
      CarrierKind.locker,
      3.5,
      '1–2',
    ),
    const Carrier(
      'hr-dpd-locker',
      'DPD Pickup paketomat',
      CarrierKind.locker,
      3.5,
      '1–3',
    ),
    const Carrier('hr-gls', 'GLS', CarrierKind.courier, 5, '1–2'),
    const Carrier('hr-dpd', 'DPD', CarrierKind.courier, 5.5, '1–2'),
    const Carrier(
      'hr-overseas',
      'Overseas Express',
      CarrierKind.courier,
      5,
      '1–2',
    ),
    const Carrier('hr-post', 'Hrvatska pošta', CarrierKind.post, 4, '2–4'),
    const Carrier('hr-express', 'GLS Express', CarrierKind.express, 12, '0–1'),
  ]),
  Country('SI', 'Slovenija', '🇸🇮', 46.1, 14.8, _std('si', 'Pošta Slovenije')),
  Country(
    'AT',
    'Austrija',
    '🇦🇹',
    47.6,
    14.1,
    _std('at', 'Österreichische Post', base: 6),
  ),
  Country(
    'HU',
    'Mađarska',
    '🇭🇺',
    47.2,
    19.4,
    _std(
      'hu',
      'Magyar Posta',
      extra: const [
        Carrier('hu-foxpost', 'Foxpost', CarrierKind.locker, 3, '1–2'),
      ],
    ),
  ),
  Country(
    'IT',
    'Italija',
    '🇮🇹',
    42.8,
    12.6,
    _std(
      'it',
      'Poste Italiane',
      base: 6,
      extra: const [Carrier('it-brt', 'BRT', CarrierKind.courier, 6, '1–3')],
    ),
  ),
  Country(
    'DE',
    'Njemačka',
    '🇩🇪',
    51.1,
    10.4,
    _std(
      'de',
      'Deutsche Post',
      base: 5,
      extra: const [
        Carrier('de-dhl', 'DHL', CarrierKind.courier, 5, '1–2'),
        Carrier('de-hermes', 'Hermes', CarrierKind.courier, 4.5, '2–3'),
      ],
    ),
  ),
  Country(
    'SK',
    'Slovačka',
    '🇸🇰',
    48.7,
    19.7,
    _std('sk', 'Slovenská pošta', base: 4),
  ),
  Country(
    'CZ',
    'Češka',
    '🇨🇿',
    49.8,
    15.5,
    _std(
      'cz',
      'Česká pošta',
      base: 4,
      extra: const [
        Carrier('cz-zasilkovna', 'Zásilkovna', CarrierKind.locker, 3, '1–2'),
      ],
    ),
  ),
  Country(
    'PL',
    'Poljska',
    '🇵🇱',
    52.0,
    19.1,
    _std(
      'pl',
      'Poczta Polska',
      base: 4,
      extra: const [
        Carrier('pl-inpost', 'InPost Paczkomat', CarrierKind.locker, 3, '1–2'),
      ],
    ),
  ),
  Country(
    'RO',
    'Rumunjska',
    '🇷🇴',
    45.9,
    24.9,
    _std(
      'ro',
      'Poșta Română',
      base: 4,
      extra: const [
        Carrier('ro-fan', 'FAN Courier', CarrierKind.courier, 4, '1–2'),
      ],
    ),
  ),
  Country(
    'BG',
    'Bugarska',
    '🇧🇬',
    42.7,
    25.5,
    _std(
      'bg',
      'Bulgarian Posts',
      base: 4,
      extra: const [
        Carrier('bg-econt', 'Econt', CarrierKind.courier, 4, '1–2'),
      ],
    ),
  ),
  Country(
    'FR',
    'Francuska',
    '🇫🇷',
    46.6,
    2.2,
    _std(
      'fr',
      'La Poste Colissimo',
      base: 6,
      extra: const [
        Carrier(
          'fr-mondialrelay',
          'Mondial Relay',
          CarrierKind.locker,
          4,
          '2–4',
        ),
      ],
    ),
  ),
  Country('BE', 'Belgija', '🇧🇪', 50.5, 4.5, _std('be', 'bpost', base: 6)),
  Country('NL', 'Nizozemska', '🇳🇱', 52.1, 5.3, _std('nl', 'PostNL', base: 6)),
  Country(
    'LU',
    'Luksemburg',
    '🇱🇺',
    49.8,
    6.1,
    _std('lu', 'POST Luxembourg', base: 6),
  ),
  Country('DK', 'Danska', '🇩🇰', 56.3, 9.5, _std('dk', 'PostNord', base: 7)),
  Country(
    'ES',
    'Španjolska',
    '🇪🇸',
    40.5,
    -3.7,
    _std(
      'es',
      'Correos',
      base: 6,
      extra: const [Carrier('es-seur', 'SEUR', CarrierKind.courier, 6, '1–2')],
    ),
  ),
  Country('PT', 'Portugal', '🇵🇹', 39.4, -8.2, _std('pt', 'CTT', base: 6)),
  Country(
    'GR',
    'Grčka',
    '🇬🇷',
    39.1,
    21.8,
    _std(
      'gr',
      'ELTA',
      base: 5,
      extra: const [
        Carrier('gr-boxnow', 'BOX NOW', CarrierKind.locker, 3, '1–2'),
      ],
    ),
  ),
  Country('IE', 'Irska', '🇮🇪', 53.4, -8.2, _std('ie', 'An Post', base: 7)),
  Country('SE', 'Švedska', '🇸🇪', 60.1, 18.6, _std('se', 'PostNord', base: 7)),
  Country('FI', 'Finska', '🇫🇮', 61.9, 25.7, _std('fi', 'Posti', base: 7)),
  Country('EE', 'Estonija', '🇪🇪', 58.6, 25.0, _std('ee', 'Omniva', base: 5)),
  Country(
    'LV',
    'Latvija',
    '🇱🇻',
    56.9,
    24.6,
    _std('lv', 'Latvijas Pasts', base: 5),
  ),
  Country('LT', 'Litva', '🇱🇹', 55.2, 23.9, _std('lt', 'LP Express', base: 5)),
  Country(
    'CY',
    'Cipar',
    '🇨🇾',
    35.1,
    33.4,
    _std('cy', 'Cyprus Post', base: 6),
  ),
  Country('MT', 'Malta', '🇲🇹', 35.9, 14.4, _std('mt', 'MaltaPost', base: 6)),
];

/// Država po kodu (zadano Hrvatska).
Country countryOf(String? code) => kCountries.firstWhere(
  (c) => c.code == code,
  orElse: () => kCountries.first,
);

/// Država po (hrvatskom ili prevedenom) imenu, npr. s kraja adrese.
Country? countryNamed(String? name) {
  final n = name?.trim();
  if (n == null || n.isEmpty) return null;
  for (final c in kCountries) {
    if (c.nameHr == n || c.name == n) return c;
  }
  return null;
}

/// Udaljenost između glavnih točaka dviju država (km).
double distanceKm(Country a, Country b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLon = rad(b.lon - a.lon);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// Dostavljači za slanje iz jedne države u drugu; cijena raste s
/// udaljenošću (do 700 km, do 1500 km, dalje).
List<Carrier> internationalCarriers(Country from, Country to) {
  final km = distanceKm(from, to);
  final (double base, String days) = km < 700
      ? (10, '2–4')
      : km < 1500
      ? (14, '3–5')
      : (19, '4–7');
  return [
    Carrier(
      'intl-gls',
      'GLS Europe',
      CarrierKind.courier,
      base,
      days,
      international: true,
    ),
    Carrier(
      'intl-dpd',
      'DPD Classic',
      CarrierKind.courier,
      base + 1,
      days,
      international: true,
    ),
    Carrier(
      'intl-post',
      '${from.carriers.where((c) => c.kind == CarrierKind.post).firstOrNull?.name ?? t('Pošta')} (${t('međunarodno')})',
      CarrierKind.post,
      base - 2,
      '5–10',
      international: true,
    ),
  ];
}
