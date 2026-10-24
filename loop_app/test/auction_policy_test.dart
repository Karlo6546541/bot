import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/models/seller_info.dart';
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

  test('objava aukcije je besplatna', () async {
    expect(AuctionPolicy.listingFee(storage.deviceById('seed-9')!), 0);
    final cheap = await add(demo, 60);
    expect(AuctionPolicy.listingFee(cheap), 0);
    await create(demo, 'seed-9');
    expect(storage.userById(demo)!.credits, 1250);
    expect(
      storage.transactions.where((t) => t.type == TransactionType.auctionFee),
      isEmpty,
    );
  });

  test('predmeti ispod 1 € ne idu na aukciju', () async {
    final cheap = await add(demo, 0.5);
    await expectLater(create(demo, cheap.id), throwsA(isA<TradeException>()));
    expect(storage.userById(demo)!.credits, 1250); // bez naknade
  });

  test('najviše ${AuctionPolicy.maxActive} aktivne aukcije', () async {
    final n = AuctionPolicy.maxActive;
    final items = [for (var i = 0; i <= n; i++) await add(tester, 60)];
    final now = DateTime.now();
    for (var i = 0; i < n; i++) {
      // Dnevni limit ne smije smetati: svaka aukcija drugog dana.
      await create(tester, items[i].id, now: now.add(Duration(days: i)));
    }
    expect(auctions.policy.activeCount(tester), n);
    await expectLater(
      create(tester, items[n].id, now: now.add(Duration(days: n))),
      throwsA(isA<TradeException>()),
    );
  });

  test(
    'najviše ${AuctionPolicy.maxNewPerDay} novih aukcija u 24 sata',
    () async {
      const n = AuctionPolicy.maxNewPerDay;
      final items = [for (var i = 0; i <= n; i++) await add(tester, 100)];
      final now = DateTime.now();
      for (var i = 0; i < n; i++) {
        await create(tester, items[i].id, now: now);
      }
      await expectLater(
        create(tester, items[n].id, now: now),
        throwsA(isA<TradeException>()),
      );
      // Dan kasnije ponovno može (prve su završile).
      await auctions.settleExpired(now: now.add(const Duration(hours: 25)));
      await create(
        tester,
        items[n].id,
        now: now.add(const Duration(hours: 25)),
      );
    },
  );

  test('trgovac (obrt/tvrtka) ima veća ograničenja', () async {
    final user = storage.userById(tester)!;
    await storage.putUser(
      user.copyWith(
        seller: SellerInfo(
          kind: SellerKind.business,
          companyName: 'Retro Kutak j.d.o.o.',
          legalName: 'Ivo Ivić',
          oib: '12345678903',
          address: 'Ilica 1, Zagreb',
          iban: 'HR2523400091111111111',
          contactEmail: 'info@retrokutak.hr',
          contactPhone: '+385 91 123 4567',
          updatedAt: DateTime(2026),
        ),
      ),
    );
    expect(
      auctions.policy.maxActiveFor(tester),
      AuctionPolicy.businessMaxActive,
    );
    expect(auctions.policy.maxActiveFor(demo), AuctionPolicy.maxActive);
    // Više od dnevnog limita privatne osobe u istom danu.
    const n = AuctionPolicy.maxNewPerDay + 2;
    final items = [for (var i = 0; i < n; i++) await add(tester, 100)];
    final now = DateTime.now();
    for (final d in items) {
      await create(tester, d.id, now: now);
    }
    expect(auctions.policy.activeCount(tester), n);
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
