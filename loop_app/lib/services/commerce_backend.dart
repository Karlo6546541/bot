import 'package:supabase_flutter/supabase_flutter.dart';

/// Authoritative marketplace commands; all amounts are EUR cents.
/// The Supabase JWT supplies identity. Never mark an order paid from the app.
class CommerceBackend {
  CommerceBackend(this.client);
  final SupabaseClient client;

  Future<dynamic> publish(String title, int cents, int stock) => client.rpc(
    'commerce_publish',
    params: {'p_title': title, 'p_price': cents, 'p_stock': stock},
  );
  Future<dynamic> reserve(String product, int quantity, String requestId) =>
      client.rpc(
        'commerce_reserve',
        params: {
          'p_product': product,
          'p_quantity': quantity,
          'p_request': requestId,
        },
      );
  Future<dynamic> claimAward(String lot, String requestId) => client.rpc(
    'commerce_claim_award',
    params: {'p_lot': lot, 'p_request': requestId},
  );
  Future<dynamic> follow(String seller, bool enabled) => client.rpc(
    'commerce_follow',
    params: {'p_seller': seller, 'p_follow': enabled},
  );
  Future<dynamic> favorite(String product, bool enabled) => client.rpc(
    'commerce_favorite',
    params: {'p_product': product, 'p_favorite': enabled},
  );
  Future<dynamic> chooseShipping(
    String order,
    String method,
    Map<String, dynamic> destination,
  ) => client.rpc(
    'commerce_choose_shipping',
    params: {
      'p_order': order,
      'p_method': method,
      'p_destination': destination,
    },
  );
  Future<dynamic> cancel(String order) =>
      client.rpc('commerce_cancel', params: {'p_order': order});
  Future<dynamic> ship(String order, String carrier, String tracking) =>
      client.rpc(
        'commerce_ship',
        params: {
          'p_order': order,
          'p_carrier': carrier,
          'p_tracking': tracking,
        },
      );
  Future<dynamic> confirmDelivery(String order) =>
      client.rpc('commerce_confirm_delivery', params: {'p_order': order});
  Future<List<Map<String, dynamic>>> orders({int offset = 0, String? id}) async {
    var query = client.from('commerce_orders').select();
    if (id != null) query = query.eq('id', id);
    return await query.order('created_at', ascending: false).order('id')
        .range(offset, offset + 49);
  }
  Future<List<Map<String, dynamic>>> notifications({int? before}) async {
    var query = client.from('commerce_notifications').select();
    if (before != null) query = query.lt('id', before);
    return await query.order('id', ascending: false).limit(50);
  }

  Future<dynamic> readNotification(int id) =>
      client.rpc('commerce_read_notification', params: {'p_id': id});
}
