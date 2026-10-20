import '../models/app_user.dart';
import 'dart:math';

import '../models/device.dart';
import '../models/portfolio_point.dart';

/// Demo podaci koji se kreiraju pri prvom pokretanju (i nakon resetiranja).
class SeedData {
  static const demoUserId = 'user-demo';
  static const testUserId = 'user-test';

  static List<AppUser> users(DateTime now) => [
    AppUser(
      id: demoUserId,
      email: 'demo@loop.com',
      name: 'Demo Korisnik',
      credits: 1250,
      createdAt: now,
    ),
    AppUser(
      id: testUserId,
      email: 'test@loop.com',
      name: 'Test Korisnik',
      credits: 800,
      createdAt: now,
    ),
  ];

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
    return [
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
    ];
  }

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
    };
  }
}
