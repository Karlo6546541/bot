import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loop_app/screens/cloud_commerce_screen.dart';

void main() {
  testWidgets('guest reads live chat but bidding and messaging require login', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final mutations = <String>[];
    final requests = <String>[];
    final errors = <Object>[];
    var logins = 0;
    const room = '00000000-0000-4000-8000-000000000001';
    const host = '00000000-0000-4000-8000-000000000002';
    final transport = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      if (request.method == 'POST') mutations.add(request.url.path);
      Object rows = [];
      if (request.url.path.endsWith('live_rooms')) {
        rows = [
          {
            'id': room,
            'host_id': host,
            'title': 'Retro live',
            'status': 'live',
          },
        ];
      } else if (request.url.path.endsWith('live_lots')) {
        rows = [
          {
            'id': room,
            'title': 'Game Boy',
            'status': 'running',
            'price_cents': null,
            'start_cents': 100,
            'increment_cents': 100,
            'ends_at': DateTime.now()
                .add(const Duration(seconds: 30))
                .toIso8601String(),
          },
        ];
      } else if (request.url.path.endsWith('live_messages')) {
        rows = [
          {
            'id': 1,
            'sender_id': host,
            'body': 'Dobrodošli u live!',
            'deleted': false,
          },
        ];
      } else if (request.url.path.endsWith('live-token')) {
        return http.Response(
          '{"error":"MEDIA_NOT_CONFIGURED"}',
          503,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      return http.Response(
        jsonEncode(rows),
        200,
        headers: {'content-type': 'application/json'},
          request: request,
      );
    });
    final client = SupabaseClient(
      'https://test.invalid',
      'test-key',
      httpClient: transport,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudCommerceScreen(
          client: client,
          enableRealtime: false,
          onLoadError: errors.add,
          onRequireLogin: () async {
            logins++;
          },
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    expect(find.text('Prijava'), findsOneWidget);
    expect(errors, isEmpty, reason: 'Requests: $requests');
    expect(find.text('Retro live'), findsOneWidget, reason: 'Requests: $requests; errors: $errors');
    await tester.tap(find.text('Retro live'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    expect(find.text('Dobrodošli u live!'), findsOneWidget);
    final bid = find.text('Prijavi se za licitiranje');
    await tester.ensureVisible(bid);
    await tester.tap(bid);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    expect(logins, 1);
    await tester.tap(find.byIcon(Icons.send));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    expect(logins, 2);
    expect(mutations.where((p) => p.contains('/rpc/')), isEmpty);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    expect(find.text('Dobrodošli u live!'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await client.dispose();
    transport.close();
  });
}
