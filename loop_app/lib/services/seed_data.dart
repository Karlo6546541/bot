import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/auction.dart';
import '../models/device.dart';
import '../models/portfolio_point.dart';
import '../models/seller_info.dart';
import '../models/story.dart';

/// Demo podaci koji se kreiraju pri prvom pokretanju (i nakon resetiranja).
class SeedData {
  static const demoUserId = 'user-demo';
  static const testUserId = 'user-test';
  static const anaUserId = 'user-ana';
  static const markoUserId = 'user-marko';

  /// Markova zarada za isplatu (ponude na aukcijama se ne blokiraju —
  /// pobjednik plaća karticom na kraju).
  static const _markoTotal = 1500.0;

  /// Lozinka svih demo računa.
  static const demoPassword = 'demo';

  /// Unaprijed izračunat sažetak lozinke "demo" (vidi `LocalAuthBackend`).
  static Map<String, dynamic> demoCredential(String userId) => {
    'userId': userId,
    'salt': _demoSalt,
    'hash': _demoHash,
  };

  static const _demoSalt = 'loop-demo-salt';
  static const _demoHash = 'QkOJINXrf3/IutVq32Dzqw9rndFQ03vBTz2lR2YhzR0=';

  static List<AppUser> users(DateTime now) => [
    AppUser(
      id: demoUserId,
      username: 'demo',
      emailVerified: true,
      email: 'demo@loop.com',
      name: 'Demo Korisnik',
      credits: 1250,
      createdAt: now,
      // Izmišljeni podaci ispravnog oblika (ne pripadaju stvarnoj osobi).
      address: 'Ilica 1, 10000 Zagreb',
      paymentCard: kDemoCard,
      seller: SellerInfo(
        legalName: 'Demo Korisnik',
        oib: '12345678903',
        birthDate: DateTime(1990, 1, 1),
        address: 'Ilica 1, 10000 Zagreb',
        iban: 'HR2523400091111111111',
        updatedAt: now,
      ),
    ),
    AppUser(
      id: testUserId,
      username: 'test',
      emailVerified: true,
      email: 'test@loop.com',
      name: 'Test Korisnik',
      credits: 800,
      createdAt: now,
      address: 'Ilica 1, 10000 Zagreb',
      paymentCard: kDemoCard,
      seller: SellerInfo(
        legalName: 'Test Korisnik',
        oib: '23456789013',
        birthDate: DateTime(1992, 2, 2),
        address: 'Ilica 1, 10000 Zagreb',
        iban: 'HR8024020062222222222',
        updatedAt: now,
      ),
    ),
    AppUser(
      id: anaUserId,
      username: 'ana.kolekcija',
      emailVerified: true,
      email: 'ana@loop.com',
      name: 'Ana Kolekcionarka',
      credits: 400,
      createdAt: now,
      address: 'Korzo 1, 51000 Rijeka',
      paymentCard: kDemoCard,
      seller: SellerInfo(
        legalName: 'Ana Demo',
        oib: '34567890125',
        birthDate: DateTime(1995, 4, 4),
        address: 'Korzo 1, 51000 Rijeka',
        iban: 'HR6724840083333333333',
        updatedAt: now,
      ),
    ),
    AppUser(
      id: markoUserId,
      username: 'marko',
      emailVerified: true,
      email: 'marko@loop.com',
      name: 'Marko',
      credits: _markoTotal,
      createdAt: now,
      address: 'Riva 1, 21000 Split',
      paymentCard: kDemoCard,
      seller: SellerInfo(
        legalName: 'Marko Demo',
        oib: '45678901239',
        birthDate: DateTime(1988, 3, 3),
        address: 'Riva 1, 21000 Split',
        iban: 'HR0523600004444444444',
        updatedAt: now,
      ),
    ),
  ];

  static const _descriptions = {
    'Kocka za kalibraciju':
        'Klasična kocka 20 × 20 × 20 mm za provjeru dimenzija i kalibraciju '
        '3D printera. Datoteka: STL, odmah nakon kupnje.',
    'Predložak plakata':
        'Jednostavan A4 plakat u SVG formatu — otvori u Inkscapeu, Figmi ili '
        'Illustratoru, promijeni tekst i boje.',
    'iPhone 15 Pro':
        'Kupljen u Hrvatskoj, korišten 8 mjeseci uvijek s maskicom i '
        'zaštitnim staklom. Baterija 94%. Uz mobitel originalna kutija i '
        'USB-C kabel. Bez ogrebotina na ekranu.',
    'MacBook Air M3':
        'Odličan za faks i posao. Nekoliko sitnih tragova korištenja na '
        'poklopcu, ekran i tipkovnica besprijekorni. 112 ciklusa baterije, '
        'dolazi s originalnim punjačem.',
    'Charizard Holo':
        'Base Set Charizard holo, čuvan u zaštitnoj foliji i toploaderu. '
        'Rubovi lagano istrošeni, holo bez ogrebotina. Nije gradiran.',
    'Električna gitara':
        'Fender Squier Stratocaster, sunburst. Nove žice, podešen vrat. '
        'Uz gitaru ide mekana torba i kabel od 3 m.',
    'Keramička šalica':
        'Ručno oblikovana na kolu i glazirana u tirkiznoj boji. '
        'Svaki komad je unikat. Može u perilicu posuđa.',
    'Radionica keramike':
        'Termin od 3 sata u ateljeu u Zagrebu: rad na kolu, materijal i '
        'pečenje uključeni. Gotove radove preuzimaš za dva tjedna.',
    'iPhone 13':
        'Ispravan, baterija 86%. Sitna ogrebotina u kutu ekrana, '
        'ne vidi se kad je ekran upaljen.',
  };

  static List<Device> devices(DateTime now) {
    var i = 0;
    Device d(
      String name,
      String model,
      DeviceCondition condition,
      double price,
      DeviceCategory category, [
      String? ownerId,
    ]) {
      i++;
      return Device(
        id: 'seed-$i',
        name: name,
        model: model,
        condition: condition,
        price: price,
        category: category,
        ownerId: ownerId,
        // Različita vremena kako bi redoslijed u listama bio stabilan.
        createdAt: now.subtract(Duration(minutes: i)),
      );
    }

    const nw = DeviceCondition.brandNew;
    const ex = DeviceCondition.excellent;
    const vg = DeviceCondition.veryGood;
    const gd = DeviceCondition.good;
    final list = [
      // Market (nisu ničiji)
      d('iPhone 15 Pro', '256GB', ex, 780, DeviceCategory.phone),
      d('MacBook Air M3', '16/512', vg, 1120, DeviceCategory.laptop),
      d('Samsung Galaxy S24', '256GB', ex, 610, DeviceCategory.phone),
      d('iPad Air M2', '128GB', vg, 490, DeviceCategory.tablet),
      d('AirPods Pro 2', 'USB-C', ex, 185, DeviceCategory.audio),
      d('iPhone 14', '128GB', gd, 420, DeviceCategory.phone),
      d('MacBook Pro 14"', 'M3 Pro', ex, 1890, DeviceCategory.laptop),
      d('iPad Pro 11"', 'M2', vg, 720, DeviceCategory.tablet),
      // Portfolio demo korisnika
      d('iPhone 13', '128GB', gd, 310, DeviceCategory.phone, demoUserId),
      d(
        'Laptop Lenovo',
        'ThinkPad',
        vg,
        450,
        DeviceCategory.laptop,
        demoUserId,
      ),
      // Dodatni uređaji u Marketu (novije kategorije)
      d('Apple Watch Series 9', '45mm', ex, 290, DeviceCategory.watch),
      d('Sony A7 III', 'Body', vg, 980, DeviceCategory.camera),
      d('PlayStation 5', 'Disc 825GB', vg, 380, DeviceCategory.console),
      d('Nintendo Switch OLED', '64GB', ex, 230, DeviceCategory.console),
      // Kolekcionarstvo
      d(
        'Charizard Holo',
        'Pokémon Base Set 1999',
        vg,
        450,
        DeviceCategory.cards,
      ),
      d(
        'Prigodna kovanica 25 kn',
        'Ulazak u EU, 2013.',
        ex,
        60,
        DeviceCategory.coins,
      ),
      d(
        'Album poštanskih maraka',
        'Jugoslavija 1960–1980',
        gd,
        120,
        DeviceCategory.stamps,
      ),
      d(
        'Star Wars figure',
        'Vintage Kenner, 6 kom',
        gd,
        210,
        DeviceCategory.figures,
      ),
      d(
        'Pink Floyd – The Dark Side of the Moon',
        'LP, 1973.',
        vg,
        140,
        DeviceCategory.vinyl,
      ),
      // Hobiji
      d(
        'Električna gitara',
        'Fender Squier Strat',
        vg,
        260,
        DeviceCategory.instruments,
      ),
      d('Brdski bicikl', 'Trek Marlin 5, M', gd, 520, DeviceCategory.sport),
      d(
        'Catan',
        'Osnovna igra + 2 proširenja',
        ex,
        55,
        DeviceCategory.boardGames,
      ),
      d(
        'Harry Potter 1–7',
        'Tvrdi uvez, HR izdanje',
        vg,
        70,
        DeviceCategory.books,
      ),
      d(
        'LEGO Millennium Falcon',
        '75257, složen',
        ex,
        130,
        DeviceCategory.models,
      ),
      // Rukotvorine
      d(
        'Keramička šalica',
        'Ručno rađena, 350 ml',
        nw,
        25,
        DeviceCategory.ceramics,
      ),
      d(
        'Pleteni džemper',
        'Merino vuna, vel. M',
        nw,
        80,
        DeviceCategory.textile,
      ),
      d('Srebrne naušnice', 'Ručni rad, 925', nw, 65, DeviceCategory.jewelry),
      d('Daska za rezanje', 'Masivni orah', nw, 45, DeviceCategory.woodwork),
      d(
        'Ulje na platnu',
        'Dalmatinska obala, 50×70',
        ex,
        220,
        DeviceCategory.paintings,
      ),
      // Aktivnosti
      d(
        'Radionica keramike',
        '1 termin, 3 h, Zagreb',
        nw,
        45,
        DeviceCategory.workshops,
      ),
      d('Poduka gitare', '4 sata, početnici', nw, 90, DeviceCategory.tutoring),
      d(
        'Ulaznica za koncert',
        'Arena Zagreb, parter',
        nw,
        60,
        DeviceCategory.tickets,
      ),
      d(
        'Ronjenje za početnike',
        'Krk, 1 dan s opremom',
        nw,
        120,
        DeviceCategory.experiences,
      ),
      // Predmeti koje Ana prodaje na aukcijama (vidi [auctions]).
      d(
        'Pokémon Base Set booster',
        'Zapečaćen, 1999.',
        ex,
        900,
        DeviceCategory.cards,
        anaUserId,
      ),
      d(
        'Polaroid SX-70',
        'Ispravan, s torbicom',
        vg,
        180,
        DeviceCategory.camera,
        anaUserId,
      ),
      d(
        'Akvarel – Stari grad Hvar',
        'Original, 40×30',
        nw,
        150,
        DeviceCategory.paintings,
        anaUserId,
      ),
      d(
        'Ulaznica – Ultra Europe',
        '3 dana, Split',
        nw,
        160,
        DeviceCategory.tickets,
        anaUserId,
      ),
      // Digitalno (LOOP Originals) — prave datoteke za isprobavanje.
      d(
        'Kocka za kalibraciju',
        '3D model · STL, 20 mm',
        nw,
        15,
        DeviceCategory.models3d,
      ),
      d(
        'Predložak plakata',
        'SVG · A4, uredivo',
        nw,
        20,
        DeviceCategory.templates,
      ),
      // Moda i Dom (novi odjeljci, dodani na kraj da ID-evi ostanu isti).
      d(
        'Nike Air Jordan 1',
        'Retro High OG, EU 43',
        ex,
        220,
        DeviceCategory.sneakers,
      ),
      d('Gramofon Lenco', 'Vintage, 1975.', vg, 140, DeviceCategory.vintage),
    ];
    // Opisi i datoteke za nekoliko demo predmeta.
    return [
      for (final dev in list)
        Device.fromMap({
          ...dev.toMap(),
          if (_descriptions[dev.name] != null)
            'description': _descriptions[dev.name],
          if (_files[dev.name] case final f?)
            'file': {
              'ref': 'local:${f.$1}',
              'name': f.$1.split('/').last,
              'size': utf8.encode(f.$2).length,
              'uploadedAt': now.toIso8601String(),
            },
        }),
    ];
  }

  /// Sadržaj demo datoteka (ključ u lokalnom spremištu → bajtovi).
  static Map<String, Uint8List> files() => {
    for (final f in _files.values) f.$1: utf8.encode(f.$2),
  };

  static final _files = <String, (String, String)>{
    'Kocka za kalibraciju': ('seed/kocka_20mm.stl', _cubeStl()),
    'Predložak plakata': ('seed/plakat_a4.svg', _posterSvg),
  };

  /// ASCII STL kocke 20×20×20 mm (12 trokuta).
  static String _cubeStl() {
    const s = 20.0;
    final v = [
      [0.0, 0.0, 0.0],
      [s, 0.0, 0.0],
      [s, s, 0.0],
      [0.0, s, 0.0],
      [0.0, 0.0, s],
      [s, 0.0, s],
      [s, s, s],
      [0.0, s, s],
    ];
    const faces = [
      [0, 2, 1, 0, 0, -1], [0, 3, 2, 0, 0, -1], // dno
      [4, 5, 6, 0, 0, 1], [4, 6, 7, 0, 0, 1], // vrh
      [0, 1, 5, 0, -1, 0], [0, 5, 4, 0, -1, 0], // prednja
      [2, 3, 7, 0, 1, 0], [2, 7, 6, 0, 1, 0], // stražnja
      [1, 2, 6, 1, 0, 0], [1, 6, 5, 1, 0, 0], // desna
      [0, 4, 7, -1, 0, 0], [0, 7, 3, -1, 0, 0], // lijeva
    ];
    final b = StringBuffer('solid loop_kocka\n');
    for (final f in faces) {
      b.writeln('  facet normal ${f[3]} ${f[4]} ${f[5]}');
      b.writeln('    outer loop');
      for (final i in f.take(3)) {
        final p = v[i];
        b.writeln('      vertex ${p[0]} ${p[1]} ${p[2]}');
      }
      b.writeln('    endloop');
      b.writeln('  endfacet');
    }
    b.writeln('endsolid loop_kocka');
    return b.toString();
  }

  static const _posterSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" width="210mm" height="297mm" viewBox="0 0 210 297">
  <rect width="210" height="297" fill="#FFF7EF"/>
  <rect x="15" y="15" width="180" height="267" rx="8" fill="none" stroke="#C8441E" stroke-width="2"/>
  <text x="105" y="90" font-family="sans-serif" font-size="22" font-weight="900" text-anchor="middle" fill="#2A1F17">NASLOV DOGAĐAJA</text>
  <text x="105" y="115" font-family="sans-serif" font-size="9" text-anchor="middle" fill="#76685D">Datum · mjesto · vrijeme</text>
  <circle cx="105" cy="185" r="45" fill="#FFE1D1"/>
  <text x="105" y="270" font-family="sans-serif" font-size="7" text-anchor="middle" fill="#76685D">Napravljeno s LOOP predloškom</text>
</svg>
''';

  /// Izmišljena povijest za demo korisnike, kako bi grafikon portfolija
  /// odmah imao što prikazati. Završava točno na početnom stanju iz seeda.
  static Map<String, List<PortfolioPoint>> history(DateTime now) {
    final rnd = Random(7); // fiksno sjeme = uvijek ista krivulja
    final demo = <PortfolioPoint>[];
    var credits = 900.0;
    var portfolio = 620.0;
    var day = 34.0;
    while (day > 1) {
      demo.add(
        PortfolioPoint(
          time: now.subtract(Duration(minutes: (day * 24 * 60).round())),
          credits: credits,
          portfolio: portfolio,
        ),
      );
      // Naizmjence "prodaje" i "kupnje" s blagim rastom.
      if (rnd.nextBool()) {
        credits += 40 + rnd.nextInt(160);
      } else {
        final delta = 30.0 + rnd.nextInt(140);
        portfolio += delta;
        credits -= delta * 0.7;
      }
      if (rnd.nextInt(5) == 0) portfolio -= 40 + rnd.nextInt(80);
      day -= 0.6 + rnd.nextDouble() * 2.2;
    }
    // Krivulju linearno "povlačimo" kroz vrijeme tako da glatko završi
    // točno na početnom stanju (1250 kredita + 760 portfolio), bez skoka.
    final last = demo.last;
    final creditGap = 1250 - last.credits;
    final portfolioGap = 760 - last.portfolio;
    final n = demo.length;
    final adjusted = [
      for (var i = 0; i < n; i++)
        PortfolioPoint(
          time: demo[i].time,
          credits: (demo[i].credits + creditGap * (i + 1) / n).roundToDouble(),
          portfolio: (demo[i].portfolio + portfolioGap * (i + 1) / n)
              .roundToDouble(),
        ),
      PortfolioPoint(
        time: now.subtract(const Duration(hours: 2)),
        credits: 1250,
        portfolio: 760,
      ),
    ];
    demo
      ..clear()
      ..addAll(adjusted);

    return {
      demoUserId: demo,
      testUserId: [
        PortfolioPoint(
          time: now.subtract(const Duration(days: 12)),
          credits: 800,
          portfolio: 0,
        ),
      ],
      anaUserId: [
        PortfolioPoint(
          time: now.subtract(const Duration(days: 9)),
          credits: 400,
          portfolio: 1390,
        ),
      ],
      markoUserId: [
        PortfolioPoint(
          time: now.subtract(const Duration(days: 9)),
          credits: _markoTotal,
          portfolio: 0,
        ),
      ],
    };
  }

  /// Demo aukcije: Ana prodaje, Marko i test korisnik licitiraju.
  /// ID-evi predmeta prate redoslijed u [devices] (seed-34 … seed-37).
  static List<Auction> auctions(DateTime now) {
    Bid bid(String userId, String label, double amount, int minutesAgo) => Bid(
      userId: userId,
      userLabel: label,
      amount: amount,
      time: now.subtract(Duration(minutes: minutesAgo)),
    );
    Auction a(
      String n,
      String deviceId,
      String name,
      double start,
      Duration endsIn,
      List<Bid> bids,
    ) => Auction(
      id: 'seed-auction-$n',
      deviceId: deviceId,
      deviceName: name,
      sellerId: anaUserId,
      sellerLabel: '@ana.kolekcija',
      startPrice: start,
      createdAt: now.subtract(const Duration(days: 1)),
      endsAt: now.add(endsIn),
      bids: bids,
    );

    return [
      a(
        '1',
        'seed-34',
        'Pokémon Base Set booster',
        300,
        const Duration(hours: 26),
        [
          bid(testUserId, '@test', 300, 600),
          bid(markoUserId, '@marko', 320, 300),
        ],
      ),
      a('2', 'seed-35', 'Polaroid SX-70', 60, const Duration(hours: 3), [
        bid(markoUserId, '@marko', 60, 120),
      ]),
      a(
        '3',
        'seed-36',
        'Akvarel – Stari grad Hvar',
        40,
        const Duration(days: 5),
        const [],
      ),
      a(
        '4',
        'seed-37',
        'Ulaznica – Ultra Europe',
        90,
        const Duration(minutes: 40),
        [bid(markoUserId, '@marko', 90, 30)],
      ),
    ];
  }

  /// Dnevne priče demo trgovina (Ana i Marko) da red s pričama nije prazan.
  /// Ne spremaju se u bazu: svaki dan nastaju nove (vrijede do ponoći).
  static List<Story> dailyStories(List<Device> devices, DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    final key = '${day.year}${day.month}${day.day}';
    final looks = [
      [
        StoryText(
          text: t('Novo stiglo! 👀'),
          y: 0.22,
          rotation: -0.08,
          size: 0.1,
          color: 0xFFFFFFFF,
          background: StoryTextBackground.solid,
        ),
        StoryText(
          text: t('samo danas'),
          y: 0.33,
          x: 0.62,
          size: 0.075,
          font: StoryFont.script,
          color: 0xFFFFD60A,
        ),
      ],
      [
        StoryText(
          text: t('Danas posebna ponuda ✨'),
          y: 0.25,
          size: 0.11,
          font: StoryFont.modern,
          color: 0xFFFFFFFF,
        ),
        StoryText(
          text: t('javi se u poruke'),
          y: 0.41,
          size: 0.055,
          font: StoryFont.typewriter,
          color: 0xFF34C759,
          background: StoryTextBackground.soft,
        ),
      ],
    ];
    final out = <Story>[];
    var i = 0;
    for (final user in const [anaUserId, markoUserId]) {
      final d = devices
          .where((d) => d.ownerId == user && d.isForSale)
          .firstOrNull;
      final texts = looks[i % looks.length];
      out.add(
        Story(
          id: 'demo-$user-$key',
          userId: user,
          text: texts.map((x) => x.text).join('\n'),
          texts: texts,
          deviceId: d?.id,
          color: i * 2,
          createdAt: day,
        ),
      );
      i++;
    }
    return out;
  }
}
