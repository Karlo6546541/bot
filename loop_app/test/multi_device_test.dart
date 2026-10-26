import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/app_user.dart';
import 'package:loop_app/models/auction.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/models/seller_info.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/services/auction_service.dart';
import 'package:loop_app/services/boxnow/boxnow_demo.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/services/earnings.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/remote_store.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/sync_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// Zajednička online baza u memoriji: jedinstveni ID (kao primarni ključ
/// u Postgresu) — `claim` uspije samo prvom.
class SharedRemote implements RemoteStore {
  final data = <String, Map<String, Map<String, dynamic>>>{};

  @override
  bool canWrite = true;

  @override
  Future<bool> claim(String table, String id, Map<String, dynamic> d) async {
    final t = data[table] ??= {};
    if (t.containsKey(id)) return false;
    t[id] = jsonDecode(jsonEncode(d)) as Map<String, dynamic>;
    return true;
  }

  @override
  Future<Map<String, Map<String, Map<String, dynamic>>>> pullAll(
    List<String> tables,
  ) async => {
    for (final t in tables)
      t: {
        for (final e in (data[t] ?? {}).entries)
          e.key: jsonDecode(jsonEncode(e.value)) as Map<String, dynamic>,
      },
  };

  @override
  Future<void> upsert(String table, String id, Map<String, dynamic> d) async =>
      (data[table] ??= {})[id] =
          jsonDecode(jsonEncode(d)) as Map<String, dynamic>;

  @override
  Future<void> delete(String table, String id) async => data[table]?.remove(id);

  @override
  Future<void> clearAll(List<String> tables) async => data.clear();

  @override
  Stream<RemoteChange> changes(List<String> tables) => const Stream.empty();
}

/// Provjera ispravaka iz testa s više korisnika (točke 3–8). Svaki
/// "uređaj" radi sa zastarjelim podacima (nije vidio tuđu kupnju), a
/// istina je u zajedničkoj bazi.
void main() {
  late StorageService storage;
  late SharedRemote remote;
  late SyncService sync;

  const ana = SeedData.anaUserId;
  const demo = SeedData.demoUserId;
  const tester = SeedData.testUserId;
  const marko = SeedData.markoUserId;

  Map<String, Map<String, Map<String, dynamic>>> snapshot() => {
    for (final t in storage.exportAll().entries)
      t.key: {
        for (final r in t.value.entries)
          r.key: jsonDecode(jsonEncode(r.value)) as Map<String, dynamic>,
      },
  };

  /// Drugi uređaj: lokalni podaci kao u trenutku [stale] (tuđe promjene
  /// još nisu stigle), baza je stvarna.
  Future<void> device(
    Map<String, Map<String, Map<String, dynamic>>> stale,
  ) async {
    await sync.flushNow();
    await storage.replaceAllFromRemote(stale);
  }

  /// Svježi podaci iz baze (kao novo učitavanje stranice).
  Future<void> reload() async {
    await sync.flushNow();
    await storage.replaceAllFromRemote(
      await remote.pullAll(StorageService.syncedTables),
    );
  }

  double remoteCredits(String id) =>
      (remote.data['users']![id]!['credits'] as num).toDouble();

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    remote = SharedRemote();
    for (final t in storage.exportAll().entries) {
      remote.data[t.key] = {
        for (final r in t.value.entries) r.key: Map.of(r.value),
      };
    }
    sync = SyncService(storage, remote);
    await sync.start();
  });

  tearDown(() async {
    await sync.dispose();
    await Hive.close();
  });

  Future<Device> listed(String owner, double price, {int quantity = 1}) async {
    final d = await TradeService(storage).addDevice(
      userId: owner,
      name: 'Walkman',
      model: 'WM-${DateTime.now().microsecondsSinceEpoch}',
      condition: DeviceCondition.good,
      price: price,
      quantity: quantity,
      category: DeviceCategory.values.firstWhere(
        (c) => c.section != ItemSection.digital,
      ),
    );
    await sync.flushNow();
    return storage.deviceById(d.id)!;
  }

  test(
    '5: tri kupca istovremeno kupuju jedini komad — prolazi samo jedan',
    () async {
      final d = await listed(ana, 50);
      final before = snapshot();
      final anaBefore = remoteCredits(ana);
      final results = <String, Object>{};
      for (final buyer in [demo, tester, marko]) {
        await device(before);
        try {
          await TradeService(storage).buy(userId: buyer, deviceId: d.id);
          results[buyer] = 'ok';
        } on TradeException catch (e) {
          results[buyer] = e.message;
        }
      }
      await reload();
      expect(results.values.where((r) => r == 'ok'), hasLength(1));
      final sales = remote.data['transactions']!.values.where(
        (t) => t['type'] == 'sell' && t['deviceId'] == d.id,
      );
      expect(sales, hasLength(1));
      final winner = results.entries.firstWhere((e) => e.value == 'ok').key;
      expect(storage.deviceById(d.id)!.ownerId, winner);
      // Prodavač plaćen točno jednom (95 % od 50 €).
      expect(remoteCredits(ana), closeTo(anaBefore + 47.5, 0.001));
    },
  );

  test(
    '5: zaliha 2, dva kupca istovremeno — oba dobiju komad, treći ne',
    () async {
      final d = await listed(ana, 20, quantity: 2);
      final anaBefore = remoteCredits(ana);
      final stale = snapshot();
      final ok = <String>[];
      // Oba kupca vide "2 na zalihi" i kupuju u istoj sekundi.
      for (final b in [demo, tester]) {
        await device(stale);
        await TradeService(storage).buy(userId: b, deviceId: d.id);
        ok.add(b);
      }
      expect(ok, [demo, tester]);
      // Treći (također zastarjeli podaci) — rasprodano.
      await device(stale);
      await expectLater(
        TradeService(storage).buy(userId: marko, deviceId: d.id),
        throwsA(isA<TradeException>()),
      );
      await reload();
      final sales = remote.data['transactions']!.values.where(
        (t) => t['type'] == 'sell' && t['deviceId'] == d.id,
      );
      expect(sales, hasLength(2));
      // Istovremeni upisi profila prodavača: jedna zarada se prepisala…
      expect(remoteCredits(ana), lessThan(anaBefore + 2 * 19));
      // …a prodavačev uređaj je ponovno uračuna (i nikad dvaput).
      expect(await Earnings(storage).reconcile(ana), 1);
      expect(await Earnings(storage).reconcile(ana), 0);
      await sync.flushNow();
      expect(remoteCredits(ana), closeTo(anaBefore + 2 * 19, 0.001));
      // Komadi su kod kupaca, oglas ne ide u minus.
      expect(storage.deviceById(d.id)!.quantity, greaterThanOrEqualTo(0));
    },
  );

  test('5: bez veze s bazom kupnja se ne radi lokalno', () async {
    final d = await listed(ana, 50);
    remote.canWrite = true;
    await sync.dispose();
    // Baza postoji, ali veza je pala.
    final offline = SyncService(storage, _DownRemote(remote));
    await offline.start(timeout: const Duration(milliseconds: 50));
    await expectLater(
      TradeService(storage).buy(userId: demo, deviceId: d.id),
      throwsA(
        isA<TradeException>().having(
          (e) => e.message,
          'message',
          contains('Nema veze'),
        ),
      ),
    );
    expect(storage.deviceById(d.id)!.ownerId, ana);
    await offline.dispose();
    sync = SyncService(storage, remote);
    await sync.start();
  });

  test('zarada: stari račun se ne uračunava ponovno', () async {
    final before = storage.userById(ana)!;
    expect(before.creditedSales, isNull);
    // Prvo pokretanje samo označi postojeće prodaje.
    expect(await Earnings(storage).reconcile(ana), 0);
    expect(storage.userById(ana)!.credits, before.credits);
    expect(storage.userById(ana)!.creditedSales, isNotNull);
  });

  test(
    '6: dva uređaja istovremeno zaključuju aukciju — jedna prodaja i dostava',
    () async {
      final a = storage.auctionById('seed-auction-2')!;
      final sellerBefore = remoteCredits(a.sellerId);
      final stale = snapshot();
      final end = a.endsAt.add(const Duration(seconds: 1));
      for (var i = 0; i < 2; i++) {
        await device(stale);
        await AuctionService(storage).settleExpired(now: end);
      }
      await reload();
      final sales = remote.data['transactions']!.values.where(
        (t) => t['deviceId'] == a.deviceId && t['type'] == 'sell',
      );
      expect(sales, hasLength(1));
      expect(
        remote.data['deliveries']!.values.where(
          (x) => x['deviceId'] == a.deviceId,
        ),
        hasLength(1),
      );
      expect(storage.auctionById(a.id)!.status, AuctionStatus.sold);
      // Zarada prodavača = zbroj svih njegovih (jednom upisanih) prodaja
      // iz ovog zaključivanja — ništa dvaput.
      final all = remote.data['transactions']!.values.where(
        (t) =>
            t['type'] == 'sell' &&
            t['sellerId'] == a.sellerId &&
            (t['id'] as String).startsWith('auction-'),
      );
      final ids = all.map((t) => t['id']).toList();
      expect(ids.toSet().length, ids.length);
      final payout = all.fold<double>(
        0,
        (s, t) => s + (t['amount'] as num).toDouble(),
      );
      expect(remoteCredits(a.sellerId), closeTo(sellerBefore + payout, 0.001));
    },
  );

  test(
    '6: live predmet — domaćin i pobjednik istovremeno, jedna prodaja',
    () async {
      final t0 = DateTime(2026, 10, 23, 20);
      final items = [await listed(demo, 100), await listed(demo, 100)];
      final live = LiveService(storage);
      final show = await live.create(
        hostId: demo,
        title: 'Test',
        items: [for (final d in items) (d.id, 1.0)],
        lotSeconds: 30,
        startsAt: t0,
        now: t0,
      );
      await live.startLot(demo, show.id, index: 0, now: t0);
      await live.bid(
        tester,
        show.id,
        3,
        now: t0.add(const Duration(seconds: 5)),
      );
      final hostBefore = storage.userById(demo)!.credits;
      await sync.flushNow();
      final stale = snapshot();
      final later = t0.add(const Duration(seconds: 60));
      for (final who in [tester, demo]) {
        await device(stale);
        await LiveService(storage).settleDue(userId: who, now: later);
      }
      await reload();
      final sales = remote.data['transactions']!.keys.where(
        (k) => k == 'live-${show.id}-0',
      );
      expect(sales, hasLength(1));
      expect(
        remote.data['deliveries']!.keys.where((k) => k == 'live-${show.id}-0'),
        hasLength(1),
      );
      expect(storage.deviceById(items[0].id)!.ownerId, tester);
      expect(storage.userById(demo)!.credits, closeTo(hostBefore + 2.8, 0.001));
    },
  );

  test('3: PIN nije izveden iz javnog broja pošiljke', () async {
    final d = await listed(ana, 30);
    final pins = <String>{};
    final parcels = <String>{};
    for (var i = 0; i < 20; i++) {
      final x = await DeliveryService(storage).createForPurchase(
        userId: demo,
        device: d,
        method: DeliveryMethod.parcelLocker,
        destination: kDemoLockers.first,
        sellerId: ana,
      );
      expect(x.dropOffPin, isNotNull);
      expect(BoxNowDemo.pickupPin(x), x.pickupPin);
      expect(BoxNowDemo.dropOffPin(x), x.dropOffPin);
      expect(x.pickupPin, isNot(x.dropOffPin));
      pins.add(x.pickupPin!);
      parcels.add(BoxNowDemo.parcelId(x));
      // Isti broj pošiljke s drugim PIN-om — PIN dolazi iz zapisa, ne iz broja.
      final copy = Delivery.fromMap({...x.toMap(), 'pickupPin': '000000'});
      expect(BoxNowDemo.parcelId(copy), BoxNowDemo.parcelId(x));
      expect(BoxNowDemo.pickupPin(copy), '000000');
    }
    // Nasumični PIN-ovi: praktički svi različiti.
    expect(pins.length, greaterThanOrEqualTo(18));
    expect(parcels.length, 20);
  });

  test(
    '4: otpremnica i Kupljeno pokazuju cijenu predmeta, ne 0 € dostave',
    () async {
      final d = await listed(ana, 80);
      final tx = await TradeService(storage).buy(userId: demo, deviceId: d.id);
      final delivery = await DeliveryService(storage).createForPurchase(
        userId: demo,
        device: storage.deviceById(tx.deviceId)!,
        method: DeliveryMethod.parcelLocker,
        destination: kDemoLockers.first,
        sellerId: ana,
      );
      // Plaćena dostava je zaseban zapis (cijena 0, iznos = dostava).
      final all = storage.transactions.where(
        (t) => t.deviceId == delivery.deviceId && t.buyerId == demo,
      );
      expect(all.any((t) => t.type == TransactionType.delivery), isTrue);
      final state = AppState.fromStorage(storage);
      expect(state.itemPaid(delivery.deviceId, demo), 80);
    },
  );

  test('8: oznaka trgovca je javna — vide je i drugi uređaji', () async {
    final u = storage.userById(tester)!;
    final info = SellerInfo(
      kind: SellerKind.business,
      companyName: 'Retro Kutak j.d.o.o.',
      legalName: 'Ivo Ivić',
      oib: '12345678903',
      address: 'Ilica 1, Zagreb',
      iban: 'HR2523400091111111111',
      contactEmail: 'info@retrokutak.hr',
      contactPhone: '+385 91 123 4567',
      updatedAt: DateTime(2026),
    );
    await storage.putUser(
      u.copyWith(seller: info, trader: TraderPublic.of(info)),
    );
    await sync.flushNow();
    final row = remote.data['users']![tester]!;
    // Privatni podaci (IBAN, datum rođenja) ne idu u javni profil.
    expect(row.containsKey('seller'), isFalse);
    expect(jsonEncode(row), isNot(contains('HR2523400091111111111')));
    // Drugi korisnik vidi samo javni profil — i dalje je trgovac.
    final seen = AppUser.fromMap(row);
    expect(seen.isTrader, isTrue);
    expect(seen.traderInfo!.name, 'Retro Kutak j.d.o.o.');
    // Ograničenja za trgovce vrijede i na tuđem uređaju.
    await storage.replaceAllFromRemote({
      'users': {...remote.data['users']!},
      'sellers': {},
    });
    expect(storage.userById(tester)!.seller, isNull);
    expect(
      AuctionService(storage).policy.maxActiveFor(tester),
      greaterThan(AuctionService(storage).policy.maxActiveFor(demo)),
    );
  });

  test(
    '7: više od 1000 redaka — čitanje po stranicama, ništa se ne gubi',
    () async {
      // Lokalni PostgREST: kao Supabase vraća najviše 1000 redaka po upitu.
      final rows = [
        for (var i = 0; i < 2345; i++)
          {
            'id': 'e${i.toString().padLeft(5, '0')}',
            'data': {'n': i},
          },
      ];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Uri>[];
      server.listen((r) {
        requests.add(r.uri);
        final q = r.uri.queryParameters;
        final offset = int.tryParse(q['offset'] ?? '') ?? 0;
        final limit = (int.tryParse(q['limit'] ?? '') ?? 1000).clamp(0, 1000);
        final page = rows.skip(offset).take(limit).toList();
        r.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(page));
        r.response.close();
      });
      final client = SupabaseClient(
        'http://${server.address.host}:${server.port}',
        'sb_publishable_test',
      );
      final store = SupabaseRemoteStore(client);
      final out = await store.pullAll(['live_events']);
      await server.close(force: true);
      expect(out['live_events'], hasLength(2345));
      expect(out['live_events']!['e02344'], {'n': 2344});
      expect(requests.length, 3);
    },
  );
}

/// Baza koja postoji, ali veza ne radi.
class _DownRemote extends SharedRemote {
  _DownRemote(this.real);
  final SharedRemote real;

  @override
  Future<Map<String, Map<String, Map<String, dynamic>>>> pullAll(
    List<String> tables,
  ) async => throw Exception('nema mreže');

  @override
  Future<bool> claim(String table, String id, Map<String, dynamic> d) async =>
      throw Exception('nema mreže');
}
