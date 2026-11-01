import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/live_boost.dart';
import 'package:loop_app/models/live_show.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/screens/show_checklist_screen.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  const host = SeedData.demoUserId;
  const viewer = SeedData.testUserId;
  late StorageService storage;
  late LiveService live;
  final t0 = DateTime(2026, 11, 1, 20);

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: host);
    live = LiveService(storage);
  });
  tearDown(() => Hive.close());

  Future<LiveShow> makeShow(DateTime startsAt) async {
    final d = await TradeService(storage).addDevice(
      userId: host,
      name: 'Walkman',
      model: 'Retro',
      condition: DeviceCondition.good,
      price: 20,
      category: DeviceCategory.values.firstWhere(
        (c) => c.section != ItemSection.digital,
      ),
    );
    return live.create(
      hostId: host,
      title: 'Retro večer',
      items: [(d.id, 5.0)],
      startsAt: startsAt,
      now: t0,
    );
  }

  test('brzi boost: samo domaćin, samo uživo, 15 min, nižu se', () async {
    final show = await makeShow(t0);
    await expectLater(
      live.boost(viewer, show.id, BoostKind.quick, 5, now: t0),
      throwsA(isA<TradeException>()),
    );
    await expectLater(
      live.boost(host, show.id, BoostKind.quick, 0.5, now: t0),
      throwsA(isA<TradeException>()),
    );
    final b = await live.boost(host, show.id, BoostKind.quick, 5, now: t0);
    expect(b.kind, BoostKind.quick);
    expect(b.until, t0.add(const Duration(minutes: 15)));
    // Drugi boost kupljen dok prvi traje počinje kad prvi završi.
    await live.heartbeat(
      host,
      show.id,
      now: t0.add(const Duration(minutes: 5)),
    );
    final b2 = await live.boost(
      host,
      show.id,
      BoostKind.quick,
      3,
      now: t0.add(const Duration(minutes: 5)),
    );
    expect(b2.weight, 5);
    expect(b2.spent, 8);
    final later = live
        .stateOf(show, now: t0.add(const Duration(minutes: 20)))
        .boost;
    expect(later.kind, BoostKind.quick);
    expect(later.until, t0.add(const Duration(minutes: 30)));
    // Plaćanje je zapisano kao promocija u transakcijama domaćina.
    final txs = storage.transactions.where(
      (t) => t.type == TransactionType.promotion && t.userId == host,
    );
    expect(txs.map((t) => t.amount).toList()..sort(), [3, 5]);
  });

  test('promocija zakazanog showa: jednom, ne prije plaćanja', () async {
    final show = await makeShow(t0.add(const Duration(days: 1)));
    await expectLater(
      live.boost(host, show.id, BoostKind.quick, 5, now: t0),
      throwsA(isA<TradeException>()),
    );
    expect(live.stateOf(show, now: t0).boost.active, isFalse);
    final b = await live.boost(host, show.id, BoostKind.show, 6, now: t0);
    expect(b.kind, BoostKind.show);
    expect(b.until, show.startsAt.add(LiveBoost.showPromoAfterStart));
    await expectLater(
      live.boost(host, show.id, BoostKind.show, 6, now: t0),
      throwsA(isA<TradeException>()),
    );
  });

  test('community boost: 10 različitih gledatelja podijeli live', () {
    final show = LiveShow.fromMap({
      'id': 's1',
      'hostId': host,
      'title': 'x',
      'startsAt': t0.toIso8601String(),
      'createdAt': t0.toIso8601String(),
      'lots': <dynamic>[],
    });
    LiveEvent share(String user, int minute) => LiveEvent(
      id: '$user-$minute',
      showId: 's1',
      type: LiveEventType.share,
      userId: user,
      userLabel: user,
      at: t0.add(Duration(minutes: minute)),
    );
    final events = [
      for (var i = 0; i < 9; i++) share('u$i', i),
      share('u0', 9), // isti gledatelj se ne broji dvaput
      share(host, 9), // domaćin se ne broji
    ];
    final before = LiveBoost.of(
      show,
      events,
      t0.add(const Duration(minutes: 10)),
      liveFrom: t0,
    );
    expect(before.sharers, 9);
    expect(before.active, isFalse);
    events.add(share('u9', 10));
    final after = LiveBoost.of(
      show,
      events,
      t0.add(const Duration(minutes: 11)),
      liveFrom: t0,
    );
    expect(after.communityUnlocked, isTrue);
    expect(after.kind, BoostKind.community);
    expect(after.until, t0.add(const Duration(minutes: 25)));
    // Nakon 15 minuta boost prestaje.
    final done = LiveBoost.of(
      show,
      events,
      t0.add(const Duration(minutes: 26)),
      liveFrom: t0,
    );
    expect(done.active, isFalse);
    expect(done.communityUnlocked, isTrue);
  });

  test('dijeljenje: jednom po gledatelju, domaćin se ne broji', () async {
    final show = await makeShow(t0);
    await live.shared(viewer, show.id, now: t0);
    await live.shared(viewer, show.id, now: t0);
    await live.shared(host, show.id, now: t0);
    expect(
      storage.liveEventsOf(show.id).where((e) => e.type == LiveEventType.share),
      hasLength(1),
    );
    expect(live.stateOf(show, now: t0).boost.sharers, 1);
  });

  test('priprema showa: predmeti i kupci otključavaju korake', () async {
    final show = await makeShow(t0.add(const Duration(days: 1)));
    var done = showPrepDone(
      show,
      storage.liveEventsOf(show.id),
      promoted: false,
    );
    expect(done, {ShowPrepStep.create, ShowPrepStep.products});
    await live.shared(viewer, show.id, now: t0);
    done = showPrepDone(show, storage.liveEventsOf(show.id), promoted: false);
    expect(done, contains(ShowPrepStep.buyers));
  });
}
