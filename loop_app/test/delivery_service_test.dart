import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/app_notification.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/services/auction_service.dart';
import 'package:loop_app/services/boxnow/boxnow.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  late Directory dir;
  late StorageService storage;
  late DeliveryService deliveries;
  const demo = SeedData.demoUserId;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('loop_delivery');
    storage = StorageService();
    await storage.init(path: dir.path);
    deliveries = DeliveryService(storage);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('aktivnosti imaju samo digitalnu dostavu', () {
    final ticket = storage.devices.firstWhere(
      (d) => d.name == 'Ulaznica za koncert',
    );
    expect(DeliveryService.methodsFor(ticket), [DeliveryMethod.digital]);
    final phone = storage.deviceById('seed-1')!;
    expect(DeliveryService.methodsFor(phone), hasLength(4));
  });

  test(
    'kurir naplaćuje dostavu, pamti adresu i dobiva broj pošiljke',
    () async {
      final start = DateTime(2026, 10, 21, 12);
      final d = await deliveries.createForPurchase(
        userId: demo,
        device: storage.deviceById('seed-1')!,
        method: DeliveryMethod.courier,
        destination: 'Ilica 1, Zagreb',
        now: start,
      );
      expect(storage.userById(demo)!.credits, 1250); // dostava karticom
      expect(storage.userById(demo)!.address, 'Ilica 1, Zagreb');
      // Odabir se pamti za sljedeću kupnju.
      expect(storage.userById(demo)!.lastDelivery, 'courier|Ilica 1, Zagreb');
      expect(d.trackingNumber, startsWith('SUBH-'));
      expect(storage.transactions.single.type, TransactionType.delivery);

      // Statusi prate (ubrzano) vrijeme: 4 min za kurira.
      expect(d.status(start), DeliveryStatus.ordered);
      expect(
        d.status(start.add(const Duration(minutes: 2))),
        DeliveryStatus.shipped,
      );
      expect(d.isDelivered(start.add(const Duration(minutes: 4))), isTrue);
    },
  );

  test(
    'paketomat: preuzimanje se samo potvrdi, prodavač dobiva obavijesti',
    () async {
      final start = DateTime(2026, 10, 21, 12);
      const seller = SeedData.anaUserId;
      final d = await deliveries.createForPurchase(
        userId: demo,
        device: storage.deviceById('seed-1')!,
        method: DeliveryMethod.parcelLocker,
        destination: kDemoLockers.first,
        sellerId: seller,
        now: start,
      );
      // Prodavač dobiva kod za paketomat.
      expect(
        storage.notifications.where(
          (n) => n.userId == seller && n.kind == NotificationKind.shipReady,
        ),
        hasLength(1),
      );
      expect(d.steps.last, DeliveryStatus.pickedUp);
      // Još u paketomatu — ništa se ne potvrđuje.
      expect(await deliveries.autoConfirmPickups(demo, now: start), 0);
      // Kupac preuzeo → automatski potvrđeno (bez gumba).
      final later = start.add(const Duration(minutes: 10));
      expect(await deliveries.autoConfirmPickups(demo, now: later), 1);
      expect(storage.deliveryById(d.id)!.confirmedAt, isNotNull);
      expect(
        storage.notifications.where(
          (n) =>
              n.userId == seller && n.kind == NotificationKind.parcelPickedUp,
        ),
        hasLength(1),
      );
      // Samo jednom.
      expect(await deliveries.autoConfirmPickups(demo, now: later), 0);
    },
  );

  test('kurir bez adrese i paketomat bez odabira se odbijaju', () async {
    final phone = storage.deviceById('seed-1')!;
    await expectLater(
      deliveries.createForPurchase(
        userId: demo,
        device: phone,
        method: DeliveryMethod.courier,
      ),
      throwsA(isA<TradeException>()),
    );
    expect(
      DeliveryService.validate(DeliveryMethod.parcelLocker, 'nepostojeći'),
      isNotNull,
    );
    expect(
      DeliveryService.validate(DeliveryMethod.parcelLocker, kDemoLockers.first),
      isNull,
    );
  });

  test('BOX NOW paketomat s karte: zapis i provjera', () {
    const locker = BoxNowLocker(
      id: '1234',
      address: 'Ilica 1',
      postalCode: '10000',
      name: 'Konzum Ilica',
    );
    expect(locker.destination, 'BOX NOW #1234 · Konzum Ilica, Ilica 1, 10000');
    final back = BoxNowLocker.parse(locker.destination)!;
    expect(back.id, '1234');
    expect(back.address, 'Konzum Ilica, Ilica 1, 10000');
    expect(BoxNowLocker.parse('Ilica 1, Zagreb'), isNull);
    expect(BoxNowLocker.parse('BOX NOW # · '), isNull);
    expect(
      DeliveryService.validate(DeliveryMethod.parcelLocker, locker.destination),
      isNull,
    );
    // Izvan preglednika nema karte — bira se s popisa.
    expect(BoxNow.available, isFalse);
  });

  test('potvrda primitka tek nakon isporuke', () async {
    final start = DateTime(2026, 10, 21, 12);
    final d = await deliveries.createForPurchase(
      userId: demo,
      device: storage.deviceById('seed-1')!,
      method: DeliveryMethod.pickup,
      now: start,
    );
    await expectLater(
      deliveries.confirmReceipt(demo, d.id, now: start),
      throwsA(isA<TradeException>()),
    );
    await deliveries.confirmReceipt(
      demo,
      d.id,
      now: start.add(const Duration(minutes: 5)),
    );
    expect(storage.deliveryById(d.id)!.confirmedAt, isNotNull);
  });

  test('pobjednik aukcije dobiva pošiljku koja čeka odabir dostave', () async {
    final a = storage.auctionById('seed-auction-2')!; // Marko vodi
    await AuctionService(
      storage,
    ).settleExpired(now: a.endsAt.add(const Duration(seconds: 1)));
    final pending = storage.deliveries.where(
      (d) => d.buyerId == SeedData.markoUserId && d.deviceId == 'seed-35',
    );
    expect(pending.single.awaitingChoice, isTrue);
    final chosen = await deliveries.choose(
      userId: SeedData.markoUserId,
      deliveryId: pending.single.id,
      method: DeliveryMethod.parcelLocker,
      destination: kDemoLockers[2],
    );
    expect(chosen.method, DeliveryMethod.parcelLocker);
    expect(chosen.cost, 3);
  });
}
