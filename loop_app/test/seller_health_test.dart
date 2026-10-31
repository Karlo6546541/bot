import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/screens/seller_finance_screens.dart';
import 'package:loop_app/models/report.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/screens/seller_hub.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  const seller = SeedData.demoUserId;
  const buyer = SeedData.testUserId;
  late StorageService storage;
  late DeliveryService deliveries;
  final t0 = DateTime(2026, 10, 23, 20);

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: seller);
    deliveries = DeliveryService(storage);
  });
  tearDown(() => Hive.close());

  Future<Delivery> ship(String id, {DateTime? at}) => deliveries.createStarted(
    id: id,
    userId: buyer,
    deviceId: 'd-$id',
    deviceName: 'Predmet $id',
    method: DeliveryMethod.courier,
    destination: 'Ilica 1, Zagreb',
    sellerId: seller,
    free: true,
    now: at ?? t0,
  );

  AccountHealth health(DateTime now) =>
      AccountHealth.of(AppState.fromStorage(storage), seller, now);

  test('predaja paketa: samo prodavač, jednom, mjeri se rok od 48 h', () async {
    final a = await ship('a');
    await expectLater(
      deliveries.markHandedOver(buyer, a.id),
      throwsA(isA<TradeException>()),
    );
    // Predano u roku.
    await deliveries.markHandedOver(
      seller,
      a.id,
      now: t0.add(const Duration(hours: 5)),
    );
    // Drugo predavanje ne mijenja vrijeme.
    final again = await deliveries.markHandedOver(
      seller,
      a.id,
      now: t0.add(const Duration(hours: 30)),
    );
    expect(again.handedOverAt, t0.add(const Duration(hours: 5)));

    final late = await ship('b');
    final during = t0.add(const Duration(hours: 10));
    // Rok još nije istekao: b se ne računa.
    expect(health(during).onTimeRate, 1.0);
    // Rok istekao bez predaje: b kasni.
    expect(health(t0.add(const Duration(hours: 49))).onTimeRate, 0.5);
    // Predano nakon roka: i dalje kasni.
    await deliveries.markHandedOver(
      seller,
      late.id,
      now: t0.add(const Duration(hours: 50)),
    );
    expect(health(t0.add(const Duration(hours: 51))).onTimeRate, 0.5);
  });

  test('pravila zajednice: prijave u zadnjih 180 dana', () async {
    final now = t0.add(const Duration(days: 1));
    expect(health(now).policy, HealthLevel.excellent);
    final base = Report(
      id: 'r1',
      reporterId: buyer,
      reporterLabel: '@test',
      targetType: 'user',
      targetId: seller,
      targetLabel: '@demo',
      reason: ReportReason.scam,
      createdAt: t0,
    );
    await storage.putReport(base);
    expect(health(now).policy, HealthLevel.good);
    expect(health(now).openReports, 1);
    await storage.putReport(base.close(ReportStatus.resolved, now));
    expect(health(now).policy, HealthLevel.attention);
    expect(health(now).level, HealthLevel.attention);
    // Starije od 180 dana ne računa.
    expect(
      health(t0.add(const Duration(days: 200))).policy,
      HealthLevel.excellent,
    );
    // Odbačena prijava ne računa.
    await storage.putReport(base.close(ReportStatus.dismissed, now));
    expect(health(now).policy, HealthLevel.excellent);
  });

  test(
    'dupliciranje showa: samo završen, prenosi predmete koji su još moji',
    () async {
      final trade = TradeService(storage);
      final live = LiveService(storage);
      final items = [
        for (final n in ['Game Boy', 'Walkman'])
          await trade.addDevice(
            userId: seller,
            name: n,
            model: 'Retro',
            condition: DeviceCondition.good,
            price: 20,
            category: DeviceCategory.values.firstWhere(
              (c) => c.section != ItemSection.digital,
            ),
          ),
      ];
      final show = await live.create(
        hostId: seller,
        title: 'Retro večer',
        items: [for (final d in items) (d.id, 5.0)],
        startsAt: t0,
        now: t0,
      );
      // Dok je show aktivan, dupliciranje nije moguće.
      await expectLater(
        live.duplicate(
          seller,
          show.id,
          t0.add(const Duration(days: 1)),
          now: t0.add(const Duration(minutes: 1)),
        ),
        throwsA(isA<TradeException>()),
      );
      final end = t0.add(const Duration(minutes: 10));
      await live.end(seller, show.id, now: end);
      final copy = await live.duplicate(
        seller,
        show.id,
        t0.add(const Duration(days: 1)),
        now: end.add(const Duration(minutes: 1)),
      );
      expect(copy.id, isNot(show.id));
      expect(copy.title, 'Retro večer');
      expect(copy.lots, hasLength(2));
      expect(copy.lots.first.startPrice, 5);
    },
  );

  test('uređivanje zakazanog showa: naslov, početak, kategorija', () async {
    final live = LiveService(storage);
    final show = await live.create(
      hostId: seller,
      title: 'Stari naslov',
      startsAt: t0.add(const Duration(hours: 3)),
      now: t0,
    );
    final edited = await live.edit(
      seller,
      show.id,
      title: 'Novi naslov',
      startsAt: t0.add(const Duration(hours: 5)),
      category: 'other',
      now: t0,
    );
    expect(edited.title, 'Novi naslov');
    expect(edited.startsAt, t0.add(const Duration(hours: 5)));
    expect(edited.category, 'other');
    await expectLater(
      live.edit(buyer, show.id, title: 'Tuđe', now: t0),
      throwsA(isA<TradeException>()),
    );
    await expectLater(
      live.edit(seller, show.id, title: 'ab', now: t0),
      throwsA(isA<TradeException>()),
    );
    // Show koji je počeo (domaćin je u sobi) više se ne uređuje.
    await live.heartbeat(seller, show.id, now: t0);
    await expectLater(
      live.edit(seller, show.id, title: 'Prekasno', now: t0),
      throwsA(isA<TradeException>()),
    );
  });

  test('analitika showa i tjedni CSV', () async {
    final trade = TradeService(storage);
    final live = LiveService(storage);
    final d = await trade.addDevice(
      userId: seller,
      name: 'Walkman',
      model: 'Retro',
      condition: DeviceCondition.good,
      price: 20,
      category: DeviceCategory.values.firstWhere(
        (c) => c.section != ItemSection.digital,
      ),
    );
    final show = await live.create(
      hostId: seller,
      title: 'Analitika show',
      items: [(d.id, 5.0)],
      startsAt: t0,
      now: t0,
    );
    await live.join(buyer, show.id, now: t0.add(const Duration(seconds: 1)));
    await live.startLot(seller, show.id, index: 0, now: t0);
    await live.bid(buyer, show.id, 8, now: t0.add(const Duration(seconds: 5)));
    await live.end(seller, show.id, now: t0.add(const Duration(minutes: 2)));
    await live.settleDue(now: t0.add(const Duration(minutes: 3)));
    final s = AppState.fromStorage(storage);
    final a = ShowAnalytics.of(
      s,
      storage.liveShowById(show.id)!,
      storage.liveEventsOf(show.id),
      t0.add(const Duration(minutes: 3)),
    );
    expect(a.orders, 1);
    expect(a.sales, 8); // jedini ponuditelj plaća svoju ponudu
    expect(a.buyers, 1);
    expect(a.newBuyers, 1);
    expect(a.bids, 1);
    expect(a.viewers, 1);
    expect(a.topBuyers.first.userId, buyer);
    final sales = sellerLedger(
      s,
      seller,
    ).where((tx) => tx.type == TransactionType.sell).toList();
    final csv = weeklyReportCsv(sales, weekStart(t0), s.userLabel);
    expect(csv.split('\n').length, greaterThan(2));
    expect(csv, contains('Walkman'));
  });
}
