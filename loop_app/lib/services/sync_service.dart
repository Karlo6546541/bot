import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;

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
  bool _flushing = false;
  bool _again = false;

  /// Uzastopni neuspjesi slanja (za postupno dulje čekanje).
  int _failedRounds = 0;

  /// Broj neposlanih promjena (za prikaz u Profilu).
  final pendingListenable = ValueNotifier<int>(0);

  /// Tablice koje postoje u online bazi (ostale rade samo lokalno).
  List<String> _tables = StorageService.syncedTables;

  List<String> get onlineTables => _tables;

  /// Tablice kojih nema u online bazi (SQL za novu verziju nije pokrenut) —
  /// njihovi podaci (npr. poruke) ostaju samo na ovom uređaju.
  List<String> get missingTables => status == SyncStatus.online
      ? [
          for (final t in StorageService.syncedTables)
            if (!_tables.contains(t)) t,
        ]
      : const [];

  /// Stanje veze za prikaz (Profil) — mijenja se i nakon ponovnog spajanja.
  final statusListenable = ValueNotifier<SyncStatus>(SyncStatus.offline);

  void _setStatus(SyncStatus s) {
    status = s;
    statusListenable.value = s;
  }

  Timer? _reconnect;
  int _attempt = 0;
  Duration _timeout = const Duration(seconds: 20);

  /// Spaja se na bazu. Ako ne uspije (spora mreža, baza se "budi"),
  /// aplikacija radi lokalno, promjene čekaju u redu, a spajanje se
  /// automatski ponavlja (15 s, 30 s, 60 s… najviše 2 min).
  Future<void> start({Duration timeout = const Duration(seconds: 20)}) async {
    _timeout = timeout;
    // Lokalne promjene se bilježe od početka; šalju se kad veza proradi.
    _storage.onLocalChange = _queue;
    _storage.remoteClaim = _claim;
    _restorePending();
    await _connect();
  }

  /// Ručni "Pokušaj ponovno".
  Future<void> retry() async {
    if (status == SyncStatus.online || status == SyncStatus.connecting) return;
    _reconnect?.cancel();
    _attempt = 0;
    await _connect();
  }

  Future<void> _connect() async {
    _setStatus(SyncStatus.connecting);
    try {
      final remote = await _remote
          .pullAll(StorageService.syncedTables)
          .timeout(_timeout);
      _tables = [
        for (final t in StorageService.syncedTables)
          if (remote.containsKey(t)) t,
      ];
      {
        // Vlastiti profil koji online još ne postoji (napravljen dok veza
        // nije radila) ne smije nestati.
        final me = _storage.currentUserId;
        final myLocal = me == null ? null : _storage.exportAll()['users']?[me];
        await _storage.replaceAllFromRemote(remote);
        if (myLocal != null && remote['users']?[me] == null) {
          await _storage.applyRemote('users', me!, myLocal);
          _pending['users/$me'] = ('users', me, myLocal);
        }
        // Promjene napravljene dok nije bilo veze vrijede i dalje.
        for (final (table, id, data) in _pending.values) {
          await _storage.applyRemote(table, id, data);
        }
      }
      _pending.removeWhere((_, v) => !_tables.contains(v.$1));
      _changed();
      await _sub?.cancel();
      _sub = _remote.changes(_tables).listen(_onRemote);
      _attempt = 0;
      lastError = null;
      _setStatus(SyncStatus.online);
      onRemoteChange?.call();
      unawaited(_flush());
    } catch (e) {
      // Bez mreže/baze: nastavi lokalno i pokušaj ponovno kasnije.
      lastError = '$e';
      _setStatus(SyncStatus.error);
      _scheduleReconnect();
    }
  }

  /// Atomski upis u bazu (vidi [StorageService.claimTransaction]).
  Future<bool?> _claim(
    String table,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (status != SyncStatus.online ||
        !_remote.canWrite ||
        !_tables.contains(table)) {
      return null;
    }
    try {
      return await _remote.claim(table, id, data);
    } catch (_) {
      return null;
    }
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    final seconds = (15 * (1 << _attempt)).clamp(15, 120);
    _attempt = (_attempt + 1).clamp(0, 4);
    _reconnect = Timer(Duration(seconds: seconds), _connect);
  }

  /// Neposlane promjene iz prošlog pokretanja (npr. oglas objavljen pa
  /// stranica osvježena prije slanja) — šalju se s trenutnim podacima.
  void _restorePending() {
    for (final key in _storage.pendingSync) {
      final slash = key.indexOf('/');
      if (slash <= 0) continue;
      final table = key.substring(0, slash);
      final id = key.substring(slash + 1);
      _pending[key] = (table, id, _storage.rawRow(table, id));
    }
    _changed();
  }

  void _changed() {
    pendingListenable.value = _pending.length;
    unawaited(_storage.setPendingSync(_pending.keys).catchError((_) {}));
  }

  void _queue(String table, String id, Map<String, dynamic>? data) {
    if (!_tables.contains(table)) return;
    _pending['$table/$id'] = (table, id, data);
    _changed();
    _flush();
  }

  /// Ručno "Pošalji sada".
  Future<void> flushNow() async {
    _retry?.cancel();
    _retry = null;
    _failedRounds = 0;
    await _flush();
  }

  void _scheduleRetry() {
    if (_retry != null) return;
    // 5 s, 10 s, 20 s… najviše 1 min.
    final seconds = (5 * (1 << _failedRounds.clamp(0, 4))).clamp(5, 60);
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      _flush();
    });
  }

  Future<void> _flush() async {
    if (status != SyncStatus.online) return; // čeka vezu
    if (_flushing) {
      _again = true;
      return;
    }
    if (_pending.isEmpty) return;
    // Bez prijave baza ne prima izmjene — čekaj prijavu (ništa se ne gubi).
    if (!_remote.canWrite) {
      _scheduleRetry();
      return;
    }
    _flushing = true;
    var failed = false;
    try {
      do {
        _again = false;
        for (final e in Map.of(_pending).entries) {
          final (table, id, data) = e.value;
          try {
            if (data == null) {
              await _remote.delete(table, id);
            } else {
              await _remote.upsert(table, id, data);
            }
            // Ukloni samo ako u međuvremenu nije stigla novija verzija.
            if (identical(_pending[e.key], e.value)) _pending.remove(e.key);
          } catch (err) {
            // Jedan zapis koji ne prolazi ne smije zaustaviti ostale
            // (npr. novi oglas) — nastavi i pokušaj ga ponovno kasnije.
            failed = true;
            lastError = '$err';
          }
        }
      } while (_again);
    } finally {
      _flushing = false;
      _changed();
    }
    if (failed) {
      _failedRounds++;
      _scheduleRetry();
    } else {
      _failedRounds = 0;
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
    _reconnect?.cancel();
    await _sub?.cancel();
    _storage.onLocalChange = null;
    _storage.remoteClaim = null;
  }
}
