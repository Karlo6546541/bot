import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/app_user.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/services/fee.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  late Directory dir;
  late StorageService storage;
  late TradeService trade;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('loop_test');
    storage = StorageService();
    await storage.init(path: dir.path);
    trade = TradeService(storage);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('naknada 2% plaća samo kupac', () {
    expect(feeFor(780), 15.6);
    expect(sellPayout(310), 310);
    expect(buyTotal(185), 188.7);
  });

  test(
    'seed: demo korisnik ima 2 predmeta, 33 predmeta u Marketu (2 digitalna)',
    () {
      final state = AppState.fromStorage(storage);
      final demo = storage.userById(SeedData.demoUserId)!;
      expect(demo.credits, 1250);
      expect(state.devicesOf(demo.id), hasLength(2));
      expect(state.devices.where((d) => d.isOnMarket), hasLength(33));
    },
  );

  test('instant sell: puna cijena, uređaj ide u Market, transakcija', () async {
    final tx = await trade.sell(
      userId: SeedData.demoUserId,
      deviceId: 'seed-9',
    );
    expect(tx.type, TransactionType.sell);
    expect(tx.amount, 310);
    expect(tx.fee, 0);
    expect(storage.userById(SeedData.demoUserId)!.credits, 1560);
    expect(storage.deviceById('seed-9')!.isOnMarket, isTrue);
    expect(storage.transactions, hasLength(1));
  });

  test('ne može prodati tuđi uređaj', () async {
    expect(
      () => trade.sell(userId: SeedData.testUserId, deviceId: 'seed-9'),
      throwsA(isA<TradeException>()),
    );
  });

  test(
    'kupnja: kupac plaća karticom (cijena + 2 %), predmet je njegov',
    () async {
      // AirPods Pro 2 = 185 → 188.70
      final tx = await trade.buy(
        userId: SeedData.testUserId,
        deviceId: 'seed-5',
      );
      expect(tx.amount, 188.7);
      expect(storage.userById(SeedData.testUserId)!.credits, 800);
      expect(storage.deviceById('seed-5')!.ownerId, SeedData.testUserId);
    },
  );

  test('skupa kupnja ne ovisi o stanju (kartica)', () async {
    // MacBook Pro 1890 > 800 zarade — plaća se karticom.
    final tx = await trade.buy(userId: SeedData.testUserId, deviceId: 'seed-7');
    expect(tx.amount, 1927.8);
    expect(storage.userById(SeedData.testUserId)!.credits, 800);
    expect(storage.deviceById('seed-7')!.ownerId, SeedData.testUserId);
  });

  test('dodavanje uređaja', () async {
    final d = await trade.addDevice(
      userId: SeedData.testUserId,
      name: 'PS5',
      model: 'Slim',
      condition: DeviceCondition.excellent,
      price: 400,
      category: DeviceCategory.console,
    );
    expect(storage.deviceById(d.id)!.ownerId, SeedData.testUserId);
  });

  test('admin: brisanje korisnika vraća uređaje u Market; reset', () async {
    await trade.deleteUser(SeedData.demoUserId);
    expect(storage.userById(SeedData.demoUserId), isNull);
    expect(
      storage.devices.where((d) => d.ownerId == SeedData.demoUserId),
      isEmpty,
    );

    await storage.resetAll();
    expect(storage.users, hasLength(4));
    expect(storage.devices, hasLength(39));
  });

  test('favoriti: dodavanje i uklanjanje', () async {
    expect(await trade.toggleFavorite(SeedData.testUserId, 'seed-1'), isTrue);
    expect(storage.userById(SeedData.testUserId)!.favorites, ['seed-1']);
    expect(await trade.toggleFavorite(SeedData.testUserId, 'seed-1'), isFalse);
    expect(storage.userById(SeedData.testUserId)!.favorites, isEmpty);
  });

  test('stari zapis korisnika bez favorita se učitava', () {
    final u = AppUser.fromMap({
      'id': 'x',
      'email': 'x@loop.com',
      'name': 'x',
      'credits': 1,
      'createdAt': DateTime(2026).toIso8601String(),
    });
    expect(u.favorites, isEmpty);
  });

  test('svaki odjeljak ima demo predmete u Marketu', () {
    final market = storage.devices.where((d) => d.isOnMarket);
    for (final sec in ItemSection.values) {
      expect(
        market.where((d) => d.section == sec),
        isNotEmpty,
        reason: sec.label,
      );
    }
  });

  test(
    'povijest: seed završava na trenutnoj vrijednosti, prodaja dodaje točku',
    () async {
      final before = storage.historyOf(SeedData.demoUserId);
      expect(before.length, greaterThan(5));
      expect(before.last.total, 2010);

      await trade.sell(userId: SeedData.demoUserId, deviceId: 'seed-9');
      final after = storage.historyOf(SeedData.demoUserId);
      expect(after.length, before.length + 1);
      // 1250 + 310 €, portfolio samo Lenovo (450)
      expect(after.last.credits, 1560);
      expect(after.last.portfolio, 450);
    },
  );

  test(
    'fotografije: samo vlasnik ih mijenja, brisanje vraća putanje',
    () async {
      await trade.setImages(SeedData.demoUserId, 'seed-9', ['/tmp/a.jpg']);
      expect(storage.deviceById('seed-9')!.imagePaths, ['/tmp/a.jpg']);
      expect(
        () => trade.setImages(SeedData.testUserId, 'seed-9', const []),
        throwsA(isA<TradeException>()),
      );
      // Fotografije prate predmet i nakon prodaje.
      await trade.sell(userId: SeedData.demoUserId, deviceId: 'seed-9');
      expect(storage.deviceById('seed-9')!.imagePaths, ['/tmp/a.jpg']);
      expect(await trade.deleteDevice('seed-9'), ['/tmp/a.jpg']);
    },
  );

  test('stari zapis predmeta bez fotografija se učitava', () {
    final d = Device.fromMap({
      'id': 'x',
      'name': 'x',
      'model': 'x',
      'condition': 'good',
      'price': 1,
      'category': 'phone',
      'createdAt': DateTime(2026).toIso8601String(),
    });
    expect(d.imagePaths, isEmpty);
    expect(d.section, ItemSection.electronics);
  });
}
