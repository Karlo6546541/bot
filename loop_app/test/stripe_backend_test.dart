import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loop_app/services/stripe_backend.dart';

void main() {
  test('Connect activation response reaches the user as an actionable message', () async {
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
      expect(paymentActionErrorMessage(error), contains('aktivirati Stripe Connect'));
    } finally {
      await client.dispose();
    }
    expect(calls, 1);
    expect(paymentActionErrorMessage(StateError('private details')),
      isNot(contains('private details')));
  });
}
