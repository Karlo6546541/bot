import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/app_notification.dart';
import 'package:loop_app/models/app_user.dart';
import 'package:loop_app/services/account_service.dart';
import 'package:loop_app/services/auth_backend.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/models/price_offer.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/services/bargain_service.dart';
import 'package:loop_app/services/community_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

/// Zaliha, popusti, cjenkanje, praćenje, isticanje i ljestvica.
void main() {
  late StorageService storage;
  late TradeService trade;
  late BargainService bargains;
  late CommunityService community;
  const demo = SeedData.demoUserId;
  const tester = SeedData.testUserId;
  const marko = SeedData.markoUserId;

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    trade = TradeService(storage);
    bargains = BargainService(storage);
    community = CommunityService(storage);
  });

  tearDown(() => Hive.close());

  Future<Device> addMugs({int quantity = 3, double price = 20}) =>
      trade.addDevice(
        userId: demo,
        name: 'Šalica',
        model: 'Keramika',
        condition: DeviceCondition.brandNew,
        price: price,
        category: DeviceCategory.values.firstWhere(
          (c) => c.section != ItemSection.digital,
        ),
        quantity: quantity,
      );

  List<AppNotification> inbox(String userId) =>
      storage.notifications.where((n) => n.userId == userId).toList();

  group('zaliha', () {
    test('svaka kupnja skida komad; zadnji komad prelazi kupcu', () async {
      final d = await addMugs(quantity: 2);
      expect(d.quantity, 2);
      final tx1 = await trade.buy(userId: tester, deviceId: d.id);
      expect(tx1.deviceId, isNot(d.id)); // kupac dobiva svoj komad
      expect(storage.deviceById(tx1.deviceId)!.ownerId, tester);
      expect(storage.deviceById(tx1.deviceId)!.isListed, isFalse);
      final left = storage.deviceById(d.id)!;
      expect(left.quantity, 1);
      expect(left.isListed, isTrue);
      expect(left.ownerId, demo);

      final tx2 = await trade.buy(userId: marko, deviceId: d.id);
      expect(tx2.deviceId, d.id);
      expect(storage.deviceById(d.id)!.ownerId, marko);
      expect(storage.deviceById(d.id)!.quantity, 1);
      expect(
        inbox(demo).where((n) => n.kind == NotificationKind.soldOut),
        hasLength(1),
      );
    });

    test('količina se provjerava i mijenja objavom', () async {
      await expectLater(addMugs(quantity: 0), throwsA(isA<TradeException>()));
      final d = await addMugs(quantity: 1);
      final relisted = await trade.list(
        userId: demo,
        deviceId: d.id,
        price: 25,
        quantity: 10,
      );
      expect(relisted.quantity, 10);
      expect(Device.fromMap(relisted.toMap()).quantity, 10);
    });
  });

  group('popusti', () {
    test('privremeni popust snižava cijenu i istječe', () async {
      final d = await addMugs(price: 50);
      final now = DateTime.now();
      final cut = await trade.setDiscount(
        userId: demo,
        deviceId: d.id,
        percent: 20,
        duration: const Duration(days: 3),
        now: now,
      );
      expect(cut.priceAt(now), 40);
      expect(cut.priceAt(now.add(const Duration(days: 4))), 50);
      expect(Device.fromMap(cut.toMap()).discountPercent, 20);

      final tx = await trade.buy(userId: tester, deviceId: d.id);
      expect(tx.amount, 40); // kupac plaća samo cijenu, karticom
    });

    test('trajni popust; samo na oglas; granice', () async {
      final d = await addMugs(price: 10);
      final cut = await trade.setDiscount(
        userId: demo,
        deviceId: d.id,
        percent: 15,
      );
      expect(cut.discountUntil, isNull);
      expect(cut.askPrice, 8.5);
      await expectLater(
        trade.setDiscount(userId: demo, deviceId: d.id, percent: 95),
        throwsA(isA<TradeException>()),
      );
      await expectLater(
        trade.setDiscount(userId: tester, deviceId: d.id, percent: 10),
        throwsA(isA<TradeException>()),
      );
      final off = await trade.setDiscount(
        userId: demo,
        deviceId: d.id,
        percent: 0,
      );
      expect(off.askPrice, 10);
    });

    test('pratitelji dobiju obavijest o popustu i novom oglasu', () async {
      await community.toggleFollow(tester, demo);
      expect(
        inbox(demo).where((n) => n.kind == NotificationKind.newFollower),
        hasLength(1),
      );
      final d = await addMugs(price: 30);
      expect(
        inbox(tester).where((n) => n.kind == NotificationKind.followedNewItem),
        hasLength(1),
      );
      await trade.setDiscount(userId: demo, deviceId: d.id, percent: 10);
      final n = inbox(
        tester,
      ).firstWhere((n) => n.kind == NotificationKind.followedDiscount);
      expect(n.text, '@demo: popust −10% na "Šalica" — sada 27 €.');
      // Marko ne prati demo — ništa ne dobiva.
      expect(
        inbox(marko).where((n) => n.kind == NotificationKind.followedDiscount),
        isEmpty,
      );
    });
  });

  group('cjenkanje', () {
    test('ponuda → prihvaćanje → kupnja po dogovorenoj cijeni', () async {
      final d = await addMugs(price: 100, quantity: 1);
      final o = await bargains.make(
        buyerId: tester,
        deviceId: d.id,
        amount: 80,
      );
      expect(inbox(demo).last.kind, NotificationKind.bargainNew);
      await expectLater(
        bargains.make(buyerId: tester, deviceId: d.id, amount: 70),
        throwsA(isA<TradeException>()), // već postoji otvorena
      );
      await expectLater(
        bargains.accept(tester, o.id), // kupac ne prihvaća svoju ponudu
        throwsA(isA<TradeException>()),
      );
      final ok = await bargains.accept(demo, o.id);
      expect(ok.status, BargainStatus.accepted);
      expect(trade.priceFor(tester, d), 80);
      expect(trade.priceFor(marko, d), 100); // samo za tog kupca

      final sellerBefore = storage.userById(demo)!.credits;
      final tx = await trade.buy(userId: tester, deviceId: d.id);
      expect(tx.price, 80);
      expect(tx.amount, 80); // kupac plaća karticom
      expect(storage.userById(demo)!.credits, sellerBefore + 76);
      expect(storage.bargainById(o.id)!.status, BargainStatus.used);
    });

    test('protuponuda i granice iznosa', () async {
      final d = await addMugs(price: 100);
      for (final bad in [100.0, 120.0, 20.0]) {
        await expectLater(
          bargains.make(buyerId: tester, deviceId: d.id, amount: bad),
          throwsA(isA<TradeException>()),
        );
      }
      final o = await bargains.make(
        buyerId: tester,
        deviceId: d.id,
        amount: 60,
      );
      await expectLater(
        bargains.counter(demo, o.id, 50),
        throwsA(isA<TradeException>()),
      );
      final c = await bargains.counter(demo, o.id, 85);
      expect(c.status, BargainStatus.countered);
      expect(inbox(tester).last.kind, NotificationKind.bargainCountered);
      final acc = await bargains.acceptCounter(tester, o.id);
      expect(acc.agreedPrice, 85);
      expect(trade.priceFor(tester, d), 85);
    });

    test('odbijanje, istek i vlastiti oglas', () async {
      final d = await addMugs(price: 100);
      await expectLater(
        bargains.make(buyerId: demo, deviceId: d.id, amount: 50),
        throwsA(isA<TradeException>()),
      );
      final o = await bargains.make(
        buyerId: tester,
        deviceId: d.id,
        amount: 50,
      );
      await bargains.decline(demo, o.id);
      expect(storage.bargainById(o.id)!.status, BargainStatus.declined);
      expect(inbox(tester).last.kind, NotificationKind.bargainDeclined);

      final now = DateTime.now();
      final o2 = await bargains.make(
        buyerId: tester,
        deviceId: d.id,
        amount: 60,
        now: now,
      );
      final acc = await bargains.accept(demo, o2.id, now: now);
      expect(acc.usableAt(now.add(const Duration(hours: 47))), isTrue);
      expect(acc.usableAt(now.add(const Duration(hours: 49))), isFalse);
    });
  });

  group('praćenje, isticanje, ljestvica', () {
    test('praćenje se uključuje i isključuje', () async {
      expect(await community.toggleFollow(tester, demo), isTrue);
      expect(community.followersOf(demo), 1);
      expect(await community.toggleFollow(tester, demo), isFalse);
      expect(community.followersOf(demo), 0);
      await expectLater(
        community.toggleFollow(demo, demo),
        throwsA(isA<TradeException>()),
      );
    });

    test('tjedno isticanje se plaća i produljuje', () async {
      final now = DateTime(2026, 10, 1);
      final before = storage.userById(demo)!.credits;
      final u = await community.promote(demo, 1, now: now);
      // Plaća se karticom: zarada ostaje, a plaćanje je zabilježeno.
      expect(u.credits, before);
      expect(
        storage.transactions.where(
          (t) => t.type == TransactionType.promotion && t.userId == demo,
        ),
        hasLength(1),
      );
      expect(u.promotedAt(now.add(const Duration(days: 6))), isTrue);
      expect(u.promotedAt(now.add(const Duration(days: 8))), isFalse);
      final u2 = await community.promote(demo, 2, now: now);
      expect(u2.promotedUntil, now.add(const Duration(days: 21)));
      await expectLater(
        community.promote(demo, 9),
        throwsA(isA<TradeException>()),
      );
    });

    test('ljestvica broji prodaje drugim korisnicima', () async {
      final d = await addMugs(quantity: 3);
      await trade.buy(userId: tester, deviceId: d.id);
      await trade.buy(userId: marko, deviceId: d.id);
      // Prodaja LOOP-u se ne broji.
      await trade.sell(userId: demo, deviceId: 'seed-9');
      await storage.saveSession(userId: demo);
      final state = AppState.fromStorage(storage);
      final board = state.leaderboard();
      expect(board.first.user.id, demo);
      expect(board.first.sales, 2);
      expect(board.first.revenue, 40);
      expect(state.salesCountOf(demo), 2);
    });
  });

  test(
    'povijest pretrage: bez duplikata, najnovije prvo, najviše 10',
    () async {
      await storage.addSearch('iphone');
      await storage.addSearch('Šalica');
      await storage.addSearch('IPHONE');
      expect(storage.searchHistory, ['IPHONE', 'Šalica']);
      for (var i = 0; i < 15; i++) {
        await storage.addSearch('upit $i');
      }
      expect(storage.searchHistory, hasLength(StorageService.maxSearchHistory));
      await storage.clearSearchHistory();
      expect(storage.searchHistory, isEmpty);
    },
  );

  test('nema LOOP Marketa: predmeti platforme dobiju prodavatelje', () async {
    final before = storage.devices.where((d) => d.ownerId == null).length;
    expect(before, greaterThan(0));
    expect(await trade.assignPlatformItems(), before);
    expect(storage.devices.where((d) => d.ownerId == null), isEmpty);
    final heirs = storage.devices
        .where((d) => d.id.startsWith('seed-') && d.isListed)
        .map((d) => d.ownerId)
        .toSet();
    expect(heirs, containsAll(TradeService.platformHeirs));
    // Drugi prolaz ništa ne mijenja (svi uređaji dođu do istog rezultata).
    expect(await trade.assignPlatformItems(), 0);
    // Kupnja ide od prodavatelja: on dobiva cijenu − 5 %.
    final d = storage.deviceById('seed-5')!;
    final sellerBefore = storage.userById(d.ownerId!)!.credits;
    await trade.buy(userId: demo, deviceId: d.id);
    expect(storage.userById(d.ownerId!), isNotNull);
    expect(
      storage.userById(storage.transactions.first.sellerId!)!.credits,
      sellerBefore + 175.75,
    );
  });

  test('ocjena trgovine: jedna po korisniku, zamjenjuje se', () async {
    await community.rateShop(raterId: tester, sellerId: demo, stars: 5);
    await community.rateShop(raterId: tester, sellerId: demo, stars: 3);
    await community.rateShop(raterId: marko, sellerId: demo, stars: 4);
    await storage.saveSession(userId: tester);
    final state = AppState.fromStorage(storage);
    expect(state.ratingOf(demo).count, 2);
    expect(state.ratingOf(demo).average, 3.5);
    expect(state.myShopReviewOf(demo)!.stars, 3);
    await expectLater(
      community.rateShop(raterId: demo, sellerId: demo, stars: 5),
      throwsA(isA<TradeException>()),
    );
  });

  test('prikazi, lajkovi, pratitelji i prodaje', () async {
    await storage.addView('seed-9');
    await storage.addView('seed-9');
    await trade.toggleFavorite(tester, 'seed-9');
    await community.toggleFollow(tester, demo);
    await community.toggleFollow(marko, demo);
    await community.toggleFollow(demo, marko);
    await storage.saveSession(userId: demo);
    final state = AppState.fromStorage(storage);
    expect(state.viewsOf('seed-9'), 2);
    expect(state.likesOf('seed-9'), 1);
    expect(state.followersListOf(demo).map((u) => u.id), {tester, marko});
    expect(state.followingListOf(demo).single.id, marko);
  });

  test('naslovna slika trgovine se postavlja i uklanja', () async {
    final accounts = AccountService(storage, LocalAuthBackend(storage));
    expect(await accounts.setCover(demo, 'local:img/cover.jpg'), isNull);
    expect(storage.userById(demo)!.coverPath, 'local:img/cover.jpg');
    expect(
      AppUser.fromMap(storage.userById(demo)!.toMap()).coverPath,
      'local:img/cover.jpg',
    );
    expect(await accounts.setCover(demo, null), 'local:img/cover.jpg');
    expect(storage.userById(demo)!.coverPath, isNull);
  });
}
