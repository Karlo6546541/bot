import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/services/auction_policy.dart';
import 'package:loop_app/services/auction_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  late Directory dir;
  late StorageService storage;
  late AuctionService auctions;
  late TradeService trade;
  const demo = SeedData.demoUserId;
  const tester = SeedData.testUserId;
  const hour = Duration(hours: 1);

  Future<Device> add(String user, double price) => trade.addDevice(
    userId: user,
    name: 'Predmet $price',
    model: 'x',
    condition: DeviceCondition.good,
    price: price,
    category: DeviceCategory.other,
  );

  Future<void> create(String user, String deviceId, {DateTime? now}) =>
      auctions.create(
        userId: user,
        deviceId: deviceId,
        startPrice: 10,
        duration: hour,
        now: now,
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('loop_policy');
    storage = StorageService();
    await storage.init(path: dir.path);
    auctions = AuctionService(storage);
    trade = TradeService(storage);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('naknada za objavu: 2% vrijednosti, najmanje 2 kredita', () async {
    expect(AuctionPolicy.listingFee(storage.deviceById('seed-9')!), 6.2);
    final cheap = await add(demo, 60);
    expect(AuctionPolicy.listingFee(cheap), 2);
  });

  test('objava naplaćuje naknadu i bilježi je u aktivnosti', () async {
    await create(demo, 'seed-9'); // iPhone 13, 310 → 6,20
    expect(storage.userById(demo)!.credits, 1243.8);
    final tx = storage.transactions.single;
    expect(tx.type, TransactionType.auctionFee);
    expect(tx.fee, 6.2);
  });

  test('predmeti ispod 50 kredita ne idu na aukciju', () async {
    final cheap = await add(demo, 30);
    await expectLater(create(demo, cheap.id), throwsA(isA<TradeException>()));
    expect(storage.userById(demo)!.credits, 1250); // bez naknade
  });

  test('limit aktivnih aukcija ovisi o statusu (Bronze = 2)', () async {
    final items = [for (var i = 0; i < 3; i++) await add(tester, 60)];
    expect(auctions.policy.statusOf(tester).label, 'Bronze');
    await create(tester, items[0].id);
    await create(tester, items[1].id);
    await expectLater(
      create(tester, items[2].id),
      throwsA(isA<TradeException>()),
    );
  });

  test('najviše 3 nove aukcije u 24 sata', () async {
    await trade.addCredits(demo, 5000); // Gold → limit 6 aktivnih
    final items = [for (var i = 0; i < 4; i++) await add(demo, 100)];
    final now = DateTime.now();
    for (var i = 0; i < 3; i++) {
      await create(demo, items[i].id, now: now);
    }
    await expectLater(
      create(demo, items[3].id, now: now),
      throwsA(isA<TradeException>()),
    );
    // Dan kasnije ponovno može.
    await create(demo, items[3].id, now: now.add(const Duration(hours: 25)));
  });

  test('neprodani predmet čeka 24 h prije ponovne objave', () async {
    final now = DateTime.now();
    await create(demo, 'seed-9', now: now);
    await auctions.settleExpired(now: now.add(hour * 2)); // bez ponuda
    await expectLater(
      create(demo, 'seed-9', now: now.add(hour * 3)),
      throwsA(isA<TradeException>()),
    );
    await create(demo, 'seed-9', now: now.add(hour * 26));
  });
}
