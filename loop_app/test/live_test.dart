import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/models/app_notification.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/models/live_show.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/live_video.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

/// Signalizacija za video u memoriji: poruke idu svim ostalim
/// sudionicima (kao Supabase broadcast bez "self").
class FakeHub {
  final sent = <Map<String, dynamic>>[];
  final _listeners = <void Function(Map<String, dynamic>)>[];

  LiveSignaling channel(String showId) => _FakeSignaling(this);

  /// Poruka "izvana" (npr. od domaćina na drugom uređaju).
  void deliver(Map<String, dynamic> m) {
    for (final l in [..._listeners]) {
      l(m);
    }
  }
}

class _FakeSignaling implements LiveSignaling {
  _FakeSignaling(this.hub);
  final FakeHub hub;
  void Function(Map<String, dynamic>)? _on;

  @override
  Future<void> join(void Function(Map<String, dynamic>) onMessage) async {
    _on = onMessage;
    hub._listeners.add(onMessage);
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    hub.sent.add(message);
    for (final l in [...hub._listeners]) {
      if (l != _on) l(message);
    }
  }

  @override
  Future<void> leave() async => hub._listeners.remove(_on);
}

/// Live aukcije (kao Whatnot).
void main() {
  const host = SeedData.demoUserId;
  const bob = SeedData.testUserId;
  const ana = SeedData.anaUserId;
  const marko = SeedData.markoUserId;

  Future<Device> addItem(TradeService trade, String owner, String name) =>
      trade.addDevice(
        userId: owner,
        name: name,
        model: 'Retro',
        condition: DeviceCondition.good,
        price: 100,
        category: DeviceCategory.values.firstWhere(
          (c) => c.section != ItemSection.digital,
        ),
      );

  group('servis', () {
    late StorageService storage;
    late LiveService live;
    late TradeService trade;
    late List<Device> items;
    final t0 = DateTime(2026, 10, 23, 20);

    DateTime at(int s) => t0.add(Duration(seconds: s));

    Future<String> start({int secs = 30}) async {
      final show = await live.create(
        hostId: host,
        title: 'Retro igre od 1 €',
        items: [for (final d in items) (d.id, 1.0)],
        lotSeconds: secs,
        startsAt: t0,
        now: t0,
      );
      return show.id;
    }

    LiveState state(String id, int s) =>
        live.stateOf(storage.liveShowById(id)!, now: at(s));

    setUp(() async {
      storage = StorageService();
      await storage.init(inMemory: true);
      live = LiveService(storage);
      trade = TradeService(storage);
      items = [
        for (final n in ['Game Boy', 'Walkman', 'Polaroid'])
          await addItem(trade, host, n),
      ];
    });
    tearDown(() => Hive.close());

    test(
      'objava: predmeti izlaze iz Marketa, pratitelji dobivaju obavijest',
      () async {
        final fan = storage.userById(bob)!;
        await storage.putUser(fan.copyWith(following: [host]));
        expect(items.every((d) => d.isListed), isTrue);

        final id = await start();
        expect(items.every((d) => !storage.deviceById(d.id)!.isListed), isTrue);
        final note = storage.notifications.where(
          (n) => n.userId == bob && n.kind == NotificationKind.liveStarted,
        );
        expect(note, hasLength(1));
        expect(note.first.targetId, id);

        // Drugi live dok prvi traje nije dopušten.
        await expectLater(start(), throwsA(isA<TradeException>()));
      },
    );

    test('objava: samo vlastiti, ne digitalni predmeti, do 7 dana', () async {
      final foreign = await addItem(trade, bob, 'Tuđe');
      await expectLater(
        live.create(
          hostId: host,
          title: 'Tuđe stvari',
          items: [(foreign.id, 1)],
          now: t0,
        ),
        throwsA(isA<TradeException>()),
      );
      await expectLater(
        live.create(hostId: host, title: 'Prazno', items: [], now: t0),
        throwsA(isA<TradeException>()),
      );
      await expectLater(
        live.create(
          hostId: host,
          title: 'Predaleko',
          items: [(items.first.id, 1)],
          startsAt: t0.add(const Duration(days: 8)),
          now: t0,
        ),
        throwsA(isA<TradeException>()),
      );
      await expectLater(
        live.create(
          hostId: host,
          title: 'Ok',
          items: [(items.first.id, 0.5)],
          now: t0,
        ),
        throwsA(isA<TradeException>()),
      );
    });

    test('predmeti idu redom s pauzom; bez ponuda ostaju domaćinu', () async {
      final id = await start();
      expect(
        live.stateOf(storage.liveShowById(id)!, now: at(-60)).isScheduled,
        isTrue,
      );
      expect(state(id, 10).current!.index, 0);
      // Kraj prvog (30 s) → pauza 5 s → drugi.
      final gap = state(id, 32);
      expect(gap.current, isNull);
      expect(gap.lots[0].status, LotStatus.unsold);
      expect(gap.isLive, isTrue);
      expect(state(id, 36).current!.index, 1);
      expect(state(id, 71).current!.index, 2);
      final over = state(id, 200);
      expect(over.isOver, isTrue);
      expect(over.soldCount, 0);
      expect(await live.settleDue(now: at(200)), 0);
      expect(storage.deviceById(items[0].id)!.ownerId, host);
    });

    test(
      'ponude: minimum, vodeći ne licitira sam sebe, domaćin ne licitira',
      () async {
        final id = await start();
        await live.bid(bob, id, 1, now: at(5));
        await expectLater(
          live.bid(bob, id, 5, now: at(6)),
          throwsA(isA<TradeException>()),
        );
        await expectLater(
          live.bid(host, id, 5, now: at(6)),
          throwsA(isA<TradeException>()),
        );
        final lot = state(id, 6).current!;
        expect(lot.leader!.userId, bob);
        expect(lot.minNext, greaterThan(1));
        await expectLater(
          live.bid(ana, id, 1, now: at(7)),
          throwsA(isA<TradeException>()),
        );
        final next = await live.bid(ana, id, lot.minNext, now: at(7));
        expect(next.current!.leader!.userId, ana);
        expect(next.current!.bids, hasLength(2));
      },
    );

    test('ponuda u zadnjih 10 s vraća sat na 10 s', () async {
      final id = await start();
      await live.bid(bob, id, 2, now: at(25));
      final lot = state(id, 26).current!;
      expect(lot.end, at(35));
      expect(state(id, 33).current!.index, 0);
      // Sljedeći kreće 5 s nakon produljenog kraja.
      expect(state(id, 37).lots[1].start, at(40));
      expect(state(id, 37).lots[0].status, LotStatus.sold);
    });

    test('prodaju provodi pobjednik ili domaćin — samo jednom', () async {
      final id = await start();
      await live.bid(bob, id, 3, now: at(5));
      final hostCredits = storage.userById(host)!.credits;
      final bobCredits = storage.userById(bob)!.credits;

      // Netko treći ne provodi tuđu prodaju.
      expect(await live.settleDue(userId: marko, now: at(40)), 0);
      expect(await live.settleDue(userId: bob, now: at(40)), 1);
      expect(storage.deviceById(items[0].id)!.ownerId, bob);
      expect(storage.userById(host)!.credits, hostCredits + 3);
      // Kupac plaća karticom — stanje mu se ne dira.
      expect(storage.userById(bob)!.credits, bobCredits);
      final tx = storage.transactions.firstWhere((t) => t.id == 'live-$id-0');
      expect(tx.type, TransactionType.sell);
      expect(tx.buyerId, bob);
      expect(tx.isAuction, isTrue);
      expect(storage.deliveryById('live-$id-0'), isNotNull);
      expect(storage.liveShowById(id)!.settled, [0]);
      expect(
        storage.notifications.any(
          (n) => n.userId == bob && n.kind == NotificationKind.auctionWon,
        ),
        isTrue,
      );

      // Ponovno (npr. domaćin s drugog uređaja) — ništa novo.
      expect(await live.settleDue(userId: host, now: at(41)), 0);
      expect(
        storage.transactions.where((t) => t.id == 'live-$id-0'),
        hasLength(1),
      );
    });

    test(
      'domaćin završi live usred licitacije — ništa se ne prodaje',
      () async {
        final id = await start();
        await live.bid(bob, id, 4, now: at(5));
        await expectLater(
          live.end(bob, id, now: at(10)),
          throwsA(isA<TradeException>()),
        );
        await live.end(host, id, now: at(10));
        final s = state(id, 60);
        expect(s.isOver, isTrue);
        expect(s.lots.every((l) => l.status == LotStatus.skipped), isTrue);
        expect(await live.settleDue(now: at(60)), 0);
        expect(storage.deviceById(items[0].id)!.ownerId, host);
      },
    );

    test('predmeti u liveu su zaključani dok se ne licitiraju', () async {
      final show = await live.create(
        hostId: host,
        title: 'Sada',
        items: [for (final d in items) (d.id, 1.0)],
      );
      expect(LiveService.isLocked(storage, items[0].id), isTrue);
      await expectLater(
        trade.list(userId: host, deviceId: items[0].id, price: 50),
        throwsA(isA<TradeException>()),
      );
      await expectLater(
        trade.deleteOwn(userId: host, deviceId: items[1].id),
        throwsA(isA<TradeException>()),
      );
      // Raspored se ne mijenja ni kad se predmet kasnije makne.
      final before = live.stateOf(show, now: DateTime.now());
      await live.end(host, show.id);
      expect(LiveService.isLocked(storage, items[0].id), isFalse);
      await trade.list(userId: host, deviceId: items[0].id, price: 50);
      expect(storage.deviceById(items[0].id)!.isListed, isTrue);
      expect(before.lots.first.start, show.startsAt);
    });

    test(
      'raspored ne ovisi o tome tko gleda (blokirani samo u chatu)',
      () async {
        final id = await start();
        await live.bid(bob, id, 1, now: at(5));
        await live.chat(bob, id, 'Moje!', now: at(6));
        final show = storage.liveShowById(id)!;
        final hidden = LiveService.compute(
          show,
          storage.liveEventsOf(id),
          at(7),
          hiddenUsers: {bob},
        );
        expect(hidden.current!.leader!.userId, bob);
        expect(hidden.feed.map((e) => e.type.name), ['bid']);
        expect(state(id, 7).feed, hasLength(2));
      },
    );

    test(
      'video: oznaka se sprema, gledatelj traži video od domaćina',
      () async {
        final show = await live.create(
          hostId: host,
          title: 'Video live',
          items: [(items.first.id, 1.0)],
          video: true,
          now: t0,
          startsAt: t0,
        );
        expect(LiveShow.fromMap(show.toMap()).video, isTrue);
        expect(
          LiveShow.fromMap({...show.toMap()}..remove('video')).video,
          isFalse,
        );

        final hub = FakeHub();
        final viewer = LiveWatcher(hub.channel(show.id));
        await viewer.start();
        expect(hub.sent.single['type'], 'hello');
        expect(viewer.status.value, LiveVideoStatus.connecting);
        // Domaćin je (ponovno) spreman → gledatelj se javlja.
        hub.deliver({'type': 'ready', 'from': 'h', 'role': 'host'});
        await pumpEventQueue();
        expect(hub.sent.where((m) => m['type'] == 'hello'), hasLength(2));
        // Domaćin je ugasio kameru / izašao.
        hub.deliver({'type': 'bye', 'from': 'h', 'role': 'host'});
        await pumpEventQueue();
        expect(viewer.status.value, LiveVideoStatus.offline);
        // Odlazak gledatelja javlja domaćinu.
        await viewer.stop();
        expect(hub.sent.last['type'], 'bye');
        expect(hub.sent.last['role'], 'viewer');
      },
    );

    test('gledatelji i chat', () async {
      final id = await start();
      await live.join(bob, id, now: at(1));
      await live.join(bob, id, now: at(2)); // ne ponavlja se
      await live.join(ana, id, now: at(3));
      await live.join(host, id, now: at(3));
      await live.chat(ana, id, 'Bok svima!', now: at(4));
      final s = state(id, 5);
      expect(s.viewers, 2);
      expect(s.feed.map((e) => e.text), ['Bok svima!']);
      expect(storage.liveEventsOf(id), hasLength(4));
      await expectLater(
        live.chat(ana, id, 'x' * 141, now: at(5)),
        throwsA(isA<TradeException>()),
      );
    });
  });

  for (final size in const [Size(1400, 1000), Size(400, 860)]) {
    testWidgets('live: pokretanje, licitiranje i chat ($size)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final storage = StorageService();
      final hub = FakeHub();
      late String bobShow;
      late List<Device> mine;
      await tester.runAsync(() async {
        await storage.init(inMemory: true);
        final trade = TradeService(storage);
        final theirs = await addItem(trade, bob, 'Gramofon');
        mine = [
          await addItem(trade, host, 'Game Boy'),
          await addItem(trade, host, 'Walkman'),
        ];
        bobShow = (await LiveService(storage).create(
          hostId: bob,
          title: 'Vinili i gramofoni',
          items: [(theirs.id, 1)],
          lotSeconds: 60,
          video: true,
        )).id;
      });
      addTearDown(() => tester.runAsync(Hive.close));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            tickIntervalProvider.overrideWithValue(null),
            liveSignalingProvider.overrideWithValue(hub.channel),
          ],
          child: const LoopApp(),
        ),
      );
      await tester.ensureVisible(find.text('Prijavi se'));
      await tester.tap(find.text('Prijavi se'));
      await tester.pumpAndSettle();

      // Aukcije: kategorije kao kartice i mreža kartica (live prvi).
      await tester.tap(find.text('Aukcije').last);
      await tester.pumpAndSettle();
      final card = find.byKey(ValueKey('browse-live-$bobShow'));
      expect(card, findsOneWidget);
      expect(
        find.byKey(const ValueKey('browse-auction-seed-auction-4')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('auction-cat-live')));
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(
        find.byKey(const ValueKey('browse-auction-seed-auction-4')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('auction-cat-all')));
      await tester.pumpAndSettle();

      // Dodir na live → swipe feed, prva stranica je soba uživo.
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('swipe-feed')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-lot')), findsOneWidget);
      expect(find.text('Vinili i gramofoni'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-end')), findsNothing);
      // Video: gledatelj se javlja domaćinu i čeka sliku s kamere.
      expect(hub.sent.first['type'], 'hello');
      expect(find.text('📹 Spajam video…'), findsOneWidget);

      // Licitiraj 1 € → vodiš.
      await tester.tap(find.byKey(const ValueKey('live-bid')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-leading')), findsOneWidget);
      expect(find.text('🥇 Ti vodiš'), findsOneWidget);

      // Chat i brza reakcija.
      await tester.enterText(
        find.byKey(const ValueKey('live-chat')),
        'Koliko je star?',
      );
      await tester.tap(find.byKey(const ValueKey('live-send')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('live-feed')),
          matching: find.textContaining('Koliko je star?', findRichText: true),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('live-react-0')));
      await tester.pumpAndSettle();
      expect(
        storage
            .liveEventsOf(bobShow)
            .where((e) => e.userId == host)
            .map((e) => e.text),
        containsAll(['Koliko je star?', '🔥']),
      );

      // Red predmeta.
      await tester.tap(find.byKey(const ValueKey('live-queue')));
      await tester.pumpAndSettle();
      expect(find.text('Predmeti u liveu'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Povuci gore → sljedeća kartica (aukcija) u istom feedu.
      await tester.fling(
        find.byKey(const ValueKey('swipe-feed')),
        const Offset(0, -500),
        1500,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-lot')), findsNothing);
      expect(find.byKey(const ValueKey('post-bid')), findsOneWidget);
      await tester.tap(find.byTooltip('Natrag'));
      await tester.pumpAndSettle();

      // Vlastiti live preko "+ Objavi → Live aukcija".
      await tester.tap(find.byKey(const ValueKey('nav-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-live')));
      await tester.pumpAndSettle();
      expect(find.text('Novi live'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('live-title')),
        'Retro večer',
      );
      for (final d in mine) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('live-item-${d.id}')),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(ValueKey('live-item-${d.id}')));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byKey(ValueKey('live-price-${mine.last.id}')),
        '5',
      );
      await tester.tap(find.byKey(const ValueKey('live-secs-45')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('live-go')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('live-go')));
      await tester.pumpAndSettle();

      final show = storage.liveShows.firstWhere((s) => s.hostId == host);
      expect(show.title, 'Retro večer');
      expect(show.lotSeconds, 45);
      expect(show.lots.map((l) => l.deviceId), [for (final d in mine) d.id]);
      expect(show.lots.last.startPrice, 5);
      expect(show.video, isTrue);
      expect(find.byKey(const ValueKey('live-lot')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-bid')), findsNothing);
      // Domaćin šalje video: oznaka gledatelja videa i gumbi za kameru.
      expect(find.text('📡 Video gleda 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-cam-flip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live-mic')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mic_off), findsOneWidget);

      // Domaćin završava live.
      await tester.tap(find.byKey(const ValueKey('live-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-end-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-over')), findsOneWidget);
      expect(storage.liveShowById(show.id)!.endedAt, isNotNull);
    });
  }
}
