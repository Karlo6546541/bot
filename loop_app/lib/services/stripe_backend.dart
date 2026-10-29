import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class StripeBackend {
  StripeBackend(this.client);
  final SupabaseClient client;
  Future<void> connectSeller() => _open('stripe-connect', {});
  Future<void> checkout(String order) =>
      _open('stripe-checkout', {'orderId': order});
  Future<void> _open(String function, Map<String, dynamic> body) async {
    final response = await client.functions.invoke(function, body: body);
    final url = Uri.tryParse((response.data as Map?)?['url'] as String? ?? '');
    final allowed = function == 'stripe-connect'
        ? {'connect.stripe.com'}
        : {'checkout.stripe.com'};
    if (response.status != 200 ||
        url == null ||
        url.scheme != 'https' ||
        !allowed.contains(url.host)) {
      throw StateError('PAYMENTS_UNAVAILABLE');
    }
    if (!await launchUrl(url, webOnlyWindowName: '_self')) {
      throw StateError('PAYMENT_PAGE_UNAVAILABLE');
    }
  }
}
