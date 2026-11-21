import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/l10n/tr.dart';
import 'package:loop_app/models/app_notification.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/models/report.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/services/account_service.dart';
import 'package:loop_app/services/auction_service.dart';
import 'package:loop_app/services/auth_backend.dart';
import 'package:loop_app/services/community_service.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

/// Ocjene, obavijesti, prijave i blokiranje.
void main() {
  late StorageService storage;
  late TradeService trade;
  late CommunityService community;
  const iphone = 'seed-9'; // demo korisnik

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    trade = TradeService(storage);
    community = CommunityService(storage);
  });

  tearDown(() async {
    Tr.lang = AppLang.hr;
    await Hive.close();
  });

  List<AppNotification> inboxOf(String userId) =>
      storage.notifications.where((n) => n.userId == userId).toList();

  /// Test kupuje demo iPhone koji je objavljen u Marketu i potvrđuje primitak.
  Future<Delivery> boughtAndReceived() async {
    await trade.list(userId: SeedData.demoUserId, deviceId: iphone, price: 200);
    final device = storage.deviceById(iphone)!;
    final tx = await trade.buy(userId: SeedData.testUserId, deviceId: iphone);
    final at = DateTime.now();
    final d = await DeliveryService(storage).createForPurchase(
      userId: SeedData.testUserId,
      device: device,
      method: DeliveryMethod.pickup,
      sellerId: tx.sellerId,
      now: at,
    );
    await DeliveryService(storage).confirmReceipt(
      SeedData.testUserId,
      d.id,
      now: at.add(const Duration(days: 1)),
    );
    return storage.deliveryById(d.id)!;
  }

  group('ocjene', () {
    test('nakon primitka, jednom, 1–5 zvjezdica', () async {
      final d = await boughtAndReceived();
      expect(d.canReview, isTrue);
      await expectLater(
        community.review(
          buyerId: SeedData.testUserId,
          deliveryId: d.id,
          stars: 6,
        ),
        throwsA(isA<TradeException>()),
      );
      await expectLater(
        community.review(
          buyerId: SeedData.demoUserId, // nije kupac
          deliveryId: d.id,
          stars: 5,
        ),
        throwsA(isA<TradeException>()),
      );
      final r = await community.review(
        buyerId: SeedData.testUserId,
        deliveryId: d.id,
        stars: 4,
        comment: 'Sve OK',
      );
      expect(r.sellerId, SeedData.demoUserId);
      expect(storage.deliveryById(d.id)!.reviewed, isTrue);
      await expectLater(
        community.review(
          buyerId: SeedData.testUserId,
          deliveryId: d.id,
          stars: 5,
        ),
        throwsA(isA<TradeException>()),
      );

      await storage.saveSession(userId: SeedData.testUserId);
      final state = AppState.fromStorage(storage);
      expect(state.ratingOf(SeedData.demoUserId).average, 4);
      expect(state.ratingOf(SeedData.demoUserId).count, 1);
      // Prodavatelj je dobio obavijest.
      expect(
        inboxOf(SeedData.demoUserId).map((n) => n.kind),
        contains(NotificationKind.newReview),
      );
    });
  });

  group('obavijesti', () {
    test('prodaja objavljenog predmeta', () async {
      await trade.list(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        price: 200,
      );
      await trade.buy(userId: SeedData.testUserId, deviceId: iphone);
      final n = inboxOf(SeedData.demoUserId).single;
      expect(n.kind, NotificationKind.itemSold);
      // 200 € − 5 % provizije.
      expect(n.text, '@test je kupio tvoj predmet "iPhone 13". Dobivaš 190 €.');
      // Tekst se prevodi pri prikazu, s engleskim brojevima.
      Tr.lang = AppLang.en;
      expect(n.text, '@test bought your item "iPhone 13". You get €190.');
    });

    test('pojeftinjenje predmeta s liste želja', () async {
      await trade.list(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        price: 300,
      );
      await trade.toggleFavorite(SeedData.testUserId, iphone);
      await trade.list(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        price: 250,
      );
      expect(
        inboxOf(SeedData.testUserId).single.kind,
        NotificationKind.priceDrop,
      );
      // Poskupljenje ne šalje obavijest.
      await trade.list(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        price: 280,
      );
      expect(inboxOf(SeedData.testUserId), hasLength(1));
    });

    test('aukcija: nadmašen, nova ponuda, kraj', () async {
      final auctions = AuctionService(storage);
      // Marko vodi na seed-auction-2 (60) — demo ga nadmaši.
      await auctions.placeBid(
        userId: SeedData.demoUserId,
        auctionId: 'seed-auction-2',
        amount: 100,
      );
      expect(
        inboxOf(SeedData.markoUserId).single.kind,
        NotificationKind.outbid,
      );
      expect(inboxOf(SeedData.anaUserId).single.kind, NotificationKind.newBid);

      await auctions.settleExpired(
        now: DateTime.now().add(const Duration(hours: 4)),
      );
      expect(
        inboxOf(SeedData.demoUserId).map((n) => n.kind),
        contains(NotificationKind.auctionWon),
      );
      expect(
        inboxOf(SeedData.markoUserId).map((n) => n.kind),
        contains(NotificationKind.auctionLost),
      );
      expect(
        inboxOf(SeedData.anaUserId).map((n) => n.kind),
        contains(NotificationKind.auctionSold),
      );
    });

    test('poziv prijatelja', () async {
      final accounts = AccountService(storage, LocalAuthBackend(storage));
      await accounts.register(
        email: 'novi@loop.com',
        password: 'tajna123',
        username: 'novi',
        referral: 'demo',
      );
      expect(
        inboxOf(SeedData.demoUserId).single.kind,
        NotificationKind.referral,
      );
    });

    test('označi kao pročitano', () async {
      await trade.list(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        price: 200,
      );
      await trade.buy(userId: SeedData.testUserId, deviceId: iphone);
      await storage.saveSession(userId: SeedData.demoUserId);
      expect(AppState.fromStorage(storage).unreadNotifications, 1);
      await community.markRead(SeedData.demoUserId);
      expect(AppState.fromStorage(storage).unreadNotifications, 0);
    });
  });

  group('prijave', () {
    test('oglas i korisnik; bez duplikata i samoprijave', () async {
      await trade.list(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        price: 200,
      );
      final r = await community.report(
        reporterId: SeedData.testUserId,
        targetType: 'device',
        targetId: iphone,
        reason: ReportReason.scam,
        note: 'Previše jeftino',
      );
      expect(r.targetLabel, 'iPhone 13 128GB');
      await expectLater(
        community.report(
          reporterId: SeedData.testUserId,
          targetType: 'device',
          targetId: iphone,
          reason: ReportReason.spam,
        ),
        throwsA(isA<TradeException>()),
      );
      await expectLater(
        community.report(
          reporterId: SeedData.demoUserId,
          targetType: 'device',
          targetId: iphone,
          reason: ReportReason.spam,
        ),
        throwsA(isA<TradeException>()),
      );
      await expectLater(
        community.report(
          reporterId: SeedData.demoUserId,
          targetType: 'user',
          targetId: SeedData.demoUserId,
          reason: ReportReason.spam,
        ),
        throwsA(isA<TradeException>()),
      );

      await community.closeReport(r.id, ReportStatus.resolved);
      expect(storage.reports.single.isOpen, isFalse);
      expect(
        inboxOf(SeedData.testUserId).single.kind,
        NotificationKind.reportResolved,
      );
    });
  });

  group('blokiranje', () {
    test('skriva oglase, onemogućuje kupnju i licitiranje', () async {
      await trade.list(
        userId: SeedData.demoUserId,
        deviceId: iphone,
        price: 200,
      );
      // Test blokira demo → ne vidi njegov oglas.
      expect(
        await community.toggleBlock(SeedData.testUserId, SeedData.demoUserId),
        isTrue,
      );
      await storage.saveSession(userId: SeedData.testUserId);
      expect(
        AppState.fromStorage(storage).marketDevices.map((d) => d.id),
        isNot(contains(iphone)),
      );
      // Demo blokira marka → marko ne može kupiti od demo.
      await community.toggleBlock(SeedData.demoUserId, SeedData.markoUserId);
      await expectLater(
        trade.buy(userId: SeedData.markoUserId, deviceId: iphone),
        throwsA(isA<TradeException>()),
      );
      // Ana blokira marka → ne može licitirati na njenim aukcijama.
      await community.toggleBlock(SeedData.anaUserId, SeedData.markoUserId);
      await expectLater(
        AuctionService(storage).placeBid(
          userId: SeedData.markoUserId,
          auctionId: 'seed-auction-3',
          amount: 50,
        ),
        throwsA(isA<TradeException>()),
      );
      // Odblokiranje.
      expect(
        await community.toggleBlock(SeedData.testUserId, SeedData.demoUserId),
        isFalse,
      );
      await expectLater(
        community.toggleBlock(SeedData.testUserId, SeedData.testUserId),
        throwsA(isA<TradeException>()),
      );
    });
  });
}
