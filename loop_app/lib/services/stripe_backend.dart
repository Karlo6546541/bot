import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/stripe_payment/stripe_payment.dart';

class StripeBackend {
  StripeBackend(this.client);
  final SupabaseClient client;
  Future<void> connectSeller() async {
    final data = await _call('stripe-connect', {});
    final url = Uri.tryParse(data['url'] as String? ?? '');
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'connect.stripe.com') {
      throw StateError('PAYMENTS_UNAVAILABLE');
    }
    if (!await launchUrl(url, webOnlyWindowName: '_self')) {
      throw StateError('PAYMENT_PAGE_UNAVAILABLE');
    }
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> body,
  ) async {
    final result = await client.functions.invoke(name, body: body);
    if (result.status != 200 || result.data is! Map) {
      throw StateError('PAYMENTS_UNAVAILABLE');
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<({bool hasCard, String? last4})> cardStatus() async {
    final data = await _call('stripe-setup', {'action': 'status'});
    return (hasCard: data['hasCard'] == true, last4: data['last4'] as String?);
  }

  Future<bool> addCard(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spremi karticu za automatsku naplatu'),
        content: const Text(
          'Dopuštaš spremanje kartice i automatsku naplatu kupnji, osvojenih aukcija i promocija koje naručiš. Banka može zatražiti dodatnu potvrdu. Testni način: koristi testnu karticu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Prihvaćam i nastavi'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return false;
    final settings = await _call('stripe-setup', {'consent': true});
    if (!context.mounted) return false;
    await showStripePayment(context, settings);
    return (await cardStatus()).hasCard;
  }

  Future<bool> charge(String order, {BuildContext? context}) async {
    var data = await _call('stripe-charge', {
      'orderId': order,
      'action': 'resume',
    });
    if (data['status'] == 'requires_action' &&
        context != null &&
        context.mounted) {
      if (!await showStripePayment(context, data)) return false;
      data = await _call('stripe-charge', {
        'orderId': order,
        'action': 'resume',
      });
    }
    return data['status'] == 'paid';
  }

  Future<bool> promote(
    String show,
    String kind,
    int cents,
    String request, {
    BuildContext? context,
  }) async {
    final body = {
      'showId': show,
      'kind': kind,
      'amountCents': cents,
      'requestId': request,
    };
    var data = await _call('stripe-promotion', body);
    if (data['status'] == 'requires_action' &&
        context != null &&
        context.mounted) {
      if (!await showStripePayment(context, data)) return false;
      data = await _call('stripe-promotion', body);
    }
    return data['status'] == 'paid';
  }
}

String paymentActionErrorMessage(Object error) {
  final code = error is FunctionException && error.details is Map
      ? (error.details as Map)['error']
      : null;
  return switch (code) {
    'CONNECT_PLATFORM_REQUIRED' =>
      'Administrator treba aktivirati Stripe Connect za Subhasto.',
    'AUTH_REQUIRED' => 'Prijavi se ponovno za nastavak.',
    'CARD_REQUIRED' => 'Prvo dodaj karticu za plaćanje.',
    'CARD_DECLINED' => 'Banka je odbila karticu. Pokušaj drugu karticu.',
    'PAYMENT_ACTION_REQUIRED' => 'Banka traži dodatnu potvrdu kartice.',
    'PAYMENT_FORM_NOT_CONFIGURED' => 'Stripe obrazac još nije postavljen.',
    'SHIPPING_REQUIRED' => 'Prvo odaberi paketomat.',
    'SELLER_NOT_READY' => 'Prodavatelj još nije postavio primanje novca.',
    _ => 'Radnja nije uspjela. Osvježi stanje pa pokušaj ponovno.',
  };
}
