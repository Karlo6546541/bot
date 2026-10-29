import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loop_app/services/my_activity_backend.dart';

void main() {
  test('personal activity scopes every query and deduplicates repeated bids', () async {
    const uid = '00000000-0000-4000-8000-000000000001';
    final reads = <Uri>[];
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': uid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.signature';
    final client = SupabaseClient('https://test.invalid', 'public-key', httpClient: MockClient((request) async {
      Object response;
      if (request.url.path == '/auth/v1/token') {
        response = {'access_token': token, 'refresh_token': 'refresh', 'token_type': 'bearer', 'expires_in': 3600,
          'user': {'id': uid, 'aud': 'authenticated', 'app_metadata': {}, 'user_metadata': {}, 'created_at': '2026-10-29T00:00:00Z'}};
      } else {
        reads.add(request.url);
        response = switch (request.url.path.split('/').last) {
          'live_bids' => [
            {'lot_id': 'lot-1', 'amount_cents': 300}, {'lot_id': 'lot-1', 'amount_cents': 200},
          ],
          'live_awards' => [
            {'lot_id': 'ordered-lot', 'status': 'awaiting_checkout'},
            {'lot_id': 'unclaimed-lot', 'status': 'awaiting_checkout'},
          ],
          'commerce_orders' => [{'id': 'order-1', 'award_lot_id': 'ordered-lot', 'buyer_id': uid}],
          _ => [{'id': 'room-1', 'host_id': uid}],
        };
      }
      return http.Response(jsonEncode(response), 200, request: request, headers: {'content-type': 'application/json'});
    }));
    expect((await MyActivityBackend(client).load()).rooms, isEmpty);
    expect(reads, isEmpty, reason: 'Guests must not request private activity');
    await client.auth.signInWithPassword(email: 'fixture@example.test', password: 'fixture-only');
    final data = await MyActivityBackend(client).load();
    expect(reads, hasLength(4));
    for (final uri in reads) {
      expect(uri.query, contains(uid));
      expect(uri.queryParameters['limit'], isNotNull);
    }
    expect(data.bids.single['amount_cents'], 300);
    expect(data.unclaimedAwards.single['lot_id'], 'unclaimed-lot');
    expect(data.rooms.single['id'], 'room-1');
    expect(reads.singleWhere((u) => u.path.endsWith('commerce_orders')).queryParameters['select'], contains('commerce_shipments'));
    await client.dispose();
  });
}
