import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loop_app/services/stripe_backend.dart';
import 'package:loop_app/models/seller_info.dart';

void main() {
  final seller = SellerInfo(
    legalName: 'Test Seller',
    oib: '12345678903',
    address: 'Ulica 1, 10000 Zagreb',
    iban: 'HR1723600001101234565',
    birthDate: DateTime(1990, 1, 1),
    updatedAt: DateTime(2026),
  );
  test(
    'preparing a saved seller never launches onboarding and pins the session owner',
    () async {
      var launches = 0;
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          expect(body['action'], 'prepare');
          expect(body['expectedUserId'], 'owner-1');
          expect(body['seller']['legalName'], seller.legalName);
          for (final key in ['iban', 'oib', 'vatId', 'registryNumber']) {
            expect((body['seller'] as Map).containsKey(key), false);
          }
          return http.Response(
            '{"ready":false,"url":"https://connect.stripe.com/setup/test"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final backend = StripeBackend(
        client,
        sellerOnboarding: (_) async {
          launches++;
          return true;
        },
      );
      expect(
        await backend.prepareSeller(
          seller,
          country: 'HR',
          expectedUserId: 'owner-1',
        ),
        false,
      );
      expect(launches, 0);
      await client.dispose();
    },
  );
  test(
    'ready sellers continue without a redirect and send no payout account or tax number',
    () async {
      var launches = 0;
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/functions/v1/stripe-connect');
          final body = jsonDecode(request.body) as Map;
          expect(body['action'], 'session');
          expect(body['country'], 'HR');
          expect(body['seller']['legalName'], 'Test Seller');
          expect((body['seller'] as Map).containsKey('iban'), false);
          expect((body['seller'] as Map).containsKey('oib'), false);
          expect(body.containsKey('account'), false);
          return http.Response(
            '{"ready":true,"mode":"test"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final ready = await StripeBackend(
        client,
        sellerOnboarding: (_) async {
          launches++;
          return true;
        },
      ).ensureSellerReady(seller, country: 'HR');
      expect(ready, true);
      expect(launches, 0);
      await client.dispose();
    },
  );
  test(
    'unfinished seller completes the embedded form inside the app, then status is re-checked',
    () async {
      Map<String, dynamic>? opened;
      final actions = <String>[];
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          final action = (jsonDecode(request.body) as Map)['action'] as String;
          actions.add(action);
          return http.Response(
            action == 'session'
                ? '{"ready":false,"clientSecret":"accs_secret_test","publishableKey":"pk_test_x"}'
                : '{"ready":true}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      expect(
        await StripeBackend(
          client,
          sellerOnboarding: (session) async {
            opened = session;
            return true;
          },
        ).ensureSellerReady(seller, country: 'HR'),
        true,
      );
      // Nema adrese Stripeove stranice: samo tajna kratkotrajne sesije.
      expect(opened, {
        'clientSecret': 'accs_secret_test',
        'publishableKey': 'pk_test_x',
      });
      expect(actions, ['session', 'prepare']);
      await client.dispose();
    },
  );
  test('a response without an embedded session never opens anything', () async {
    var launches = 0;
    final client = SupabaseClient(
      'https://test.invalid',
      'test-key',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"ready":false,"url":"https://connect.stripe.com/setup/test"}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await expectLater(
      StripeBackend(
        client,
        sellerOnboarding: (_) async {
          launches++;
          return true;
        },
      ).ensureSellerReady(seller, country: 'HR'),
      throwsStateError,
    );
    expect(launches, 0);
    await client.dispose();
  });
}
