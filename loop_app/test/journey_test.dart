import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/services/auction_service.dart';
import 'package:loop_app/services/bargain_service.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/services/dispute_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

/// Cijeli put: objava → kupnja → otprema → spor → povrat → isplata.
void main() {
  const seller = SeedData.demoUserId;
  const buyer = SeedData.testUserId;
  late StorageService storage;
  late TradeService trade;
  late DeliveryService delivery;
  late DisputeService disputes;
  final t0 = DateTime(2026, 11, 1, 12);

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: buyer);
    trade = TradeService(storage);
    delivery = DeliveryService(storage);
    disputes = DisputeService(storage);
  });
  tearDown(() => Hive.close());

  Future<Device> list(double price, {int quantity = 1}) => trade.addDevice(
    userId: seller,
    name: 'Walkman',
    model: '',
    condition: DeviceCondition.good,
    price: price,
    quantity: quantity,
    category: DeviceCategory.values.firstWhere(
      (c) => c.section != ItemSection.digital,
    ),
  );

  Future<Delivery> buyPending(Device d) async {
    final tx = await trade.buy(userId: buyer, deviceId: d.id, now: t0);
    return delivery.createPending(
      id: TradeService.deliveryIdOfBuy(tx),
      userId: buyer,
      deviceId: tx.deviceId,
      deviceName: d.name,
      sellerId: tx.sellerId,
      fromAuction: false,
      now: t0,
    );
  }

  test(
    'prodavač šalje: kupac dobiva broj za praćenje i plaća dostavu jednom',
    () async {
      final d = await list(100);
      final before = storage.userById(seller)!.credits;
      final pending = await buyPending(d);
      expect(pending.awaitingChoice, isTrue);
      expect(storage.userById(seller)!.credits, greaterThan(before));

      final sent = await delivery.ship(
        sellerId: seller,
        deliveryId: pending.id,
        method: DeliveryMethod.courier,
        destination: 'Ilica 1, 10000 Zagreb',
        now: t0,
      );
      expect(sent.trackingNumber, isNotNull);
      // Ponovno slanje ne smije dvaput naplatiti dostavu.
      final again = await delivery.ship(
        sellerId: seller,
        deliveryId: pending.id,
        method: DeliveryMethod.courier,
        destination: 'Ilica 1, 10000 Zagreb',
        now: t0,
      );
      expect(again.trackingNumber, sent.trackingNumber);
      final charges = storage.transactions
          .where((x) => x.type == TransactionType.delivery && x.userId == buyer)
          .length;
      expect(charges, 1);
    },
  );

  test('tuđi prodavač ne može poslati paket', () async {
    final d = await list(50);
    final pending = await buyPending(d);
    expect(
      () => delivery.ship(
        sellerId: SeedData.anaUserId,
        deliveryId: pending.id,
        method: DeliveryMethod.courier,
        destination: 'Ilica 1, 10000 Zagreb',
      ),
      throwsA(isA<TradeException>()),
    );
  });

  test(
    'zarada se ne isplaćuje dok paket ne stigne; povrat ne daje minus',
    () async {
      final d = await list(100);
      final pending = await buyPending(d);
      await delivery.ship(
        sellerId: seller,
        deliveryId: pending.id,
        method: DeliveryMethod.courier,
        destination: 'Ilica 1, 10000 Zagreb',
        now: t0,
      );
      // Paket je na putu: 95 € (100 − 5 % provizije) je zadržano.
      expect(disputes.heldFor(seller, now: t0), 95);
      try {
        await trade.payout(userId: seller, now: t0);
      } on TradeException {
        // Nema ničeg osim zadržanog — isplata se odbija.
      }
      expect(
        storage.userById(seller)!.credits,
        greaterThanOrEqualTo(95),
        reason: 'zadržana zarada mora ostati na računu',
      );

      await disputes.open(
        buyer,
        pending.id,
        DisputeReason.values.first,
        'ne radi',
        now: t0,
      );
      await disputes.respond(seller, pending.id, accept: true, now: t0);
      expect(storage.userById(seller)!.credits, greaterThanOrEqualTo(0));
    },
  );

  test('nakon isporuke zarada je slobodna za isplatu', () async {
    final d = await list(100);
    final pending = await buyPending(d);
    await delivery.ship(
      sellerId: seller,
      deliveryId: pending.id,
      method: DeliveryMethod.courier,
      destination: 'Ilica 1, 10000 Zagreb',
      now: t0,
    );
    final later = t0.add(const Duration(days: 8));
    expect(disputes.heldFor(seller, now: later), 0);
    final tx = await trade.payout(userId: seller, now: later);
    expect(tx.amount, greaterThanOrEqualTo(95));
  });

  test(
    'kupnja zadnjeg komada: drugi kupac ne može kupiti isti predmet',
    () async {
      final d = await list(20);
      await trade.buy(userId: buyer, deviceId: d.id, now: t0);
      expect(
        () => trade.buy(userId: SeedData.anaUserId, deviceId: d.id, now: t0),
        throwsA(isA<TradeException>()),
      );
    },
  );

  test(
    'zaliha od 3 komada daje 3 prodaje i 3 različita predmeta kupcu',
    () async {
      final d = await list(10, quantity: 3);
      final ids = <String>{};
      for (var i = 0; i < 3; i++) {
        final tx = await trade.buy(userId: buyer, deviceId: d.id, now: t0);
        ids.add(tx.deviceId);
      }
      expect(ids.length, 3);
      expect(
        () => trade.buy(userId: buyer, deviceId: d.id, now: t0),
        throwsA(isA<TradeException>()),
      );
      final sales = storage.transactions
          .where((x) => x.type == TransactionType.sell && x.sellerId == seller)
          .length;
      expect(sales, 3);
    },
  );

  test(
    'povrat vraća točno cijenu + dostavu i vraća predmet prodavaču',
    () async {
      final d = await list(100);
      final pending = await buyPending(d);
      final shipped = await delivery.ship(
        sellerId: seller,
        deliveryId: pending.id,
        method: DeliveryMethod.courier,
        destination: 'Ilica 1, 10000 Zagreb',
        now: t0,
      );
      await disputes.open(
        buyer,
        pending.id,
        DisputeReason.values.first,
        '',
        now: t0,
      );
      await disputes.respond(seller, pending.id, accept: true, now: t0);
      final refund = storage.transactions.firstWhere(
        (x) => x.id == 'refund-b-${pending.id}',
      );
      expect(refund.amount, 100 + shipped.cost);
      expect(storage.deviceById(pending.deviceId)!.ownerId, seller);
    },
  );

  test('dogovorena cijena nikad nije viša od trenutne cijene oglasa', () async {
    final d = await list(100);
    final offers = BargainService(storage);
    final offer = await offers.make(
      buyerId: buyer,
      deviceId: d.id,
      amount: 80,
      now: t0,
    );
    await offers.accept(seller, offer.id, now: t0);
    // Prodavač naknadno spusti oglas ispod dogovorene cijene.
    await trade.setDiscount(
      userId: seller,
      deviceId: d.id,
      percent: 50,
      now: t0,
    );
    final tx = await trade.buy(userId: buyer, deviceId: d.id, now: t0);
    expect(tx.price, 50, reason: 'kupac ne smije platiti više od oglasa');
  });

  test('blokirani kupac ne može ni "Kupi odmah" na aukciji', () async {
    final d = await list(40);
    final a = await AuctionService(storage).create(
      userId: seller,
      deviceId: d.id,
      startPrice: 10,
      buyNowPrice: 30,
      duration: const Duration(days: 1),
      now: t0,
    );
    final s = storage.userById(seller)!;
    await storage.putUser(s.copyWith(blockedIds: [buyer]));
    expect(
      () => AuctionService(
        storage,
      ).buyNow(userId: buyer, auctionId: a.id, now: t0),
      throwsA(isA<TradeException>()),
    );
  });

  test(
    'aukcija: pobjednik dobiva predmet i čeka pošiljku od prodavača',
    () async {
      final d = await list(40);
      final svc = AuctionService(storage);
      final a = await svc.create(
        userId: seller,
        deviceId: d.id,
        startPrice: 10,
        duration: const Duration(hours: 1),
        now: t0,
      );
      await svc.placeBid(userId: buyer, auctionId: a.id, amount: 25, now: t0);
      final end = t0.add(const Duration(hours: 2));
      final results = await svc.settleExpired(now: end);
      expect(results.single.winnerId, buyer);
      final del = storage.deliveryById('auction-${a.id}')!;
      expect(del.awaitingChoice, isTrue);
      expect(del.sellerId, seller);
      // Drugi poziv ne smije ponovno zaračunati zaradu ni napraviti drugu pošiljku.
      final credits = storage.userById(seller)!.credits;
      await svc.settleExpired(now: end);
      expect(storage.userById(seller)!.credits, credits);
      expect(
        storage.deliveries.where((x) => x.id == 'auction-${a.id}').length,
        1,
      );
    },
  );

  test(
    'zaliha: povrat komada oduzima zaradu prodavaču i zadržava je u sporu',
    () async {
      final d = await list(100, quantity: 2);
      final before = storage.userById(seller)!.credits;
      final pending = await buyPending(d);
      expect(pending.deviceId, isNot(d.id), reason: 'kupac dobiva novi komad');
      expect(storage.userById(seller)!.credits, before + 95);
      await delivery.ship(
        sellerId: seller,
        deliveryId: pending.id,
        method: DeliveryMethod.courier,
        destination: 'Ilica 1, 10000 Zagreb',
        now: t0,
      );
      expect(disputes.heldFor(seller, now: t0), 95, reason: 'komad na putu');
      await disputes.open(
        buyer,
        pending.id,
        DisputeReason.values.first,
        '',
        now: t0,
      );
      await disputes.respond(seller, pending.id, accept: true, now: t0);
      expect(storage.userById(seller)!.credits, before);
    },
  );
}
