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
  });

  tearDown(() => Hive.close());

  test('prazna online baza dobiva lokalne demo podatke', () async {
    final sync = SyncService(storage, remote);
    await sync.start();
    expect(sync.status, SyncStatus.online);
    expect(remote.data['users']!.keys, contains(SeedData.demoUserId));
    expect(remote.data['devices'], hasLength(39));
    expect(remote.data['auctions'], hasLength(4));
  });

  test('postojeća online baza zamjenjuje lokalne podatke', () async {
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

  test('reset demo podataka prepisuje i online bazu', () async {
    final sync = SyncService(storage, remote);
    await sync.start();
    remote.data['users']!['strani'] = {'id': 'strani'};
    await storage.resetAll();
    await sync.resetRemote();
    expect(remote.data['users']!.containsKey('strani'), isFalse);
    expect(remote.data['users'], hasLength(4));
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
    expect(storage.pendingSync, ['users/${SeedData.demoUserId}']);
    await sync.dispose();

    // "Osvježavanje stranice": novo pokretanje povlači bazu, ali lokalna
    // neposlana promjena ostaje i šalje se nakon prijave.
    sync = SyncService(storage, remote);
    await sync.start();
    expect(storage.userById(SeedData.demoUserId)!.credits, 4321);
    expect(sync.pendingCount, 1);
    remote.canWrite = true;
    await sync.flushNow();
    expect(remote.data['users']![SeedData.demoUserId]!['credits'], 4321);
    expect(sync.pendingCount, 0);
    expect(storage.pendingSync, isEmpty);
    await sync.dispose();
  });
}
