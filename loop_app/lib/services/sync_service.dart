import 'dart:async';

import 'remote_store.dart';
import 'storage_service.dart';

enum SyncStatus { offline, connecting, online, error }

/// Sinkronizacija lokalne pohrane (Hive) s online bazom.
///
/// Model "lokalno prvo": aplikacija i dalje čita i piše lokalno (brzo,
/// radi i bez mreže), a ovaj servis:
/// 1. pri pokretanju povuče sve podatke iz baze (ili, ako je baza prazna,
///    u nju pošalje lokalne demo podatke);
/// 2. svaku lokalnu promjenu pošalje u bazu;
/// 3. promjene drugih korisnika primi u stvarnom vremenu i spremi lokalno.
///
/// Ograničenje testne verzije: pravila trgovanja provjerava aplikacija,
/// ne server, a istovremene izmjene istog zapisa rješavaju se pravilom
/// "zadnji pobjeđuje". Za produkciju bi kupnje/ponude išle kroz
/// funkcije na serveru (vidi README).
class SyncService {
  SyncService(this._storage, this._remote);

  final StorageService _storage;
  final RemoteStore _remote;

  SyncStatus status = SyncStatus.offline;
  String? lastError;

  /// Poziva se kad stignu tuđe promjene (aplikacija osvježi prikaz).
  void Function()? onRemoteChange;

  StreamSubscription<RemoteChange>? _sub;

  /// Neposlane promjene (npr. dok je mreža pala) — šalju se ponovno.
  final _pending = <String, (String, String, Map<String, dynamic>?)>{};
  Timer? _retry;

  /// Tablice koje postoje u online bazi (ostale rade samo lokalno).
  List<String> _tables = StorageService.syncedTables;

  List<String> get onlineTables => _tables;

  Future<void> start({Duration timeout = const Duration(seconds: 10)}) async {
    status = SyncStatus.connecting;
    try {
      final remote = await _remote
          .pullAll(StorageService.syncedTables)
          .timeout(timeout);
      _tables = [
        for (final t in StorageService.syncedTables)
          if (remote.containsKey(t)) t,
      ];
      final remoteEmpty = remote.values.every((m) => m.isEmpty);
      if (remoteEmpty) {
        // Prvi korisnik: baza je prazna — pošalji demo podatke.
        await _pushAll();
      } else {
        await _storage.replaceAllFromRemote(remote);
      }
      _storage.onLocalChange = _queue;
      _sub = _remote.changes(_tables).listen(_onRemote);
      status = SyncStatus.online;
    } catch (e) {
      // Bez mreže/baze: nastavi lokalno.
      status = SyncStatus.error;
      lastError = '$e';
    }
  }

  Future<void> _pushAll() async {
    final all = _storage.exportAll();
    for (final t in all.entries.where((e) => _tables.contains(e.key))) {
      for (final row in t.value.entries) {
        await _remote.upsert(t.key, row.key, row.value);
      }
    }
  }

  /// Nakon "Resetiraj demo podatke": isprazni bazu i pošalji nove podatke.
  Future<void> resetRemote() async {
    if (status != SyncStatus.online) return;
    _pending.clear();
    await _remote.clearAll(_tables);
    await _pushAll();
  }

  void _queue(String table, String id, Map<String, dynamic>? data) {
    if (!_tables.contains(table)) return;
    _pending['$table/$id'] = (table, id, data);
    _flush();
  }

  Future<void> _flush() async {
    final batch = Map.of(_pending);
    for (final e in batch.entries) {
      final (table, id, data) = e.value;
      try {
        if (data == null) {
          await _remote.delete(table, id);
        } else {
          await _remote.upsert(table, id, data);
        }
        // Ukloni samo ako u međuvremenu nije stigla novija verzija.
        if (identical(_pending[e.key], e.value)) _pending.remove(e.key);
      } catch (_) {
        _retry ??= Timer(const Duration(seconds: 5), () {
          _retry = null;
          _flush();
        });
        return;
      }
    }
  }

  Future<void> _onRemote(RemoteChange c) async {
    // Ne prepisuj vlastitu promjenu koja još čeka slanje.
    if (_pending.containsKey('${c.table}/${c.id}')) return;
    await _storage.applyRemote(c.table, c.id, c.data);
    onRemoteChange?.call();
  }

  int get pendingCount => _pending.length;

  Future<void> dispose() async {
    _retry?.cancel();
    await _sub?.cancel();
    _storage.onLocalChange = null;
  }
}
