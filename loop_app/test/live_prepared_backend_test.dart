import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loop_app/services/live_backend.dart';

void main() {
  test(
    'prepared form is sent as one atomic request with schedule and ordered lots',
    () async {
      final calls = <Map<String, dynamic>>[];
      final transport = MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/live_prepare_room');
        calls.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          '{"id":"new-room"}',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: transport,
      );
      final result = await LiveBackend(client).prepareRoom(
        title: 'Retro večer',
        category: 'console',
        cover: 'https://example.test/cover.jpg',
        startsAt: DateTime.utc(2026, 11, 1, 20),
        seconds: 10,
        video: true,
        requestId: 'stable-request',
        lots: [
          {'title': 'PSP', 'start_cents': 100},
          {'title': 'Game Boy #150', 'start_cents': 200},
        ],
      );
      expect(result['id'], 'new-room');
      expect(calls, hasLength(1));
      expect(calls.single['p_starts'], '2026-11-01T20:00:00.000Z');
      expect(calls.single['p_request'], 'stable-request');
      expect((calls.single['p_lots'] as List).map((e) => e['title']), [
        'PSP',
        'Game Boy #150',
      ]);
      expect(calls.single['p_cover'], 'https://example.test/cover.jpg');
      await client.dispose();
      transport.close();
    },
  );
}
