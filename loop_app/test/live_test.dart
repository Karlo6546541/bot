import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/models/app_notification.dart';
import 'package:loop_app/models/app_user.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/models/live_show.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/live_video.dart';
import 'package:loop_app/widgets/live_video_view.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoViewObjectFit;
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

    /// Live s tri predmeta; domaćin odmah pokreće prvi (t0 … t0+30 s).
    Future<String> start({int secs = 30}) async {
      final show = await live.create(
        hostId: host,
        title: 'Retro igre od 1 €',
        items: [for (final d in items) (d.id, 1.0)],
        lotSeconds: secs,
        startsAt: t0,
        now: t0,
      );
      await live.startLot(host, show.id, index: 0, now: t0);
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
      // Predmeti su neobavezni — dodaju se tijekom livea.
      final empty = await live.create(hostId: host, title: 'Prazno', now: t0);
      expect(empty.lots, isEmpty);
    });

    test(
      'domaćin pokreće predmete; live traje dok se domaćin javlja',
      () async {
        final show = await live.create(
          hostId: host,
          title: 'Uživo',
          items: [for (final d in items) (d.id, 1.0)],
          startsAt: t0,
          now: t0,
        );
        final id = show.id;
        var st = state(id, 1);
        expect(st.isLive, isTrue);
        expect(st.current, isNull);
        expect(st.queue, hasLength(3));
        expect(st.canStart, isTrue);
        // Ništa se ne licitira dok domaćin ne pokrene predmet.
        await expectLater(
          live.bid(bob, id, 1, now: at(2)),
          throwsA(isA<TradeException>()),
        );
        await expectLater(
          live.startLot(bob, id, now: at(3)),
          throwsA(isA<TradeException>()),
        );
        // Domaćin bira bilo koji predmet.
        await live.startLot(host, id, index: 1, now: at(3));
        expect(state(id, 4).current!.index, 1);
        await expectLater(
          live.startLot(host, id, now: at(4)),
          throwsA(isA<TradeException>()),
        );
        await live.bid(bob, id, 1, now: at(5));
        expect(state(id, 40).lots[1].status, LotStatus.sold);
        // Bez indeksa: prvi na čekanju.
        await live.startLot(host, id, now: at(41));
        expect(state(id, 42).current!.index, 0);
        expect(state(id, 80).lots[0].status, LotStatus.unsold);
        // Novi predmet usred livea ide na kraj reda.
        final extra = await addItem(trade, host, 'Diskman');
        await live.addLot(host, id, extra.id, 2, now: at(90));
        expect(state(id, 91).queue.map((l) => l.lot.deviceId), [
          items[2].id,
          extra.id,
        ]);
        // Domaćin se javlja → live traje; bez javljanja 2 min → gotov.
        await live.heartbeat(host, id, now: at(150));
        expect(state(id, 260).isLive, isTrue);
        final over = state(id, 280);
        expect(over.isOver, isTrue);
        expect(over.queue, isEmpty);
        expect(over.lots[2].status, LotStatus.skipped);
        expect(
          LiveService.isLocked(storage, items[2].id, now: at(280)),
          isFalse,
        );
        await expectLater(
          live.addLot(host, id, items[2].id, 1, now: at(280)),
          throwsA(isA<TradeException>()),
        );
        expect(await live.settleDue(userId: bob, now: at(280)), 1);
        expect(storage.deviceById(items[1].id)!.ownerId, bob);
      },
    );

    test('zakazani live čeka domaćina, a bez njega nestaje', () async {
      final show = await live.create(
        hostId: host,
        title: 'Večeras',
        items: [(items.first.id, 1.0)],
        startsAt: t0.add(const Duration(hours: 1)),
        now: t0,
      );
      expect(state(show.id, 60).isScheduled, isTrue);
      expect(state(show.id, 60).canStart, isFalse);
      // Domaćin dođe ranije i krene uživo.
      await live.heartbeat(host, show.id, now: at(1800));
      expect(state(show.id, 1801).isLive, isTrue);
      await live.end(host, show.id, now: at(1900));
      expect(state(show.id, 1901).isOver, isTrue);

      // Drugi zakazani live na koji domaćin ne dođe.
      final noShow = await live.create(
        hostId: host,
        title: 'Sutra',
        startsAt: t0.add(const Duration(hours: 3)),
        now: at(2000),
      );
      expect(state(noShow.id, 3 * 3600).isScheduled, isTrue);
      expect(state(noShow.id, 4 * 3600 + 1).isOver, isTrue);
    });

    test(
      'ponude: minimum, vodeći samo povisuje maksimum, domaćin ne licitira',
      () async {
        final id = await start();
        await live.bid(bob, id, 1, now: at(5));
        // Vodeći ne može ponuditi isto ili manje od svog maksimuma …
        await expectLater(
          live.bid(bob, id, 1, now: at(6)),
          throwsA(isA<TradeException>()),
        );
        await expectLater(
          live.bid(host, id, 5, now: at(6)),
          throwsA(isA<TradeException>()),
        );
        final lot = state(id, 6).current!;
        expect(lot.leader!.userId, bob);
        expect(lot.minNext, 2);
        await expectLater(
          live.bid(ana, id, 1, now: at(7)),
          throwsA(isA<TradeException>()),
        );
        final next = await live.bid(ana, id, lot.minNext, now: at(7));
        expect(next.current!.leader!.userId, ana);
        expect(next.current!.bids, hasLength(2));
        // … ali može povisiti maksimum — cijena se ne mijenja.
        await live.bid(ana, id, 20, now: at(8));
        expect(state(id, 8).current!.price, 2);
        expect(state(id, 8).current!.maxOf(ana), 20);
      },
    );

    test('vlastiti iznos: cijena odmah skače na ponudu', () async {
      final id = await start();
      // Bob upiše 30 € → cijena je odmah 30 € (ne ostaje na početnoj).
      await live.bid(bob, id, 30, now: at(2));
      var lot = state(id, 2).current!;
      expect(lot.price, 30);
      expect(lot.leader!.userId, bob);
      // Gumb "Licitiraj" nudi 1 € više (31 €).
      expect(lot.minNext, 31);
      await live.bid(ana, id, lot.minNext, now: at(3));
      lot = state(id, 3).current!;
      expect(lot.leader!.userId, ana);
      expect(lot.price, 31);
      // Marko skoči na 50 € — vidljivo u chatu kao 50 €.
      await live.bid(marko, id, 50, now: at(4));
      lot = state(id, 4).current!;
      expect(lot.leader!.userId, marko);
      expect(lot.price, 50);
      expect(
        state(id, 4).feed.where((e) => e.type == LiveEventType.bid).last.amount,
        50,
      );
      // Niža ponuda od sljedećeg koraka se odbija.
      expect(() => live.bid(bob, id, 50, now: at(5)), throwsA(anything));
    });

    test('korak licitiranja je uvijek 1 €', () {
      for (final p in [1.0, 9.0, 10.0, 60.0, 120.0, 300.0, 1500.0]) {
        expect(LiveLot.increment(p), 1);
      }
    });

    test('predlicitacija na predmet koji tek dolazi', () async {
      final id = await start();
      // Predmet 2 (Walkman) još čeka — Ana predlicitira do 15 €.
      await live.bid(ana, id, 15, lot: 1, now: at(3));
      await live.bid(bob, id, 6, lot: 1, now: at(4));
      final queued = state(id, 5).lots[1];
      expect(queued.status, LotStatus.upcoming);
      expect(queued.leader!.userId, ana);
      expect(queued.price, 7); // 6 + korak 1
      // Domaćin pokreće predmet: predlicitacije vrijede, sat ne produljuju.
      await live.startLot(host, id, index: 1, now: at(40));
      final running = state(id, 41).lots[1];
      expect(running.leader!.userId, ana);
      expect(running.price, 7);
      expect(running.end, at(70));
      // Za završen predmet se više ne može predlicitirati.
      await expectLater(
        live.bid(bob, id, 30, lot: 0, now: at(41)),
        throwsA(isA<TradeException>()),
      );
    });

    test('kartica i adresa su obavezne prije prve ponude', () async {
      final id = await start();
      final fan = storage.userById(bob)!;
      await storage.putUser(
        AppUser.fromMap({...fan.toMap(), 'paymentCard': null}),
      );
      await expectLater(
        live.bid(bob, id, 1, now: at(2)),
        throwsA(isA<TradeException>()),
      );
      await storage.putUser(fan);
      await live.bid(bob, id, 1, now: at(3));
    });

    test('svaka ponuda dodaje 2 s na sat', () async {
      final id = await start();
      await live.bid(bob, id, 2, now: at(25));
      final lot = state(id, 26).current!;
      expect(lot.end, at(32));
      await live.bid(ana, id, 3, now: at(31));
      expect(state(id, 31).current!.end, at(34));
      expect(state(id, 33).current!.index, 0);
      expect(state(id, 37).lots[0].status, LotStatus.sold);
      // Sljedeći kreće kad ga domaćin pokrene.
      expect(state(id, 37).lots[1].status, LotStatus.upcoming);
      await live.startLot(host, id, now: at(37));
      expect(state(id, 38).lots[1].start, at(37));
    });

    test('prodaju provodi pobjednik ili domaćin — samo jednom', () async {
      final id = await start();
      await live.bid(bob, id, 3, now: at(5)); // Bob vodi s 3 €
      final hostCredits = storage.userById(host)!.credits;
      final bobCredits = storage.userById(bob)!.credits;

      // Netko treći ne provodi tuđu prodaju.
      expect(await live.settleDue(userId: marko, now: at(40)), 0);
      expect(await live.settleDue(userId: bob, now: at(40)), 1);
      expect(storage.deviceById(items[0].id)!.ownerId, bob);
      // Provizija: 10 % od razlike iznad početnog 1 € → 0,20 €.
      expect(storage.userById(host)!.credits, hostCredits + 2.8);
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
      'kupac bira dostavu; sve iz istog livea ide u jednom paketu',
      () async {
        final id = await start();
        await live.bid(bob, id, 3, now: at(5));
        await live.startLot(host, id, index: 1, now: at(40));
        await live.bid(bob, id, 2, now: at(45));
        await live.settleDue(userId: bob, now: at(80));
        final first = storage.deliveryById('live-$id-0')!;
        final second = storage.deliveryById('live-$id-1')!;
        // Ništa ne kreće samo — kupac bira način dostave.
        expect(first.awaitingChoice, isTrue);
        expect(second.awaitingChoice, isTrue);
        expect(DeliveryService.liveParcel(first.id), 'live-$id');
        await DeliveryService(storage).choose(
          userId: bob,
          deliveryId: first.id,
          method: DeliveryMethod.courier,
          destination: 'Ilica 1, 10000 Zagreb',
          now: at(90),
        );
        final a = storage.deliveryById(first.id)!;
        final b = storage.deliveryById(second.id)!;
        expect(a.method, DeliveryMethod.courier);
        expect(b.method, DeliveryMethod.courier);
        // Dostava se plaća jednom za cijeli paket.
        expect(a.cost + b.cost, DeliveryMethod.courier.cost);
      },
    );

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
      expect(
        live.stateOf(show, now: DateTime.now()).lots.first.status,
        LotStatus.upcoming,
      );
      // Kraj livea oslobađa predmete na čekanju.
      await live.end(host, show.id);
      expect(LiveService.isLocked(storage, items[0].id), isFalse);
      await trade.list(userId: host, deviceId: items[0].id, price: 50);
      expect(storage.deviceById(items[0].id)!.isListed, isTrue);
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

    /// Prazan live u kojem domaćin dodaje jedan predmet zadane vrste.
    Future<String> special(LotMode mode, {double price = 20}) async {
      final show = await live.create(
        hostId: host,
        title: 'Posebno',
        startsAt: t0,
        now: t0,
      );
      await live.addLot(
        host,
        show.id,
        items[0].id,
        price,
        mode: mode,
        floorPrice: 2,
        now: at(1),
      );
      await live.startLot(host, show.id, now: at(2));
      return show.id;
    }

    test('pada cijena: prvi koji uzme kupuje po trenutnoj cijeni', () async {
      final id = await special(LotMode.dutch);
      // Najniža cijena mora biti ispod početne.
      await expectLater(
        live.addLot(
          host,
          id,
          items[1].id,
          5,
          mode: LotMode.dutch,
          floorPrice: 5,
          now: at(2),
        ),
        throwsA(isA<TradeException>()),
      );
      expect(state(id, 2).current!.dutchPriceAt(at(2), 30), 20);
      // Na pola vremena: 20 − 18 · ½ = 11 €.
      expect(state(id, 17).current!.dutchPriceAt(at(17), 30), 11);
      await expectLater(
        live.bid(bob, id, 12, now: at(16)),
        throwsA(isA<TradeException>()),
      );
      expect(await live.take(bob, id, now: at(17)), isTrue);
      // Netko je bio brži — predmet je već prodan.
      await expectLater(
        live.take(ana, id, now: at(18)),
        throwsA(isA<TradeException>()),
      );
      final lot = state(id, 18).lots[0];
      expect(lot.status, LotStatus.sold);
      expect(lot.leader!.userId, bob);
      expect(lot.price, 11);
      expect(await live.settleDue(userId: bob, now: at(18)), 1);
      expect(storage.deviceById(items[0].id)!.ownerId, bob);
      // Na kraju vremena cijena staje na najnižoj.
      expect(lot.lot.dutchPrice(const Duration(seconds: 99), 30), 2);
    });

    test('nagradna igra: prijave, izvlačenje i obavijest dobitniku', () async {
      final id = await special(LotMode.giveaway);
      expect(state(id, 3).current!.price, 0);
      await live.enterGiveaway(bob, id, now: at(5));
      await live.enterGiveaway(ana, id, now: at(6));
      await live.enterGiveaway(bob, id, now: at(7));
      await expectLater(
        live.enterGiveaway(host, id, now: at(8)),
        throwsA(isA<TradeException>()),
      );
      expect(live.hasEntered(bob, id, 0), isTrue);
      final running = state(id, 10).current!;
      expect(running.entrants, 2);
      // Dobitnik se ne zna dok traje.
      expect(running.leader, isNull);

      final done = state(id, 40).lots[0];
      expect(done.status, LotStatus.sold);
      final winner = done.leader!.userId;
      expect([bob, ana], contains(winner));
      // Isti dobitnik na svakom uređaju.
      expect(state(id, 50).lots[0].leader!.userId, winner);
      expect(done.price, 0);

      expect(await live.settleDue(userId: host, now: at(40)), 1);
      expect(storage.deviceById(items[0].id)!.ownerId, winner);
      expect(
        storage.notifications.any(
          (n) => n.userId == winner && n.kind == NotificationKind.giveawayWon,
        ),
        isTrue,
      );
    });

    test('podsjeti me: obavijest kad zakazani live krene', () async {
      final show = await live.create(
        hostId: host,
        title: 'Večeras',
        startsAt: t0.add(const Duration(hours: 1)),
        now: t0,
      );
      await live.remind(bob, show.id, now: at(10));
      await live.remind(bob, show.id, now: at(11));
      expect(live.wantsReminder(bob, show.id), isTrue);
      expect(live.wantsReminder(ana, show.id), isFalse);
      bool reminded() => storage.notifications.any(
        (n) =>
            n.userId == bob &&
            n.kind == NotificationKind.liveStarted &&
            n.targetId == show.id,
      );
      expect(reminded(), isFalse);
      await live.heartbeat(host, show.id, now: at(3000));
      expect(
        storage.notifications.where(
          (n) => n.userId == bob && n.targetId == show.id,
        ),
        hasLength(1),
      );
      expect(reminded(), isTrue);
    });

    test('hype-metar raste s aktivnošću u sobi', () async {
      final id = await start();
      expect(state(id, 1).hype, 0);
      for (var i = 0; i < 5; i++) {
        await live.chat(i.isEven ? bob : ana, id, 'Super!', now: at(2 + i));
      }
      final calm = state(id, 8).hype;
      expect(calm, greaterThan(0));
      await live.bid(bob, id, 2, now: at(9));
      await live.bid(ana, id, 3, now: at(10));
      expect(state(id, 11).hype, greaterThan(calm));
      // Pola minute kasnije je opet mirno.
      await live.startLot(host, id, now: at(80));
      expect(state(id, 81).hype, 0);
    });

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
        await LiveService(storage).startLot(bob, bobShow);
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

      // Početna: pilula "Uživo" pokazuje samo liveove.
      await tester.tap(find.byKey(const ValueKey('home-cat-live')));
      await tester.pumpAndSettle();
      final card = find.byKey(ValueKey('browse-live-$bobShow'));
      expect(card, findsOneWidget);

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
      expect(find.textContaining('🥇 Ti vodiš'), findsOneWidget);

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
      // Srce: šalje se kao reakcija i leti uz desni rub (ne ide u chat).
      await tester.tap(find.byKey(const ValueKey('live-react-0')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('❤️'), findsWidgets);
      await tester.pumpAndSettle();
      // Srce postaje crveno tek nakon lajka.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('live-react-0')),
          matching: find.byIcon(Icons.favorite),
        ),
        findsOneWidget,
      );
      // Ponovni dodir na crveno srce poništava lajk (opet prozirno).
      await tester.tap(find.byKey(const ValueKey('live-react-0')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('live-react-0')),
          matching: find.byIcon(Icons.favorite_border),
        ),
        findsOneWidget,
      );
      // Brza reakcija: više emojija leti, a ostalima ide jedna poruka.
      await tester.tap(find.byKey(const ValueKey('live-reaction-🔥')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('🔥'), findsAtLeastNWidgets(3));
      await tester.pumpAndSettle();
      expect(
        storage
            .liveEventsOf(bobShow)
            .where((e) => e.userId == host && e.text == '🔥'),
        hasLength(1),
      );
      // Zvuk se utišava i to se pamti.
      await tester.tap(find.byKey(const ValueKey('live-sound')));
      await tester.pump();
      expect(storage.liveMuted, isTrue);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live-sound')));
      await tester.pump();
      expect(storage.liveMuted, isFalse);
      // Dodir bilo gdje po pozadini pušta srca.
      await tester.tap(find.byKey(const ValueKey('live-stage-tap')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('❤️'), findsWidgets);
      await tester.pumpAndSettle();
      expect(
        storage
            .liveEventsOf(bobShow)
            .where((e) => e.userId == host)
            .map((e) => e.text),
        containsAll(['Koliko je star?', '❤️']),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('live-feed')),
          matching: find.text('❤️'),
        ),
        findsNothing,
      );

      // Red predmeta.
      await tester.tap(find.byKey(const ValueKey('live-queue')));
      await tester.pumpAndSettle();
      expect(find.text('Predmeti u liveu'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Povuci gore (po videu, ne po chatu) → sljedeća kartica u feedu.
      await tester.flingFrom(
        Offset(
          tester.getCenter(find.byKey(const ValueKey('swipe-feed'))).dx,
          220,
        ),
        const Offset(0, -500),
        1500,
      );
      await tester.pumpAndSettle();
      // Feed liveova: iza zadnjeg je kraj popisa.
      expect(find.byKey(const ValueKey('live-lot')), findsNothing);
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
      // Zatvori tipkovnicu (fokusirano polje inače vraća pomak na sebe).
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      // Popis na ekranu "Novi live" (ispod je još swipe feed).
      final form = find
          .descendant(
            of: find.byType(Scaffold).last,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('live-secs-45')),
        200,
        scrollable: form,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-secs-45')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('live-go')),
        200,
        scrollable: form,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-go')));
      await tester.pumpAndSettle();

      final show = storage.liveShows.firstWhere((s) => s.hostId == host);
      expect(show.title, 'Retro večer');
      expect(show.lotSeconds, 45);
      expect(show.lots.map((l) => l.deviceId), [for (final d in mine) d.id]);
      expect(show.lots.last.startPrice, 5);
      expect(show.video, isTrue);
      // Domaćin sam pokreće licitaciju.
      expect(find.byKey(const ValueKey('live-lot')), findsNothing);
      expect(find.byKey(const ValueKey('live-host-idle')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live-start-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-lot')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-bid')), findsNothing);
      expect(storage.liveShowById(show.id)!.lots.first.startedAt, isNotNull);
      // Novi predmet usred livea.
      await tester.tap(find.byKey(const ValueKey('live-host-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-add-item')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RadioListTile<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-add-confirm')));
      await tester.pumpAndSettle();
      expect(storage.liveShowById(show.id)!.lots, hasLength(3));
      // ⚡ Brzo dodaj: samo naziv i cijena, predmet ide u Moje predmete.
      await tester.tap(find.byKey(const ValueKey('live-quick-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick-name')),
        'Pokemon Charizard',
      );
      await tester.enterText(find.byKey(const ValueKey('quick-price')), '7');
      await tester.tap(find.byKey(const ValueKey('quick-add-confirm')));
      await tester.pumpAndSettle();
      final lots = storage.liveShowById(show.id)!.lots;
      expect(lots, hasLength(4));
      expect(lots.last.deviceName, 'Pokemon Charizard');
      expect(lots.last.startPrice, 7);
      expect(
        storage.deviceById(lots.last.deviceId)!.category,
        DeviceCategory.tcg,
      );
      // Domaćin šalje video: oznaka gledatelja videa i gumbi za kameru.
      expect(find.text('📡 Video gleda 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-cam-flip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live-mic')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mic_off), findsOneWidget);

      // Domaćin završava live (u izborniku ⋮).
      await tester.tap(find.byKey(const ValueKey('live-host-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-end-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-over')), findsOneWidget);
      expect(storage.liveShowById(show.id)!.endedAt, isNotNull);
    });
  }

  testWidgets('mali prozor s liveom nakon izlaska iz sobe', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = StorageService();
    late String id;
    await tester.runAsync(() async {
      await storage.init(inMemory: true);
      final trade = TradeService(storage);
      final live = LiveService(storage);
      final d = await addItem(trade, bob, 'Gramofon');
      id = (await live.create(hostId: bob, title: 'Petak navečer')).id;
      await live.addLot(bob, id, d.id, 40);
      await live.startLot(bob, id);
    });
    addTearDown(() => tester.runAsync(Hive.close));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
        ],
        child: const LoopApp(),
      ),
    );
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-cat-live')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('browse-live-$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mini-live')), findsNothing);

    // Izlazak iz sobe → mali prozor; aplikacija se koristi dalje.
    await tester.tap(find.byKey(const ValueKey('live-close')).first);
    await tester.pumpAndSettle();
    final mini = find.byKey(const ValueKey('mini-live'));
    expect(mini, findsOneWidget);
    expect(find.byKey(const ValueKey('home-search')), findsOneWidget);

    // Povlači se po ekranu (lijepi se uz bliži rub).
    final before = tester.getTopLeft(mini);
    await tester.drag(mini, const Offset(-300, -250));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(mini);
    expect(after.dx, lessThan(before.dx));
    expect(after.dy, lessThan(before.dy));

    // Dodir vraća u sobu (prozor nestaje), izlazak ga vraća.
    await tester.tap(mini);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-lot')), findsOneWidget);
    expect(find.byKey(const ValueKey('mini-live')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('live-close')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mini-live')), findsOneWidget);

    // ✕ ga gasi.
    await tester.tap(find.byKey(const ValueKey('mini-live-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mini-live')), findsNothing);
  });

  testWidgets('početna i posebni predmeti: pada cijena, nagradna igra', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final storage = StorageService();
    late String id;
    late List<Device> theirs;
    late LiveService live;
    await tester.runAsync(() async {
      await storage.init(inMemory: true);
      final trade = TradeService(storage);
      live = LiveService(storage);
      theirs = [
        await addItem(trade, bob, 'Gramofon'),
        await addItem(trade, bob, 'Kazetofon'),
      ];
      id = (await live.create(hostId: bob, title: 'Petak navečer')).id;
      await live.addLot(
        bob,
        id,
        theirs[0].id,
        40,
        mode: LotMode.dutch,
        floorPrice: 5,
      );
      await live.startLot(bob, id);
    });
    addTearDown(() => tester.runAsync(Hive.close));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
        ],
        child: const LoopApp(),
      ),
    );
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();

    // Početna: pilule, a "Za tebe" je feed (live ima svoju traku, pa
    // pretraga preko objave tada nije prikazana).
    expect(find.byKey(const ValueKey('home-cat-for-you')), findsOneWidget);
    // "Za tebe" (TikTok): live uživo je prva objava feeda.
    expect(find.byKey(ValueKey('feed-live-$id')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-go-live')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-cat-live')));
    await tester.pumpAndSettle();
    final card = find.byKey(ValueKey('browse-live-$id'));
    expect(card, findsOneWidget);

    // Pada cijena: "Uzmi" kupuje odmah.
    await tester.tap(card);
    await tester.pumpAndSettle();
    // Mirna soba: bez mjerača atmosfere (pojavi se tek kad se licitira).
    expect(find.byKey(const ValueKey('live-hype')), findsNothing);
    expect(find.byKey(const ValueKey('live-value')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-bid')), findsNothing);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('live-take'))),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('🏆 Osvojio si!'), findsOneWidget);

    // Osvojeno → u sobi gumb za odabir dostave (ništa ne kreće samo).
    final app = ProviderScope.containerOf(
      tester.element(find.byType(LoopApp)),
    ).read(appProvider.notifier);
    await tester.runAsync(app.settleLive);
    await tester.pumpAndSettle();
    final choose = find.byKey(const ValueKey('live-choose-delivery'));
    expect(choose, findsOneWidget);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delivery-courier')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Potvrdi · 6 €'));
    await tester.runAsync(() => tester.tap(find.text('Potvrdi · 6 €')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 900)),
    );
    await tester.pumpAndSettle();
    expect(choose, findsNothing);
    // Poruka "Dostava je krenula" nestane sama.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      storage.deliveries
          .where((d) => d.buyerId == host && d.method != null)
          .length,
      1,
    );

    // Domaćin pokreće nagradnu igru — gledatelj se prijavljuje.
    await tester.runAsync(() async {
      await live.addLot(bob, id, theirs[1].id, 0, mode: LotMode.giveaway);
      await live.startLot(bob, id);
    });
    await tester.enterText(find.byKey(const ValueKey('live-chat')), 'Ja!');
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('live-send'))),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Besplatno'), findsWidgets);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('live-enter'))),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-entered')), findsOneWidget);
  });

  testWidgets(
    'samo kartica prije ponude (bez adrese), jedan gumb za ponudu, Kupi odmah',
    (tester) async {
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final storage = StorageService();
      late String id;
      await tester.runAsync(() async {
        await storage.init(inMemory: true);
        final trade = TradeService(storage);
        final live = LiveService(storage);
        final g = await addItem(trade, bob, 'Gramofon');
        id = (await live.create(hostId: bob, title: 'Vinili')).id;
        await live.addLot(bob, id, g.id, 5);
        await live.startLot(bob, id);
        // Demo korisnik (gledatelj) još nema karticu.
        final me = storage.userById(host)!;
        await storage.putUser(
          AppUser.fromMap({...me.toMap(), 'paymentCard': null}),
        );
      });
      addTearDown(() => tester.runAsync(Hive.close));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            tickIntervalProvider.overrideWithValue(null),
          ],
          child: const LoopApp(),
        ),
      );
      await tester.ensureVisible(find.text('Prijavi se'));
      await tester.tap(find.text('Prijavi se'));
      await tester.pumpAndSettle();

      // Početna: i predmeti za Kupi odmah (izbornik je bez listanja).
      await tester.ensureVisible(find.byKey(const ValueKey('home-cat-buy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-cat-buy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-buy')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('home-cat-live')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-cat-live')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('browse-live-$id')));
      await tester.pumpAndSettle();

      // Prva ponuda (jedan veliki gumb) → prvo način plaćanja.
      await tester.tap(find.byKey(const ValueKey('live-bid')));
      await tester.pumpAndSettle();
      // Live traži samo način plaćanja (bez adrese) — odmah se otvara
      // novčanik. Testna kartica: odbijena pa uspješna.
      Future<void> tapIn(String key) async {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pump();
      }

      await tapIn('pay-test-declined');
      await tapIn('pay-card-save');
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Banka je odbila karticu. Pokušaj drugu.'),
        findsOneWidget,
      );
      await tapIn('pay-test-fill');
      await tapIn('pay-card-save');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(storage.userById(host)!.paymentCard, 'Visa •••• 4242');
      // Ponuda je prošla: vodim s početnom cijenom (bez maksimalne ponude).
      expect(find.byKey(const ValueKey('live-leading')), findsOneWidget);
      final st = LiveService(storage).stateOf(storage.liveShowById(id)!);
      expect(st.current!.price, 5);
      expect(st.current!.leader!.userId, host);
      expect(find.byKey(const ValueKey('live-raise')), findsNothing);
      expect(find.byKey(const ValueKey('live-bid-custom')), findsNothing);
    },
  );

  group('kvaliteta videa', () {
    test('viši početni protok u opisu veze (VP8 bez fmtp, H264 s fmtp)', () {
      const sdp =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 102\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=rtpmap:102 H264/90000\r\n'
          'a=fmtp:102 profile-level-id=42e01f\r\n'
          'a=rtpmap:111 opus/48000/2\r\n';
      final out = boostVideoSdp(sdp, startKbps: 1500, maxKbps: 2500);
      expect(
        out,
        contains(
          'a=fmtp:96 x-google-start-bitrate=1500;x-google-max-bitrate=2500',
        ),
      );
      expect(
        out,
        contains(
          'a=fmtp:102 profile-level-id=42e01f;'
          'x-google-start-bitrate=1500;x-google-max-bitrate=2500',
        ),
      );
      expect(out, isNot(contains('fmtp:111')));
      expect(
        out.split('\r\n').where((l) => l.startsWith('a=fmtp:96')),
        hasLength(1),
      );
      // Bez video kodeka ništa se ne mijenja.
      expect(boostVideoSdp('v=0\r\n'), 'v=0\r\n');
    });

    test('H264 je prvi video kodek u ponudi', () {
      const sdp =
          'v=0\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97 102 103\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=rtpmap:102 H264/90000\r\n'
          'a=rtpmap:103 H264/90000\r\n';
      final out = preferH264(sdp);
      expect(out, contains('m=video 9 UDP/TLS/RTP/SAVPF 102 103 96 97\r\n'));
      expect(out, contains('m=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'));
      expect(
        preferH264('m=video 9 X 96\r\na=rtpmap:96 VP8/90000'),
        'm=video 9 X 96\r\na=rtpmap:96 VP8/90000',
      );
    });

    test('poruka se izvlači iz Supabase broadcast paketa', () {
      const msg = {'type': 'offer', 'from': 'a', 'to': 'b', 'sdp': 'x'};
      // Kako stiže preko WebSocketa: Supabase je dodao svoj type/event.
      expect(
        unwrapSignal({
          'type': 'broadcast',
          'event': 'signal',
          'payload': {'payload': msg, 'type': 'broadcast', 'event': 'signal'},
        }),
        msg,
      );
      expect(unwrapSignal({'payload': msg}), msg);
      expect(unwrapSignal(msg), msg);
      // Stari (pokvareni) oblik: type je prepisan — nije naša poruka.
      expect(
        unwrapSignal({'type': 'broadcast', 'event': 'signal', 'from': 'a'}),
        isNull,
      );
    });

    test('protok po gledatelju pada s brojem gledatelja', () {
      expect(videoBitrateFor(1), 2500000);
      expect(videoBitrateFor(4), 1800000);
      expect(videoBitrateFor(6), 1200000);
      expect(videoBitrateFor(20), 800000);
    });

    test('slika se ne zumira kad se omjer jako razlikuje', () {
      // Gotovo isti omjer → ispuni ekran.
      expect(
        videoFit(videoAspect: 9 / 16, viewAspect: 0.55),
        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
      // Cijeli senzor mobitela (3:4) na izduženom ekranu → cijela slika.
      expect(
        videoFit(videoAspect: 3 / 4, viewAspect: 9 / 19.5),
        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      );
      // Položena kamera (16:9) na uspravnom ekranu → cijela slika.
      expect(
        videoFit(videoAspect: 16 / 9, viewAspect: 400 / 800),
        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      );
      expect(videoFit(), RTCVideoViewObjectFit.RTCVideoViewObjectFitContain);
    });
  });
}
