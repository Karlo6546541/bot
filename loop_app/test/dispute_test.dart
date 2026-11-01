import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/services/dispute_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  const seller = SeedData.demoUserId;
  const buyer = SeedData.testUserId;
  late StorageService storage;
  late DisputeService disputes;
  final t0 = DateTime(2026, 11, 1, 12);

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: buyer);
    disputes = DisputeService(storage);
  });
  tearDown(() => Hive.close());

  /// Prodaja: kupac je platio 100 €, prodavatelj je dobio 90 €.
  Future<Delivery> sale(String id) async {
    final d = await TradeService(storage).addDevice(
      userId: seller,
      name: 'Walkman $id',
      model: '',
      condition: DeviceCondition.good,
      price: 100,
      category: DeviceCategory.values.firstWhere(
        (c) => c.section != ItemSection.digital,
      ),
    );
    await storage.putDevice(d.withOwner(buyer));
    await storage.putTransaction(
      LoopTransaction(
        id: 'sale-$id',
        type: TransactionType.sell,
        userId: seller,
        deviceId: d.id,
        deviceName: d.name,
        price: 100,
        fee: 10,
        amount: 90,
        buyerId: buyer,
        sellerId: seller,
        buyerLabel: 'kupac',
        sellerLabel: 'prodavac',
        createdAt: t0,
      ),
    );
    final u = storage.userById(seller)!;
    await storage.putUser(u.copyWith(credits: 90));
    return DeliveryService(storage).createStarted(
      id: 'del-$id',
      userId: buyer,
      deviceId: d.id,
      deviceName: d.name,
      method: DeliveryMethod.courier,
      destination: 'Ilica 1, 10000 Zagreb',
      sellerId: seller,
      now: t0,
    );
  }

  test('povrat: zarada zadržana, prodavatelj prihvati, novac kupcu', () async {
    final d = await sale('a');
    expect(disputes.canOpen(d, now: t0), isTrue);
    await disputes.open(
      buyer,
      d.id,
      DisputeReason.notArrived,
      'Nema ga',
      now: t0,
    );
    expect(disputes.heldFor(seller), 90);
    // Isplata nije moguća dok traje spor (sva zarada je zadržana).
    expect(
      () => TradeService(storage).payout(userId: seller, now: t0),
      throwsA(isA<TradeException>()),
    );
    // Samo prodavatelj odgovara.
    await expectLater(
      disputes.respond(buyer, d.id, accept: true, now: t0),
      throwsA(isA<TradeException>()),
    );
    final done = await disputes.respond(seller, d.id, accept: true, now: t0);
    expect(done.dispute!.status, DisputeStatus.refunded);
    expect(done.dispute!.refundAmount, 100 + d.cost);
    expect(storage.userById(seller)!.credits, 0);
    expect(disputes.heldFor(seller), 0);
    expect(storage.deviceById(d.deviceId)!.ownerId, seller);
    final refunds = storage.transactions.where(
      (x) => x.type == TransactionType.refund,
    );
    expect(refunds.map((x) => x.userId).toSet(), {buyer, seller});
    // Drugi zahtjev za istu kupnju nije moguć.
    expect(disputes.canOpen(storage.deliveryById(d.id)!, now: t0), isFalse);
  });

  test('odbijeno: odlučuje Subhasto; bez odgovora povrat nakon 72 h', () async {
    final a = await sale('b');
    await disputes.open(buyer, a.id, DisputeReason.damaged, '', now: t0);
    final review = await disputes.respond(seller, a.id, accept: false, now: t0);
    expect(review.dispute!.status, DisputeStatus.review);
    expect(disputes.heldFor(seller), 90);
    final rejected = await disputes.decide(a.id, refund: false, now: t0);
    expect(rejected.dispute!.status, DisputeStatus.rejected);
    expect(disputes.heldFor(seller), 0);
    expect(storage.userById(seller)!.credits, 90);

    final b = await sale('c');
    await disputes.open(buyer, b.id, DisputeReason.notAsDescribed, '', now: t0);
    expect(await disputes.expire(now: t0.add(const Duration(hours: 71))), 0);
    expect(await disputes.expire(now: t0.add(const Duration(hours: 73))), 1);
    expect(storage.deliveryById(b.id)!.dispute!.status, DisputeStatus.refunded);
  });

  test('privatni prodavatelj: nakon potvrde primitka nema povrata', () async {
    final d = await sale('d');
    final confirmed = d.copyWith(confirmedAt: t0);
    await storage.putDelivery(confirmed);
    expect(disputes.canOpen(confirmed, now: t0), isFalse);
  });
}
