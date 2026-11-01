import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/services/remote_store.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/sync_service.dart';
import 'package:loop_app/services/trade_service.dart';

/// Online baza u memoriji (umjesto Supabasea).
class FakeRemote implements RemoteStore {
  final data = <String, Map<String, Map<String, dynamic>>>{};
  final _changes = StreamController<RemoteChange>.broadcast();
  bool failPull = false;

  @override
  Future<Map<String, dynamic>?> fetch(String table, String id) async =>
      data[table]?[id];

  @override
  Future<Map<String, Map<String, dynamic>>> pullSince(
    String table,
    DateTime since,
  ) async => const {};

  @override
  Future<bool> claim(String table, String id, Map<String, dynamic> d) async {
    final t = data[table] ??= {};
    if (t.containsKey(id)) return false;
    t[id] = d;
    return true;
  }

  int upserts = 0;

  @override
  bool canWrite = true;

  /// Zapisi koje baza odbija (npr. pogrešni podaci).
  final rejected = <String>{};

  @override
  Future<Map<String, Map<String, Map<String, dynamic>>>> pullAll(
    List<String> tables,
  ) async {
    if (failPull) throw Exception('nema mreže');
    return {for (final t in tables) t: Map.of(data[t] ?? {})};
  }

  @override
  Future<void> upsert(String table, String id, Map<String, dynamic> d) async {
    if (rejected.contains('$table/$id')) throw Exception('odbijeno');
    upserts++;
    (data[table] ??= {})[id] = d;
  }

  @override
  Future<void> delete(String table, String id) async => data[table]?.remove(id);

  @override
  Future<void> clearAll(List<String> tables) async => data.clear();

  @override
  Stream<RemoteChange> changes(List<String> tables) => _changes.stream;

  /// Drugi tester je nešto promijenio.
  void simulateOther(String table, String id, Map<String, dynamic>? d) {
    if (d == null) {
      data[table]?.remove(id);
    } else {
      (data[table] ??= {})[id] = d;
    }
    _changes.add(RemoteChange(table, id, d));
  }
}

void main() {
  late StorageService storage;
  late FakeRemote remote;

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    remote = FakeRemote();
    // Online baza već postoji (s demo podacima) — aplikacija ih ne šalje
    // sama, pa ih test unaprijed upisuje.
    for (final t in storage.exportAll().entries) {
      remote.data[t.key] = {
        for (final r in t.value.entries) r.key: Map.of(r.value),
      };
    }
  });

  tearDown(() => Hive.close());

  test('demo podaci se nikad sami ne šalju u online bazu', () async {
    remote.data.clear();
    final sync = SyncService(storage, remote);
    await sync.start();
    expect(sync.status, SyncStatus.online);
    expect(remote.data['users'] ?? {}, isEmpty);
    expect(remote.data['devices'] ?? {}, isEmpty);
  });

  test('s online bazom nema lokalnih demo podataka', () async {
    await Hive.close();
    final fresh = StorageService();
    await fresh.init(inMemory: true, seed: false);
    expect(fresh.users, isEmpty);
  });

  test('postojeća online baza zamjenjuje lokalne podatke', () async {
    remote.data.clear();
    remote.data['users'] = {
      'u-x': {
        'id': 'u-x',
        'email': 'x@loop.com',
        'name': 'X',
        'credits': 5,
        'createdAt': DateTime(2026).toIso8601String(),
      },
    };
    await SyncService(storage, remote).start();
    expect(storage.users.single.email, 'x@loop.com');
    expect(storage.devices, isEmpty);
  });

  test('lokalna promjena odlazi u bazu', () async {
    await SyncService(storage, remote).start();
    await TradeService(
      storage,
    ).sell(userId: SeedData.demoUserId, deviceId: 'seed-9');
    await Future<void>.delayed(Duration.zero);
    expect(remote.data['devices']!['seed-9']!['ownerId'], isNull);
    expect(remote.data['users']![SeedData.demoUserId]!['credits'], 1560);
    expect(remote.data['transactions'], hasLength(1));
  });

  test('tuđa promjena stiže lokalno i osvježava prikaz', () async {
    final sync = SyncService(storage, remote);
    var refreshed = 0;
    sync.onRemoteChange = () => refreshed++;
    await sync.start();
    refreshed = 0; // spajanje je već osvježilo prikaz

    final user = Map<String, dynamic>.from(
      remote.data['users']![SeedData.testUserId]!,
    )..['credits'] = 999;
    remote.simulateOther('users', SeedData.testUserId, user);
    await Future<void>.delayed(Duration.zero);
    expect(storage.userById(SeedData.testUserId)!.credits, 999);
    expect(refreshed, 1);

    remote.simulateOther('devices', 'seed-1', null);
    await Future<void>.delayed(Duration.zero);
    expect(storage.deviceById('seed-1'), isNull);
  });

  test('bez mreže aplikacija nastavlja lokalno', () async {
    remote.failPull = true;
    final sync = SyncService(storage, remote);
    await sync.start();
    expect(sync.status, SyncStatus.error);
    expect(storage.users, isNotEmpty);
    expect(remote.upserts, 0);
    await sync.dispose();
  });

  test('promjene bez veze čekaju i šalju se nakon ponovnog spajanja', () async {
    // Online baza već ima podatke (drugi testeri).
    remote.data['users'] = {
      'u-x': {
        'id': 'u-x',
        'email': '',
        'name': 'X',
        'credits': 5,
        'createdAt': DateTime(2026).toIso8601String(),
      },
    };
    remote.failPull = true;
    final sync = SyncService(storage, remote);
    await sync.start();
    expect(sync.status, SyncStatus.error);

    // Dok veza ne radi: prijava i promjena vlastitog profila.
    await storage.saveSession(userId: SeedData.demoUserId);
    final demo = storage.userById(SeedData.demoUserId)!;
    await storage.putUser(demo.copyWith(credits: 777));
    expect(remote.upserts, 0); // ništa nije poslano

    remote.failPull = false;
    await sync.retry();
    await Future<void>.delayed(Duration.zero);
    expect(sync.status, SyncStatus.online);
    // Vlastiti profil nije nestao i poslan je u bazu.
    expect(storage.userById(SeedData.demoUserId)!.credits, 777);
    expect(remote.data['users']![SeedData.demoUserId]!['credits'], 777);
    // Tuđi podaci iz baze su stigli.
    expect(storage.userById('u-x'), isNotNull);
    await sync.dispose();
  });

  test(
    'zapis koji baza odbija ne zaustavlja ostale (npr. novi oglas)',
    () async {
      final sync = SyncService(storage, remote);
      await sync.start();
      // Profil demo korisnika baza odbija…
      remote.rejected.add('users/${SeedData.demoUserId}');
      await TradeService(
        storage,
      ).sell(userId: SeedData.demoUserId, deviceId: 'seed-9');
      await Future<void>.delayed(Duration.zero);
      // …ali predmet i transakcija ipak stižu.
      expect(remote.data['devices']!['seed-9']!['ownerId'], isNull);
      expect(remote.data['transactions'], hasLength(1));
      expect(sync.pendingCount, 1);
      expect(sync.lastError, contains('odbijeno'));
      // Kad baza opet prima, šalje se i ostatak.
      remote.rejected.clear();
      await sync.flushNow();
      expect(sync.pendingCount, 0);
      expect(remote.data['users']![SeedData.demoUserId]!['credits'], 1560);
      await sync.dispose();
    },
  );

  test('bez prijave promjene čekaju, nakon osvježavanja se ne gube', () async {
    var sync = SyncService(storage, remote);
    await sync.start();
    remote.canWrite = false; // odjavljen / sesija istekla
    final before = remote.upserts;
    final demo = storage.userById(SeedData.demoUserId)!;
    await storage.putUser(demo.copyWith(credits: 4321));
    await Future<void>.delayed(Duration.zero);
    expect(remote.upserts, before); // ništa nije poslano
    // Profil i (privatni) podaci prodavatelja čekaju slanje.
    expect(storage.pendingSync, [
      'users/${SeedData.demoUserId}',
      'sellers/${SeedData.demoUserId}',
    ]);
    await sync.dispose();

    // "Osvježavanje stranice": novo pokretanje povlači bazu, ali lokalna
    // neposlana promjena ostaje i šalje se nakon prijave.
    sync = SyncService(storage, remote);
    await sync.start();
    expect(storage.userById(SeedData.demoUserId)!.credits, 4321);
    expect(sync.pendingCount, 2);
    remote.canWrite = true;
    await sync.flushNow();
    expect(remote.data['users']![SeedData.demoUserId]!['credits'], 4321);
    expect(sync.pendingCount, 0);
    expect(storage.pendingSync, isEmpty);
    await sync.dispose();
  });

  test(
    'podaci prodavatelja idu u zasebnu tablicu, ne u javni profil',
    () async {
      await SyncService(storage, remote).start();
      final users = remote.data['users']![SeedData.demoUserId]!;
      expect(users.containsKey('seller'), isFalse);
      expect(
        remote.data['sellers']![SeedData.demoUserId]!['oib'],
        '12345678903',
      );
      expect(storage.userById(SeedData.demoUserId)!.seller!.oib, '12345678903');
    },
  );

  test('isti komad ne može se prodati dvaput (dva uređaja)', () async {
    final sync = SyncService(storage, remote);
    await sync.start();
    // Drugi uređaj je već zauzeo ovaj komad u bazi.
    final own = storage.devices.firstWhere(
      (x) => !x.isDigital && x.ownerId == SeedData.anaUserId,
    );
    await storage.putDevice(own.withListing(50));
    final d = storage.deviceById(own.id)!;
    final seller = storage.userById(d.ownerId!)!;
    remote.data['transactions']!['sale-${d.id}-${seller.id}-${d.listedAt?.millisecondsSinceEpoch ?? 0}-${d.quantity}'] =
        {'id': 'drugi'};
    await expectLater(
      TradeService(storage).buy(userId: SeedData.demoUserId, deviceId: d.id),
      throwsA(isA<TradeException>()),
    );
    // Ništa se nije promijenilo: predmet i zarada prodavatelja ostaju.
    expect(storage.deviceById(d.id)!.ownerId, seller.id);
    expect(storage.userById(seller.id)!.credits, seller.credits);
    await sync.dispose();
  });
}
