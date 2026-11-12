import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/services/auction_service.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

/// Objava vlastitih predmeta u Marketu, kupnja od drugog korisnika,
/// uklanjanje iz Marketa i brisanje predmeta.
void main() {
  late StorageService storage;
  late TradeService trade;
  const iphone = 'seed-9'; // iPhone 13, demo korisnik, vrijednost 310

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    trade = TradeService(storage);
  });

  tearDown(() async {
    await Hive.close();
  });

  Future<AppState> stateFor(String userId) async {
    await storage.saveSession(userId: userId);
    return AppState.fromStorage(storage);
  }

  test('objava: vidljivo drugima u Marketu, ne i vlasniku', () async {
    final d = await trade.list(
      userId: SeedData.demoUserId,
      deviceId: iphone,
      price: 350,
    );
    expect(d.isListed, isTrue);
    expect(d.askPrice, 350);
    expect(d.ownerId, SeedData.demoUserId); // ostaje vlasnik

    final other = await stateFor(SeedData.testUserId);
    expect(other.marketDevices.map((d) => d.id), contains(iphone));
    final mine = await stateFor(SeedData.demoUserId);
    expect(mine.marketDevices.map((d) => d.id), isNot(contains(iphone)));
    expect(mine.myListings.single.id, iphone);
  });

  test(
    'kupnja od korisnika: kupac plaća cijenu, prodavatelj −5 %, dva zapisa',
    () async {
      await trade.list(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        price: 200,
      );
      final buyerBefore = storage.userById(SeedData.testUserId)!.credits; // 800
      final sellerBefore = storage
          .userById(SeedData.demoUserId)!
          .credits; // 1250

      final tx = await trade.buy(userId: SeedData.testUserId, deviceId: iphone);
      expect(tx.sellerId, SeedData.demoUserId);
      expect(tx.sellerLabel, '@demo');

      expect(tx.amount, 200); // kupac plaća karticom, bez naknade
      expect(storage.userById(SeedData.testUserId)!.credits, buyerBefore);
      expect(
        storage.userById(SeedData.demoUserId)!.credits,
        sellerBefore + 190,
      );
      final d = storage.deviceById(iphone)!;
      expect(d.ownerId, SeedData.testUserId);
      expect(d.isListed, isFalse); // novi vlasnik nije objavio predmet

      final sellerTx = storage.transactions.where(
        (t) => t.involves(SeedData.demoUserId),
      );
      expect(sellerTx.single.type, TransactionType.sell);
      expect(sellerTx.single.amount, 190);
      expect(sellerTx.single.fee, 10);
      expect(sellerTx.single.buyerLabel, '@test');
    },
  );

  test('dostava zna prodavatelja (za ocjenu)', () async {
    await trade.list(userId: SeedData.demoUserId, deviceId: iphone, price: 200);
    final device = storage.deviceById(iphone)!;
    final tx = await trade.buy(userId: SeedData.testUserId, deviceId: iphone);
    final delivery = await DeliveryService(storage).createForPurchase(
      userId: SeedData.testUserId,
      device: device,
      method: DeliveryMethod.pickup,
      sellerId: tx.sellerId,
    );
    expect(delivery.sellerId, SeedData.demoUserId);
    expect(delivery.canReview, isFalse); // tek nakon potvrde primitka
  });

  test('skup oglas: kupac plaća karticom, prodavatelj dobiva zaradu', () async {
    await trade.list(
      userId: SeedData.demoUserId,
      deviceId: iphone,
      price: 5000,
    );
    await trade.buy(userId: SeedData.testUserId, deviceId: iphone);
    expect(storage.deviceById(iphone)!.ownerId, SeedData.testUserId);
    expect(storage.userById(SeedData.demoUserId)!.credits, 1250 + 4750);
  });

  test('isplata zarade na IBAN prodavatelja', () async {
    final tx = await trade.payout(userId: SeedData.demoUserId);
    expect(tx.type, TransactionType.payout);
    expect(tx.amount, 1250);
    expect(storage.userById(SeedData.demoUserId)!.credits, 0);
    // Nema zarade → nema isplate.
    await expectLater(
      trade.payout(userId: SeedData.demoUserId),
      throwsA(isA<TradeException>()),
    );
  });

  test('ukloni iz Marketa: više se ne može kupiti', () async {
    await trade.list(userId: SeedData.demoUserId, deviceId: iphone, price: 200);
    await trade.unlist(userId: SeedData.demoUserId, deviceId: iphone);
    expect(storage.deviceById(iphone)!.isListed, isFalse);
    await expectLater(
      trade.buy(userId: SeedData.testUserId, deviceId: iphone),
      throwsA(isA<TradeException>()),
    );
    final other = await stateFor(SeedData.testUserId);
    expect(other.marketDevices.map((d) => d.id), isNot(contains(iphone)));
  });

  test('samo vlasnik objavljuje, uklanja i briše', () async {
    for (final f in [
      () => trade.list(userId: SeedData.testUserId, deviceId: iphone, price: 1),
      () => trade.unlist(userId: SeedData.testUserId, deviceId: iphone),
      () => trade.deleteOwn(userId: SeedData.testUserId, deviceId: iphone),
      // Predmet platforme nije ničiji.
      () =>
          trade.list(userId: SeedData.demoUserId, deviceId: 'seed-1', price: 1),
    ]) {
      await expectLater(f(), throwsA(isA<TradeException>()));
    }
    await expectLater(
      trade.list(userId: SeedData.demoUserId, deviceId: iphone, price: 0),
      throwsA(isA<TradeException>()),
    );
  });

  test(
    'aukcija skida predmet iz Marketa; tijekom aukcije nema objave',
    () async {
      final auctions = AuctionService(storage);
      await trade.list(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        price: 300,
      );
      await auctions.create(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        startPrice: 100,
        duration: const Duration(hours: 1),
      );
      expect(storage.deviceById(iphone)!.isListed, isFalse);
      await expectLater(
        trade.list(userId: SeedData.demoUserId, deviceId: iphone, price: 300),
        throwsA(isA<TradeException>()),
      );
      await expectLater(
        trade.deleteOwn(userId: SeedData.demoUserId, deviceId: iphone),
        throwsA(isA<TradeException>()),
      );
    },
  );

  test('novi predmet odmah ide u Market (osim ako se isključi)', () async {
    final listed = await trade.addDevice(
      userId: SeedData.testUserId,
      name: 'PS5',
      model: 'Slim',
      condition: DeviceCondition.excellent,
      price: 400,
      category: DeviceCategory.console,
    );
    expect(listed.isListed, isTrue);
    expect(listed.askPrice, 400);
    expect(listed.ownerId, SeedData.testUserId);
    final kept = await trade.addDevice(
      userId: SeedData.testUserId,
      name: 'Xbox',
      model: 'One',
      condition: DeviceCondition.good,
      price: 150,
      category: DeviceCategory.console,
      listOnMarket: false,
    );
    expect(kept.isListed, isFalse);
    // Ni jedan od njih ne objavljuje se ponovno automatski.
    expect(await trade.autoListPortfolios(), 2); // samo demo predmeti
    expect(storage.deviceById(kept.id)!.isListed, isFalse);
  });

  test('stari predmeti iz portfolija jednom idu u Market', () async {
    // Demo ima 2 stara predmeta (bez oznake) — oba se objave po cijeni.
    expect(await trade.autoListPortfolios(), 2);
    final d = storage.deviceById(iphone)!;
    expect(d.isListed, isTrue);
    expect(d.askPrice, d.price);
    // Vlasnik ga ukloni — ponovni prolaz ga NE vraća.
    await trade.unlist(userId: SeedData.demoUserId, deviceId: iphone);
    expect(await trade.autoListPortfolios(), 0);
    expect(storage.deviceById(iphone)!.isListed, isFalse);
    // Kupljeni predmet se ne objavljuje sam od sebe.
    await trade.list(userId: SeedData.demoUserId, deviceId: iphone, price: 200);
    await trade.buy(userId: SeedData.testUserId, deviceId: iphone);
    expect(await trade.autoListPortfolios(), 0);
    expect(storage.deviceById(iphone)!.isListed, isFalse);
    // Predmeti na aukciji (Anini) ostaju na aukciji.
    final onAuction = storage.devices.where(
      (x) => x.ownerId == SeedData.anaUserId,
    );
    expect(onAuction.every((x) => !x.isListed), isTrue);
  });

  test(
    'prodaja Subhastu poništava objavu; brisanje vlastitog predmeta',
    () async {
      await trade.list(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        price: 300,
      );
      await trade.sell(userId: SeedData.demoUserId, deviceId: iphone);
      final d = storage.deviceById(iphone)!;
      expect(d.isOnMarket, isTrue);
      expect(d.isListed, isFalse);
      expect(d.askPrice, 310); // opet platformina cijena

      final mine = storage.devices.firstWhere(
        (d) => d.ownerId == SeedData.demoUserId,
      );
      await trade.deleteOwn(userId: SeedData.demoUserId, deviceId: mine.id);
      expect(storage.deviceById(mine.id), isNull);
    },
  );
}
