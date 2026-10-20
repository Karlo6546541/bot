import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/app_user.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/models/user_status.dart';
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

  test('fee je 5%', () {
    expect(feeFor(780), 39);
    expect(sellPayout(310), 294.5);
    expect(buyTotal(185), 194.25);
  });

  test('status po ukupnoj vrijednosti', () {
    expect(UserStatus.fromTotalValue(1999), UserStatus.bronze);
    expect(UserStatus.fromTotalValue(2000), UserStatus.silver);
    expect(UserStatus.fromTotalValue(5000), UserStatus.silver);
    expect(UserStatus.fromTotalValue(5001), UserStatus.gold);
  });

  test('seed: demo korisnik je Silver, 12 uređaja u Marketu', () {
    final state = AppState.fromStorage(storage);
    final demo = storage.userById(SeedData.demoUserId)!;
    expect(demo.credits, 1250);
    expect(state.devicesOf(demo.id), hasLength(2));
    expect(state.statusOf(demo), UserStatus.silver);
    expect(state.devices.where((d) => d.isOnMarket), hasLength(12));
  });

  test(
    'instant sell: krediti +95%, uređaj ide u Market, transakcija',
    () async {
      final tx = await trade.sell(
        userId: SeedData.demoUserId,
        deviceId: 'seed-9',
      );
      expect(tx.type, TransactionType.sell);
      expect(tx.amount, 294.5);
      expect(tx.fee, 15.5);
      expect(storage.userById(SeedData.demoUserId)!.credits, 1544.5);
      expect(storage.deviceById('seed-9')!.isOnMarket, isTrue);
      expect(storage.transactions, hasLength(1));
    },
  );

  test('ne može prodati tuđi uređaj', () async {
    expect(
      () => trade.sell(userId: SeedData.testUserId, deviceId: 'seed-9'),
      throwsA(isA<TradeException>()),
    );
  });

  test('instant buy: krediti −(cijena+5%), uređaj u portfoliju', () async {
    // AirPods Pro 2 = 185 → 194.25
    final tx = await trade.buy(userId: SeedData.testUserId, deviceId: 'seed-5');
    expect(tx.amount, 194.25);
    expect(storage.userById(SeedData.testUserId)!.credits, 605.75);
    expect(storage.deviceById('seed-5')!.ownerId, SeedData.testUserId);
  });

  test('kupnja bez dovoljno kredita baca grešku i ništa ne mijenja', () async {
    // MacBook Pro 1890 > 800 kredita
    await expectLater(
      trade.buy(userId: SeedData.testUserId, deviceId: 'seed-7'),
      throwsA(isA<TradeException>()),
    );
    expect(storage.userById(SeedData.testUserId)!.credits, 800);
    expect(storage.deviceById('seed-7')!.isOnMarket, isTrue);
    expect(storage.transactions, isEmpty);
  });

  test('dodavanje uređaja i login novog korisnika', () async {
    final user = await trade.login('novi@loop.com', 'x');
    expect(user.credits, TradeService.welcomeCredits);
    final d = await trade.addDevice(
      userId: user.id,
      name: 'PS5',
      model: 'Slim',
      condition: DeviceCondition.excellent,
      price: 400,
      category: DeviceCategory.console,
    );
    expect(storage.deviceById(d.id)!.ownerId, user.id);
    // Ponovna prijava istim e-mailom vraća istog korisnika.
    expect((await trade.login('NOVI@loop.com', 'y')).id, user.id);
  });

  test('admin: brisanje korisnika vraća uređaje u Market; reset', () async {
    await trade.deleteUser(SeedData.demoUserId);
    expect(storage.userById(SeedData.demoUserId), isNull);
    expect(storage.devices.every((d) => d.isOnMarket), isTrue);

    await storage.resetAll();
    expect(storage.users, hasLength(2));
    expect(storage.devices, hasLength(14));
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

  test('status: napredak do sljedećeg', () {
    expect(UserStatus.bronze.next, UserStatus.silver);
    expect(UserStatus.silver.nextThreshold, 5000);
    expect(UserStatus.gold.next, isNull);
  });
}
