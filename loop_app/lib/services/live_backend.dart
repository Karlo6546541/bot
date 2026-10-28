import 'package:supabase_flutter/supabase_flutter.dart';

/// Production live API. Identity is always derived from Supabase Auth by SQL.
/// Request IDs must survive reconnects: reuse the same ID when retrying a command.
/// This adapter is separate from the legacy local/demo LiveService.
class LiveBackend {
  LiveBackend(this.client);
  final SupabaseClient client;

  Future<dynamic> createRoom(String title, String category) => client.rpc(
    'live_create_room', params: {'p_title': title, 'p_category': category},
  );
  Future<dynamic> setStatus(String room, String status) => client.rpc(
    'live_set_status', params: {'p_room': room, 'p_status': status},
  );
  Future<dynamic> addLot(String room, String title, int cents, int increment) =>
    client.rpc('live_add_lot', params: {'p_room': room, 'p_title': title,
      'p_start': cents, 'p_increment': increment});
  Future<dynamic> startLot(String lot, int seconds) => client.rpc(
    'live_start_lot', params: {'p_lot': lot, 'p_seconds': seconds},
  );
  Future<dynamic> bid(String lot, int cents, String requestId) => client.rpc(
    'live_place_bid', params: {'p_lot': lot, 'p_amount': cents, 'p_request': requestId},
  );
  Future<dynamic> finishLot(String lot) => client.rpc(
    'live_finish_lot', params: {'p_lot': lot},
  );
  Future<dynamic> sendMessage(String room, String body, String requestId) =>
    client.rpc('live_send_message', params: {'p_room': room,
      'p_body': body, 'p_request': requestId});
  Future<dynamic> moderate(String room, String user,
      {required bool muted, required bool banned}) => client.rpc(
    'live_moderate', params: {'p_room': room, 'p_user': user,
      'p_muted': muted, 'p_banned': banned},
  );
  Future<dynamic> deleteMessage(int id) => client.rpc(
    'live_delete_message', params: {'p_id': id},
  );

  /// Realtime signal only: fetch authoritative data after reconnect, then page
  /// history by message ID. Avoid loading the whole marketplace for each room.
  RealtimeChannel watch(String room, void Function() refresh) => client
    .channel('live-state-$room')
    .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
      table: 'live_lots', filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq, column: 'room_id', value: room),
      callback: (_) => refresh())
    .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
      table: 'live_messages', filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq, column: 'room_id', value: room),
      callback: (_) => refresh())
    .subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) refresh();
    });

  Future<List<Map<String, dynamic>>> messages(String room, {int? before}) async {
    var query = client.from('live_messages').select()
      .eq('room_id', room);
    if (before != null) query = query.lt('id', before);
    return await query.order('id', ascending: false).limit(50);
  }

  Future<Map<String, dynamic>> videoToken(String room) async {
    final response = await client.functions.invoke('live-token', body: {'roomId': room});
    if (response.status != 200) throw StateError('LIVE_TOKEN_UNAVAILABLE');
    return Map<String, dynamic>.from(response.data as Map);
  }
}
