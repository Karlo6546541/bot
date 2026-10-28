import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/app_notification.dart';
import 'package:loop_app/models/country.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/services/auction_service.dart';
import 'package:loop_app/services/boxnow/boxnow.dart';
import 'package:loop_app/services/boxnow/boxnow_demo.dart';
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
    expect(DeliveryService.methodsFor(phone), hasLength(5));
    expect(DeliveryService.methodsFor(phone), contains(DeliveryMethod.europe));
  });

  test(
    'veličina paketa: cijena raste, veliko bez paketomata, glomazno bez ekspresa',
    () {
      final phone = storage.deviceById('seed-1')!;
      expect(
        DeliveryService.costFor(DeliveryMethod.courier, ParcelSize.small),
        DeliveryMethod.courier.cost,
      );
      expect(
        DeliveryService.costFor(DeliveryMethod.courier, ParcelSize.large),
        DeliveryMethod.courier.cost + ParcelSize.large.extra,
      );
      // EU: cijena po zoni države i dvostruka doplata za veličinu.
      expect(
        DeliveryService.costFor(
          DeliveryMethod.europe,
          ParcelSize.medium,
          country: 'Slovenija',
        ),
        euZoneCost(1) + 2 * ParcelSize.medium.extra,
      );
      expect(
        DeliveryService.costFor(
          DeliveryMethod.europe,
          ParcelSize.small,
          country: 'Portugal',
        ),
        euZoneCost(3),
      );
      expect(
        DeliveryService.costFor(DeliveryMethod.pickup, ParcelSize.bulky),
        0,
      );
      final big = phone.withParcelSize('large');
      expect(
        DeliveryService.methodsFor(big),
        isNot(contains(DeliveryMethod.parcelLocker)),
      );
      final bulky = phone.withParcelSize('bulky');
      expect(
        DeliveryService.methodsFor(bulky),
        isNot(contains(DeliveryMethod.express)),
      );
      expect(Device.fromMap(bulky.toMap()).parcelSize, 'bulky');
    },
  );

  test('dostava u EU naplaćuje veličinu paketa', () async {
    final phone = storage.deviceById('seed-1')!;
    await storage.putDevice(phone.withParcelSize('large'));
    final d = await deliveries.createForPurchase(
      userId: demo,
      device: storage.deviceById('seed-1')!,
      method: DeliveryMethod.europe,
      destination: 'Hauptstraße 5, 10115 Berlin, Njemačka',
    );
    expect(d.cost, euZoneCost(2) + 2 * ParcelSize.large.extra);
    // Bez države — ne može.
    expect(
      DeliveryService.validate(DeliveryMethod.europe, 'Hauptstraße 5, Berlin'),
      isNotNull,
    );
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
      // Paket u paketomatu → kupac dobiva PIN za preuzimanje (jednom).
      final arrived = start.add(const Duration(seconds: 150));
      expect(d.status(arrived), DeliveryStatus.inLocker);
      expect(await deliveries.autoConfirmPickups(demo, now: arrived), 0);
      await deliveries.autoConfirmPickups(demo, now: arrived);
      final pinNotes = storage.notifications.where(
        (n) => n.userId == demo && n.kind == NotificationKind.parcelArrived,
      );
      expect(pinNotes, hasLength(1));
      expect(pinNotes.single.args.last, BoxNowDemo.pickupPin(d));
      // PIN-ovi stižu i kao službene poruke od Subhasta.
      final sys = storage.messages.where((m) => m.senderId == 'subhasto');
      expect(
        sys.any(
          (m) =>
              m.receiverId == seller &&
              m.text.contains(BoxNowDemo.dropOffPin(d)),
        ),
        isTrue,
      );
      expect(
        sys.any(
          (m) =>
              m.receiverId == demo && m.text.contains(BoxNowDemo.pickupPin(d)),
        ),
        isTrue,
      );
      // PIN-ovi su nasumični (spremljeni uz pošiljku), ne iz broja pošiljke.
      expect(d.pickupPin, isNotNull);
      expect(d.dropOffPin, isNotNull);
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

      // BOX NOW (demo): stalni broj i PIN-ovi, praćenje do preuzimanja.
      final done = storage.deliveryById(d.id)!;
      expect(BoxNowDemo.parcelId(done), hasLength(10));
      expect(BoxNowDemo.parcelId(done), BoxNowDemo.parcelId(d));
      expect(BoxNowDemo.dropOffPin(done), matches(RegExp(r'^\d{6}$')));
      expect(BoxNowDemo.pickupPin(done), matches(RegExp(r'^\d{6}$')));
      final events = BoxNowDemo.events(done, later);
      expect(events, hasLength(5));
      expect(events.every((e) => e.$3), isTrue);
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
  test(
    'legacy notification without payload id is repaired before delivery choice',
    () async {
      final note = AppNotification(
        id: 'legacy-note',
        userId: SeedData.anaUserId,
        kind: NotificationKind.shipReady,
        createdAt: DateTime.now(),
      );
      await Hive.box<Map>(
        'notifications',
      ).put(note.id, note.toMap()..remove('id'));
      await Hive.close();
      await storage.init(path: dir.path);
      final d = await deliveries.createPending(
        userId: demo,
        deviceId: 'seed-1',
        deviceName: 'Camera',
        sellerId: SeedData.anaUserId,
      );
      await deliveries.choose(
        userId: demo,
        deliveryId: d.id,
        method: DeliveryMethod.parcelLocker,
        destination: kDemoLockers.first,
      );
      expect(storage.notifications.any((n) => n.id == note.id), isTrue);
      expect(
        AppState.fromStorage(storage).deliveries.single.method,
        DeliveryMethod.parcelLocker,
      );
    },
  );

  test('remote row key restores a missing delivery payload id', () async {
    final d = await deliveries.createPending(
      userId: demo,
      deviceId: 'seed-1',
      deviceName: 'Camera',
    );
    final raw = d.toMap()..remove('id');
    await storage.applyRemote('deliveries', d.id, raw);
    expect(storage.deliveryById(d.id)!.id, d.id);
    await storage.replaceAllFromRemote({
      'deliveries': {d.id: raw},
    });
    expect(storage.deliveries.single.id, d.id);
  });

  test('concurrent live choices and retries charge one parcel once', () async {
    final a = await deliveries.createPending(
      id: 'live-choice-0',
      userId: demo,
      deviceId: 'seed-1',
      deviceName: 'A',
    );
    final b = await deliveries.createPending(
      id: 'live-choice-1',
      userId: demo,
      deviceId: 'seed-2',
      deviceName: 'B',
    );
    await Future.wait([
      deliveries.choose(
        userId: demo,
        deliveryId: a.id,
        method: DeliveryMethod.parcelLocker,
        destination: kDemoLockers.first,
      ),
      deliveries.choose(
        userId: demo,
        deliveryId: b.id,
        method: DeliveryMethod.parcelLocker,
        destination: kDemoLockers.first,
      ),
    ]);
    final retry = await deliveries.choose(
      userId: demo,
      deliveryId: a.id,
      method: DeliveryMethod.courier,
      destination: 'Ilica 1, Zagreb',
    );
    expect(retry.method, DeliveryMethod.parcelLocker);
    expect(
      storage.transactions.where((t) => t.type == TransactionType.delivery),
      hasLength(1),
    );
    expect(storage.deliveries.fold<double>(0, (sum, d) => sum + d.cost), 3);
  });
  test(
    'controller refreshes a persisted delivery even after a write callback fails',
    () async {
      await storage.saveSession(userId: demo);
      final d = await deliveries.createPending(
        userId: demo,
        deviceId: 'seed-1',
        deviceName: 'Camera',
      );
      final container = ProviderContainer(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appProvider.notifier);
      storage.onLocalChange = (table, id, data) {
        if (table == 'deliveries' && id == d.id && data?['method'] != null) {
          throw StateError('Simulated failure after the delivery was stored');
        }
      };
      await expectLater(
        controller.chooseDelivery(
          d.id,
          DeliveryMethod.parcelLocker,
          kDemoLockers.first,
        ),
        throwsStateError,
      );
      expect(
        container.read(appProvider).deliveries.single.awaitingChoice,
        isFalse,
      );
      storage.onLocalChange = null;
    },
  );

  test('lokalni dostavljači unutar države, međunarodni među državama', () {
    final phone = storage.deviceById('seed-1')!;
    final hr = DeliveryService.optionsFor(phone, from: 'HR', to: 'HR');
    final ids = hr.map((o) => o.id).toList();
    expect(ids, containsAll(['hr-gls', 'hr-boxnow', 'hr-post']));
    expect(ids, contains(DeliveryMethod.pickup.name));
    final de = DeliveryService.optionsFor(phone, from: 'DE', to: 'DE');
    expect(de.map((o) => o.carrier?.name), containsAll(['DHL', 'Hermes']));
    // HR → SI je blizu, HR → PT daleko: veća cijena, nema osobnog preuzimanja.
    final si = DeliveryService.optionsFor(phone, from: 'HR', to: 'SI');
    final pt = DeliveryService.optionsFor(phone, from: 'HR', to: 'PT');
    expect(si.every((o) => o.carrier?.international ?? false), isTrue);
    double gls(List<DeliveryOption> o) =>
        o.firstWhere((x) => x.id == 'intl-gls').carrier!.cost;
    expect(gls(si), lessThan(gls(pt)));
    // Glomazni paket: bez paketomata, međunarodna doplata je dvostruka.
    final bulky = phone.withParcelSize('bulky');
    final big = DeliveryService.optionsFor(bulky, from: 'HR', to: 'HR');
    expect(big.any((o) => o.carrier?.kind == CarrierKind.locker), isFalse);
    final intl = internationalCarriers(countryOf('HR'), countryOf('SI')).first;
    expect(
      DeliveryService.carrierCost(intl, ParcelSize.bulky),
      intl.cost + ParcelSize.bulky.extra * 2,
    );
  });

  test('GLS i DPD paketomati: popis, zapis, broj pošiljke i PIN-ovi', () async {
    final phone = storage.deviceById('seed-1')!;
    final opts = DeliveryService.optionsFor(phone, from: 'HR', to: 'HR');
    final gls = opts.firstWhere((o) => o.id == 'hr-gls-locker');
    final dpd = opts.firstWhere((o) => o.id == 'hr-dpd-locker');
    expect(LockerNetwork.ofCarrier(gls.carrier), LockerNetwork.gls);
    expect(LockerNetwork.ofCarrier(dpd.carrier), LockerNetwork.dpd);
    // I u drugim državama (npr. Slovenija).
    final si = DeliveryService.optionsFor(phone, from: 'SI', to: 'SI');
    expect(
      si.map((o) => o.id),
      containsAll(['si-gls-locker', 'si-dpd-locker']),
    );

    final locker = demoLockers(LockerNetwork.gls, 'HR').first;
    expect(locker.destination, startsWith('GLS #'));
    final back = BoxNowLocker.parse(locker.destination)!;
    expect(back.network, LockerNetwork.gls);
    expect(back.id, locker.id);
    // Paketomat mora biti iz mreže odabranog dostavljača.
    expect(
      DeliveryService.validate(
        DeliveryMethod.parcelLocker,
        locker.destination,
        carrier: gls.carrier,
      ),
      isNull,
    );
    expect(
      DeliveryService.validate(
        DeliveryMethod.parcelLocker,
        locker.destination,
        carrier: dpd.carrier,
      ),
      isNotNull,
    );

    final d = await deliveries.createForPurchase(
      userId: demo,
      device: phone,
      method: DeliveryMethod.parcelLocker,
      destination: locker.destination,
      carrier: gls.carrier,
    );
    expect(d.carrier, 'GLS paketomat');
    expect(BoxNowDemo.network(d), LockerNetwork.gls);
    expect(BoxNowDemo.parcelId(d), hasLength(11));
    expect(BoxNowDemo.dropOffPin(d), matches(RegExp(r'^\d{6}$')));
    expect(BoxNowDemo.events(d, DateTime.now()).first.$1, contains('GLS'));
    final dpdDelivery = d.copyWith(
      destination: demoLockers(LockerNetwork.dpd, 'HR').first.destination,
    );
    expect(BoxNowDemo.parcelId(dpdDelivery), hasLength(14));
    // Zapis bez oznake mreže: odlučuje dostavljač pošiljke.
    expect(
      BoxNowDemo.network(d.copyWith(destination: kDemoLockers.first)),
      LockerNetwork.gls,
    );
  });
}
