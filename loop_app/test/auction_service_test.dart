import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/auction.dart';
import 'package:loop_app/models/loop_transaction.dart';
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
  const ana = SeedData.anaUserId;
  const marko = SeedData.markoUserId;

  double credits(String id) => storage.userById(id)!.credits;
  Auction auction(String n) => storage.auctionById('seed-auction-$n')!;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('loop_auction');
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

  test('seed: 4 aukcije, Markovih 470 LC je blokirano', () {
    expect(storage.auctions.where((a) => a.isActive), hasLength(4));
    expect(credits(marko), 1030);
    expect(storage.heldCredits(marko), 470);
    expect(storage.deviceById('seed-34')!.ownerId, ana);
    expect(auction('1').currentPrice, 320);
    expect(auction('1').minNextBid, 336); // 320 + 5%
  });

  test('ponuda blokira kredite, prethodni ponuđač dobiva povrat', () async {
    await auctions.placeBid(
      userId: demo,
      auctionId: 'seed-auction-1',
      amount: 340,
    );
    expect(credits(demo), 910); // 1250 − 340
    expect(credits(marko), 1350); // 1030 + 320
    expect(auction('1').highestBid!.userId, demo);
    expect(storage.heldCredits(demo), 340);
  });

  test('vodeći ponuđač ne može ponovno licitirati ni povući ponudu', () async {
    await auctions.placeBid(
      userId: demo,
      auctionId: 'seed-auction-1',
      amount: 340,
    );
    await expectLater(
      auctions.placeBid(userId: demo, auctionId: 'seed-auction-1', amount: 400),
      throwsA(isA<TradeException>()),
    );
    // Ponude se nikad ne brišu.
    expect(auction('1').bids, hasLength(3));
  });

  test('ponuda ne može biti veća od kredita ni manja od minimuma', () async {
    await expectLater(
      auctions.placeBid(
        userId: tester,
        auctionId: 'seed-auction-1',
        amount: 801,
      ),
      throwsA(isA<TradeException>()),
    );
    await expectLater(
      auctions.placeBid(
        userId: tester,
        auctionId: 'seed-auction-1',
        amount: 330,
      ),
      throwsA(isA<TradeException>()),
    );
    expect(credits(tester), 800);
    // Točno cijeli iznos kredita je dopušten.
    await auctions.placeBid(
      userId: tester,
      auctionId: 'seed-auction-1',
      amount: 800,
    );
    expect(credits(tester), 0);
  });

  test('prodavatelj ne licitira na svoju aukciju', () async {
    await expectLater(
      auctions.placeBid(userId: ana, auctionId: 'seed-auction-3', amount: 50),
      throwsA(isA<TradeException>()),
    );
  });

  test('ponuda u zadnjoj minuti produljuje aukciju', () async {
    final a = auction('4');
    final late = a.endsAt.subtract(const Duration(seconds: 10));
    await auctions.placeBid(
      userId: demo,
      auctionId: a.id,
      amount: 100,
      now: late,
    );
    expect(auction('4').endsAt, late.add(AuctionService.extendWindow));
  });

  test('istek: pobjednik dobiva predmet, prodavatelj cijeli iznos', () async {
    final a = auction('2'); // Marko vodi s 60
    final results = await auctions.settleExpired(
      now: a.endsAt.add(const Duration(seconds: 1)),
    );
    expect(results.map((r) => r.auction.id), contains(a.id));
    expect(auction('2').status, AuctionStatus.sold);
    expect(storage.deviceById('seed-35')!.ownerId, marko);
    // Do tada je istekla i aukcija 4 (ulaznica, 90 LC), pa se zaključuju obje.
    expect(auction('4').status, AuctionStatus.sold);
    expect(credits(ana), 550); // 400 + 60 + 90 (bez naknade)
    expect(credits(marko), 1030); // iznosi su već bili blokirani
    expect(storage.heldCredits(marko), 320); // ostaje samo aukcija 1

    final tx = storage.transactions.singleWhere((t) => t.deviceId == 'seed-35');
    expect(tx.isAuction, isTrue);
    expect(tx.typeFor(ana), TransactionType.sell);
    expect(tx.typeFor(marko), TransactionType.buy);
    expect(tx.amountFor(marko), 60);
    expect(tx.amountFor(ana), 60);
    expect(tx.feeFor(marko), 0);
  });

  test('istek bez ponuda: predmet ostaje prodavatelju', () async {
    final a = auction('3');
    await auctions.settleExpired(now: a.endsAt.add(const Duration(minutes: 1)));
    expect(auction('3').status, AuctionStatus.unsold);
    expect(storage.deviceById('seed-36')!.ownerId, ana);
  });

  test('otkazivanje: samo bez ponuda; admin vraća vodeću ponudu', () async {
    await expectLater(
      auctions.cancelBySeller(ana, 'seed-auction-1'),
      throwsA(isA<TradeException>()),
    );
    await auctions.cancelBySeller(ana, 'seed-auction-3');
    expect(auction('3').status, AuctionStatus.cancelled);

    await auctions.cancelByAdmin('seed-auction-1');
    expect(credits(marko), 1350); // 1030 + 320
  });

  test('predmet na aukciji ne može se prodati ni ponovno staviti', () async {
    await expectLater(
      trade.sell(userId: ana, deviceId: 'seed-34'),
      throwsA(isA<TradeException>()),
    );
    await expectLater(
      auctions.create(
        userId: ana,
        deviceId: 'seed-34',
        startPrice: 10,
        duration: const Duration(hours: 1),
      ),
      throwsA(isA<TradeException>()),
    );
  });

  test('nova aukcija iz vlastitog portfolija', () async {
    final a = await auctions.create(
      userId: demo,
      deviceId: 'seed-9',
      startPrice: 150,
      duration: const Duration(minutes: 2),
    );
    expect(a.isActive, isTrue);
    expect(a.minNextBid, 150);
    await expectLater(
      auctions.create(
        userId: demo,
        deviceId: 'seed-1', // nije njegov
        startPrice: 10,
        duration: const Duration(hours: 1),
      ),
      throwsA(isA<TradeException>()),
    );
  });

  test('nadogradnja sa starije verzije dodaje demo aukcije', () async {
    // Simuliraj instalaciju iz prethodne verzije (seed v3, bez aukcija).
    await Hive.box('session').put('seedVersion', 3);
    await Hive.box<Map>('users').deleteAll([ana, marko]);
    await Hive.box<Map>(
      'devices',
    ).deleteAll([for (var i = 34; i <= 37; i++) 'seed-$i']);
    await Hive.box<Map>('auctions').clear();
    await Hive.close();

    final upgraded = StorageService();
    await upgraded.init(path: dir.path);
    expect(upgraded.auctions.where((a) => a.isActive), hasLength(4));
    expect(upgraded.userById(marko)!.credits, 1030);
    expect(upgraded.deviceById('seed-34')!.ownerId, ana);
  });

  group('automatska ponuda, kupi odmah, praćenje', () {
    test('automatska ponuda licitira umjesto kupca do maksimuma', () async {
      // Marko vodi s 320 bez automatske ponude.
      await auctions.placeBid(
        userId: demo,
        auctionId: 'seed-auction-1',
        amount: 340,
        maxAmount: 500,
      );
      expect(auction('1').highestBid!.amount, 340);
      expect(credits(demo), 910); // blokira se samo 340, ne 500
      expect(auction('1').autoMaxOf(demo), 500);

      // Test nudi 360 — demo automatski odgovara korakom (360 + 18).
      await auctions.placeBid(
        userId: tester,
        auctionId: 'seed-auction-1',
        amount: 360,
      );
      expect(auction('1').highestBid!.userId, demo);
      expect(auction('1').highestBid!.amount, 378);
      expect(credits(demo), 872); // 910 − 38
      expect(credits(tester), 800); // ništa blokirano
      expect(
        storage.notifications.any(
          (n) => n.userId == tester && n.kind.name == 'outbidAuto',
        ),
        isTrue,
      );

      // Test s automatskom do 600 nadmašuje demo maksimum (500 + 25).
      await auctions.placeBid(
        userId: tester,
        auctionId: 'seed-auction-1',
        amount: 400,
        maxAmount: 600,
      );
      final a = auction('1');
      expect(a.highestBid!.userId, tester);
      expect(a.highestBid!.amount, 525);
      expect(a.bids[a.bids.length - 2].amount, 500); // demo do maksimuma
      expect(credits(demo), 1250); // povrat
      expect(credits(tester), 275);
      expect(a.autoMaxOf(demo), isNull);

      // Vodeći smije povisiti svoj maksimum (do stanja + blokiranog).
      await auctions.placeBid(
        userId: tester,
        auctionId: 'seed-auction-1',
        amount: 0,
        maxAmount: 700,
      );
      expect(auction('1').autoMaxOf(tester), 700);
      await expectLater(
        auctions.placeBid(
          userId: tester,
          auctionId: 'seed-auction-1',
          amount: 0,
          maxAmount: 900,
        ),
        throwsA(isA<TradeException>()),
      );
    });

    test('kupi odmah završava aukciju i vraća vodeću ponudu', () async {
      final a = await auctions.create(
        userId: demo,
        deviceId: 'seed-9',
        startPrice: 100,
        duration: const Duration(hours: 1),
        buyNowPrice: 300,
      );
      await auctions.placeBid(userId: marko, auctionId: a.id, amount: 150);
      expect(storage.auctionById(a.id)!.canBuyNow, isTrue);
      final r = await auctions.buyNow(userId: tester, auctionId: a.id);
      expect(r.winnerId, tester);
      expect(r.auction.status, AuctionStatus.sold);
      expect(storage.deviceById('seed-9')!.ownerId, tester);
      expect(credits(tester), 500);
      expect(credits(marko), 1030); // 150 vraćeno
      await expectLater(
        auctions.buyNow(userId: marko, auctionId: a.id),
        throwsA(isA<TradeException>()),
      );
      await expectLater(
        auctions.create(
          userId: demo,
          deviceId: 'seed-10',
          startPrice: 100,
          duration: const Duration(hours: 1),
          buyNowPrice: 90,
        ),
        throwsA(isA<TradeException>()),
      );
    });

    test('pratitelji, zvono i podsjetnik pred kraj', () async {
      final me = storage.userById(tester)!;
      await storage.putUser(me.copyWith(following: [demo]));
      final at = DateTime.now();
      final a = await auctions.create(
        userId: demo,
        deviceId: 'seed-9',
        startPrice: 100,
        duration: const Duration(hours: 1),
        now: at,
      );
      bool got(String user, String kind) => storage.notifications.any(
        (n) => n.userId == user && n.kind.name == kind && n.targetId == a.id,
      );
      expect(got(tester, 'followedAuction'), isTrue);
      expect(await auctions.toggleWatch(marko, a.id), isTrue);
      int reminders() => storage.notifications
          .where(
            (n) => n.kind.name == 'auctionEndingSoon' && n.targetId == a.id,
          )
          .length;
      // Još nije vrijeme.
      await auctions.notifyEndingSoon(now: at.add(const Duration(minutes: 30)));
      expect(reminders(), 0);
      await auctions.notifyEndingSoon(now: at.add(const Duration(minutes: 55)));
      expect(got(marko, 'auctionEndingSoon'), isTrue);
      expect(reminders(), 1);
      // Samo jednom.
      await auctions.notifyEndingSoon(now: at.add(const Duration(minutes: 56)));
      expect(reminders(), 1);
      expect(await auctions.toggleWatch(marko, a.id), isFalse);
    });
  });
}
