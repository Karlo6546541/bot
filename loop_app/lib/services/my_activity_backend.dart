import 'package:supabase_flutter/supabase_flutter.dart';

class MyOnlineActivity {
  const MyOnlineActivity({this.rooms = const [], this.bids = const [],
    this.awards = const [], this.orders = const []});
  final List<Map<String, dynamic>> rooms, bids, awards, orders;

  List<Map<String, dynamic>> get unclaimedAwards => awards.where((a) =>
    a['status'] == 'awaiting_checkout' &&
    !orders.any((o) => o['award_lot_id'] == a['lot_id'])).toList();
}

/// Read the signed-in user's online activity. RLS remains authoritative.
class MyActivityBackend {
  MyActivityBackend(this.client);
  final SupabaseClient client;

  Future<MyOnlineActivity> load() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return const MyOnlineActivity();
    final rows = await Future.wait([
      client.from('live_rooms').select().eq('host_id', uid)
        .order('created_at', ascending: false).order('id').limit(50),
      client.from('live_bids')
        .select('lot_id,amount_cents,created_at,live_lots(id,title,room_id,status,winner_id,price_cents)')
        .eq('bidder_id', uid).order('id', ascending: false).limit(100),
      client.from('live_awards')
        .select('lot_id,status,amount_cents,live_lots(id,title,room_id)')
        .eq('buyer_id', uid).order('created_at', ascending: false).limit(50),
      client.from('commerce_orders').select('*,commerce_shipments(*)')
        .or('buyer_id.eq.$uid,seller_id.eq.$uid')
        .order('created_at', ascending: false).order('id').limit(50),
    ]);
    if (client.auth.currentUser?.id != uid) return const MyOnlineActivity();
    final seen = <String>{};
    return MyOnlineActivity(rooms: rows[0], bids: [
      for (final bid in rows[1])
        if (seen.add(bid['lot_id'] as String)) bid,
    ], awards: rows[2], orders: rows[3]);
  }
}
