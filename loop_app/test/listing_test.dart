import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/delivery.dart';
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

  test('kupnja od korisnika: kupac +5%, prodavatelj −5%, dva zapisa', () async {
    await trade.list(userId: SeedData.demoUserId, deviceId: iphone, price: 200);
    final buyerBefore = storage.userById(SeedData.testUserId)!.credits; // 800
    final sellerBefore = storage.userById(SeedData.demoUserId)!.credits; // 1250

    final tx = await trade.buy(userId: SeedData.testUserId, deviceId: iphone);
    expect(tx.sellerId, SeedData.demoUserId);
    expect(tx.sellerLabel, '@demo');

    expect(storage.userById(SeedData.testUserId)!.credits, buyerBefore - 210);
    expect(storage.userById(SeedData.demoUserId)!.credits, sellerBefore + 190);
    final d = storage.deviceById(iphone)!;
    expect(d.ownerId, SeedData.testUserId);
    expect(d.isListed, isFalse); // novi vlasnik nije objavio predmet

    final sellerTx = storage.transactions.where(
      (t) => t.involves(SeedData.demoUserId),
    );
    expect(sellerTx.single.type, TransactionType.sell);
    expect(sellerTx.single.amount, 190);
    expect(sellerTx.single.buyerLabel, '@test');
  });

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

  test('premalo kredita za objavljeni predmet', () async {
    await trade.list(
      userId: SeedData.demoUserId,
      deviceId: iphone,
      price: 5000,
    );
    await expectLater(
      trade.buy(userId: SeedData.testUserId, deviceId: iphone),
      throwsA(isA<TradeException>()),
    );
    expect(storage.deviceById(iphone)!.ownerId, SeedData.demoUserId);
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

  test('objava i aukcija se isključuju', () async {
    final auctions = AuctionService(storage);
    await trade.list(userId: SeedData.demoUserId, deviceId: iphone, price: 300);
    await expectLater(
      auctions.create(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        startPrice: 100,
        duration: const Duration(hours: 1),
      ),
      throwsA(isA<TradeException>()),
    );
    await trade.unlist(userId: SeedData.demoUserId, deviceId: iphone);
    await auctions.create(
      userId: SeedData.demoUserId,
      deviceId: iphone,
      startPrice: 100,
      duration: const Duration(hours: 1),
    );
    await expectLater(
      trade.list(userId: SeedData.demoUserId, deviceId: iphone, price: 300),
      throwsA(isA<TradeException>()),
    );
    await expectLater(
      trade.deleteOwn(userId: SeedData.demoUserId, deviceId: iphone),
      throwsA(isA<TradeException>()),
    );
  });

  test(
    'prodaja LOOP-u poništava objavu; brisanje vlastitog predmeta',
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
