import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Promjena koja je stigla iz online baze (`data == null` = brisanje).
class RemoteChange {
  const RemoteChange(this.table, this.id, this.data);
  final String table;
  final String id;
  final Map<String, dynamic>? data;
}

/// Online pohrana dokumenata: tablica → (id → JSON podaci).
/// Sučelje postoji kako bi se sinkronizacija mogla testirati bez mreže.
abstract class RemoteStore {
  /// Vraća podatke tablica koje postoje u bazi. Tablica koje još nema
  /// (npr. SQL za novu verziju nije pokrenut) nema u rezultatu — ona
  /// tada radi samo lokalno.
  Future<Map<String, Map<String, Map<String, dynamic>>>> pullAll(
    List<String> tables,
  );
  Future<void> upsert(String table, String id, Map<String, dynamic> data);
  Future<void> delete(String table, String id);

  /// Smije li pisati (online baza prima izmjene samo od prijavljenih).
  bool get canWrite;
  Future<void> clearAll(List<String> tables);

  /// Promjene drugih korisnika u stvarnom vremenu.
  Stream<RemoteChange> changes(List<String> tables);
}

/// Supabase: svaka lokalna tablica je Postgres tablica `loop_<ime>`
/// sa stupcima `id text`, `data jsonb`, `updated_at` (vidi
/// `supabase/schema.sql`).
class SupabaseRemoteStore implements RemoteStore {
  SupabaseRemoteStore(this._client);

  final SupabaseClient _client;

  static String tableName(String t) => 'loop_$t';

  @override
  Future<Map<String, Map<String, Map<String, dynamic>>>> pullAll(
    List<String> tables,
  ) async {
    // Sve tablice odjednom (paralelno) — brže na sporoj mreži.
    final results = await Future.wait(tables.map(_pull));
    final out = <String, Map<String, Map<String, dynamic>>>{};
    for (var i = 0; i < tables.length; i++) {
      final r = results[i];
      if (r != null) out[tables[i]] = r;
    }
    return out;
  }

  /// `null` ako tablica još ne postoji u bazi.
  Future<Map<String, Map<String, dynamic>>?> _pull(String t) async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _client.from(tableName(t)).select('id, data');
    } on PostgrestException catch (e) {
      if (e.code == '42P01' ||
          e.code == 'PGRST205' ||
          e.message.contains('does not exist') ||
          e.message.contains('Could not find')) {
        return null;
      }
      rethrow;
    }
    return {
      for (final r in rows)
        r['id'] as String: Map<String, dynamic>.from(r['data'] as Map),
    };
  }

  @override
  bool get canWrite => _client.auth.currentSession != null;

  @override
  Future<void> upsert(String table, String id, Map<String, dynamic> data) =>
      _client.from(tableName(table)).upsert({
        'id': id,
        'data': data,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  @override
  Future<void> delete(String table, String id) =>
      _client.from(tableName(table)).delete().eq('id', id);

  @override
  Future<void> clearAll(List<String> tables) async {
    for (final t in tables) {
      await _client.from(tableName(t)).delete().neq('id', '');
    }
  }

  @override
  Stream<RemoteChange> changes(List<String> tables) {
    final controller = StreamController<RemoteChange>.broadcast();
    var channel = _client.channel('loop-sync');
    for (final t in tables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: tableName(t),
        callback: (p) {
          if (p.eventType == PostgresChangeEvent.delete) {
            final id = p.oldRecord['id'] as String?;
            if (id != null) controller.add(RemoteChange(t, id, null));
          } else {
            final rec = p.newRecord;
            controller.add(
              RemoteChange(
                t,
                rec['id'] as String,
                Map<String, dynamic>.from(rec['data'] as Map),
              ),
            );
          }
        },
      );
    }
    channel.subscribe();
    controller.onCancel = () => _client.removeChannel(channel);
    return controller.stream;
  }
}
