import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class StripeBackend {
  StripeBackend(this.client);
  final SupabaseClient client;
  Future<void> connectSeller() => _open('stripe-connect', {});
  Future<void> checkout(String order) =>
      _open('stripe-checkout', {'orderId': order});

  /// Je li kartica spremljena (kao na Whatnotu: jednom, prije licitiranja).
  Future<({bool hasCard, String? last4})> cardStatus() async {
    final response = await client.functions.invoke(
      'stripe-setup',
      body: {'action': 'status'},
    );
    final data = response.data;
    if (response.status != 200 || data is! Map) {
      throw StateError('PAYMENTS_UNAVAILABLE');
    }
    return (hasCard: data['hasCard'] == true, last4: data['last4'] as String?);
  }

  /// Dodavanje kartice (Stripe stranica, bez naplate).
  Future<void> addCard() => _open('stripe-setup', {});

  /// Automatska naplata spremljene kartice za narudžbu. Vraća `true` kad je
  /// plaćeno; inače baca [FunctionException] sa šifrom greške.
  Future<bool> charge(String order) async {
    final response = await client.functions.invoke(
      'stripe-charge',
      body: {'orderId': order},
    );
    final data = response.data;
    return response.status == 200 && data is Map && data['status'] == 'paid';
  }

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

String paymentActionErrorMessage(Object error) {
  final code = error is FunctionException && error.details is Map
      ? (error.details as Map)['error']
      : null;
  return switch (code) {
    'CONNECT_PLATFORM_REQUIRED' =>
      'Postavljanje isplata još nije dostupno. Administrator treba aktivirati Stripe Connect za Subhasto.',
    'AUTH_REQUIRED' => 'Prijavi se ponovno za nastavak.',
    'CARD_REQUIRED' => 'Prvo dodaj karticu za plaćanje.',
    'CARD_DECLINED' => 'Banka je odbila karticu. Pokušaj drugu karticu.',
    'PAYMENT_ACTION_REQUIRED' =>
      'Banka traži dodatnu potvrdu. Plati preko Stripe stranice.',
    'SHIPPING_REQUIRED' => 'Prvo odaberi paketomat.',
    'SELLER_NOT_READY' => 'Prodavatelj još nije postavio primanje novca.',
    _ => 'Radnja nije uspjela. Osvježi stanje pa pokušaj ponovno.',
  };
}
