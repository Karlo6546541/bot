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
  Future<Map<String, Map<String, Map<String, dynamic>>>> pullAll(
    List<String> tables,
  ) async {
    if (failPull) throw Exception('nema mreže');
    return {for (final t in tables) t: Map.of(data[t] ?? {})};
  }

  @override
  Future<void> upsert(String table, String id, Map<String, dynamic> d) async {
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
    expect(remote.data['devices'], hasLength(37));
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
    expect(remote.data['users']![SeedData.demoUserId]!['credits'], 1544.5);
    expect(remote.data['transactions'], hasLength(1));
  });

  test('tuđa promjena stiže lokalno i osvježava prikaz', () async {
    final sync = SyncService(storage, remote);
    var refreshed = 0;
    sync.onRemoteChange = () => refreshed++;
    await sync.start();

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
}
