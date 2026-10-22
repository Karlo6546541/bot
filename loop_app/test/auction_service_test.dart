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

  test('seed: 4 aukcije, ponude ne blokiraju novac (plaća se karticom)', () {
    expect(storage.auctions.where((a) => a.isActive), hasLength(4));
    expect(credits(marko), 1500);
    expect(storage.deviceById('seed-34')!.ownerId, ana);
    expect(auction('1').currentPrice, 320);
    expect(auction('1').minNextBid, 336); // 320 + 5%
  });

  test('ponuda ne dira stanje (pobjednik plaća karticom na kraju)', () async {
    await auctions.placeBid(
      userId: demo,
      auctionId: 'seed-auction-1',
      amount: 340,
    );
    expect(credits(demo), 1250);
    expect(credits(marko), 1500);
    expect(auction('1').highestBid!.userId, demo);
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

  test(
    'ponuda ne može biti manja od minimuma; stanje je ne ograničava',
    () async {
      await expectLater(
        auctions.placeBid(
          userId: tester,
          auctionId: 'seed-auction-1',
          amount: 330,
        ),
        throwsA(isA<TradeException>()),
      );
      // Plaća se karticom: ponuda veća od zarade je dopuštena.
      await auctions.placeBid(
        userId: tester,
        auctionId: 'seed-auction-1',
        amount: 801,
      );
      expect(credits(tester), 800);
    },
  );

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
    expect(credits(marko), 1500); // pobjednik plaća karticom

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
    expect(auction('1').status, AuctionStatus.cancelled);
    expect(credits(marko), 1500); // ništa nije bilo naplaćeno
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
    expect(upgraded.userById(marko)!.credits, 1500);
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
      expect(credits(demo), 1250); // ništa se ne blokira
      expect(auction('1').autoMaxOf(demo), 500);

      // Test nudi 360 — demo automatski odgovara korakom (360 + 18).
      await auctions.placeBid(
        userId: tester,
        auctionId: 'seed-auction-1',
        amount: 360,
      );
      expect(auction('1').highestBid!.userId, demo);
      expect(auction('1').highestBid!.amount, 378);
      expect(credits(demo), 1250);
      expect(credits(tester), 800);
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
      expect(credits(demo), 1250);
      expect(credits(tester), 800);
      expect(a.autoMaxOf(demo), isNull);

      // Vodeći smije samo povisiti svoj maksimum.
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
          maxAmount: 650,
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
      // Plaća se karticom: stanja kupaca se ne mijenjaju.
      expect(credits(tester), 800);
      expect(credits(marko), 1500);
      expect(credits(demo), 1250 + 300); // prodavatelj dobiva zaradu
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
