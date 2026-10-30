import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loop_app/services/stripe_backend.dart';

void main() {
  test(
    'Connect activation response reaches the user as an actionable message',
    () async {
      var calls = 0;
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          calls++;
          expect(request.url.path, '/functions/v1/stripe-connect');
          return http.Response(
            '{"error":"CONNECT_PLATFORM_REQUIRED"}',
            409,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      try {
        await StripeBackend(client).connectSeller();
        fail('The unavailable onboarding must not launch a payment page');
      } on FunctionException catch (error) {
        expect(
          paymentActionErrorMessage(error),
          contains('aktivirati Stripe Connect'),
        );
      } finally {
        await client.dispose();
      }
      expect(calls, 1);
      expect(
        paymentActionErrorMessage(StateError('private details')),
        isNot(contains('private details')),
      );
    },
  );

  test('kartica: status i automatska naplata', () async {
    final calls = <String>[];
    final client = SupabaseClient(
      'https://test.invalid',
      'test-key',
      httpClient: MockClient((request) async {
        calls.add(request.url.path);
        final body = request.url.path.endsWith('stripe-setup')
            ? '{"hasCard":true,"brand":"visa","last4":"4242"}'
            : request.url.path.endsWith('stripe-charge')
            ? '{"status":"paid","last4":"4242"}'
            : '{}';
        return http.Response(
          body,
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final backend = StripeBackend(client);
    final status = await backend.cardStatus();
    expect(status.hasCard, isTrue);
    expect(status.last4, '4242');
    expect(await backend.charge('order-1'), isTrue);
    expect(calls, [
      '/functions/v1/stripe-setup',
      '/functions/v1/stripe-charge',
    ]);
    expect(
      paymentActionErrorMessage(
        FunctionException(status: 402, details: {'error': 'CARD_DECLINED'}),
      ),
      contains('odbila karticu'),
    );
    await client.dispose();
  });
}
