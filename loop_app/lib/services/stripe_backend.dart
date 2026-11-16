import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/mini_live.dart' show rootNavigatorKey;
import '../widgets/stripe_onboarding/stripe_onboarding.dart';
import '../widgets/stripe_payment/stripe_payment.dart';
import '../models/seller_info.dart';

enum SavedCardChargeStatus { paid, processing, incomplete }

class StripeBackend {
  StripeBackend(this.client, {this.sellerOnboarding});

  /// Otvara ugrađenu potvrdu prodavača (zamjenjivo u testovima). Zadano:
  /// Stripe Connect komponenta u prozoru unutar aplikacije.
  final Future<bool> Function(Map<String, dynamic> session)? sellerOnboarding;
  final SupabaseClient client;

  Map<String, dynamic> _publicProfile(SellerInfo seller) => seller.toMap()
    ..remove('iban')
    ..remove('oib')
    ..remove('vatId')
    ..remove('registryNumber');

  /// Priprema račun prodavača; ako Stripe još traži potvrdu (identitet,
  /// IBAN), otvara je UNUTAR aplikacije i zatim ponovno provjerava stanje.
  /// Nikad ne otvara Stripeovu stranicu ni Dashboard.
  Future<bool> ensureSellerReady(
    SellerInfo seller, {
    required String country,
    String? expectedUserId,
  }) async {
    final data = await _call('stripe-connect', {
      'action': 'session',
      'seller': _publicProfile(seller),
      'country': country,
      'expectedUserId': ?expectedUserId,
    });
    if (data['ready'] == true) return true;
    final secret = data['clientSecret'];
    final key = data['publishableKey'];
    if (secret is! String ||
        secret.isEmpty ||
        key is! String ||
        !key.startsWith('pk_')) {
      throw StateError('PAYMENTS_UNAVAILABLE');
    }
    final session = {'clientSecret': secret, 'publishableKey': key};
    final open = sellerOnboarding;
    if (open != null) {
      if (!await open(session)) return false;
    } else {
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) {
        throw StateError('PAYMENT_PAGE_UNAVAILABLE');
      }
      if (!await showStripeOnboarding(context, session)) return false;
    }
    return prepareSeller(
      seller,
      country: country,
      expectedUserId: expectedUserId,
    );
  }

  /// Prepare the account without leaving the app or accepting any terms.
  Future<bool> prepareSeller(
    SellerInfo seller, {
    required String country,
    String? expectedUserId,
  }) async {
    final data = await _call('stripe-connect', {
      'action': 'prepare',
      'seller': _publicProfile(seller),
      'country': country,
      'expectedUserId': ?expectedUserId,
    });
    return data['ready'] == true;
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> body,
  ) async {
    final result = await client.functions
        .invoke(name, body: body)
        .timeout(const Duration(seconds: 30));
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

  Future<bool> charge(String order, {BuildContext? context}) async =>
      await chargeStatus(order, context: context) == SavedCardChargeStatus.paid;

  Future<SavedCardChargeStatus> chargeStatus(
    String order, {
    BuildContext? context,
  }) async {
    var data = await _call('stripe-charge', {
      'orderId': order,
      'action': 'resume',
    });
    if (data['status'] == 'requires_action' &&
        context != null &&
        context.mounted) {
      if (!await showStripePayment(context, data)) {
        return SavedCardChargeStatus.incomplete;
      }
      data = await _call('stripe-charge', {
        'orderId': order,
        'action': 'resume',
      });
    }
    return switch (data['status']) {
      'paid' => SavedCardChargeStatus.paid,
      'processing' => SavedCardChargeStatus.processing,
      'requires_action' => SavedCardChargeStatus.incomplete,
      _ => throw StateError('PAYMENTS_UNAVAILABLE'),
    };
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

/// Server je jasno odbio naplatu (novac sigurno nije skinut): sljedeći
/// pokušaj je nova naplata, a ne "Provjeri plaćanje".
bool paymentClearlyRejected(Object error) {
  final code = error is FunctionException && error.details is Map
      ? (error.details as Map)['error']
      : null;
  return const {
    'SELLER_NOT_READY',
    'CARD_REQUIRED',
    'CARD_DECLINED',
    'SHIPPING_REQUIRED',
    'ORDER_NOT_PAYABLE',
    'AUTH_REQUIRED',
  }.contains(code);
}

String paymentActionErrorMessage(Object error) {
  if (error is TimeoutException) {
    return 'Provjera plaćanja traje dulje. Provjeri status prije ponovnog pokušaja.';
  }
  if (error is PostgrestException) {
    return switch (error.message) {
      'LOCKER_UNAVAILABLE' =>
        'Odabrani paketomat više nije dostupan. Odaberi drugi ili kurira.',
      'ADDRESS_REQUIRED' => 'Upiši adresu za dostavu.',
      'ORDER_LOCKED' => 'Dostavu ove narudžbe više nije moguće mijenjati.',
      'UNAVAILABLE' => 'Predmet više nije dostupan za kupnju.',
      'INVALID_AMOUNT' => 'Cijena predmeta nije valjana za plaćanje.',
      'AUTH_REQUIRED' => 'Prijavi se ponovno za nastavak.',
      _ => 'Kupnju nije moguće pripremiti. Pokušaj ponovno.',
    };
  }
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
    'SHIPPING_REQUIRED' => 'Dodaj podatke za dostavu.',
    'SELLER_NOT_READY' => 'Prodavatelj ovog oglasa još nije omogućio plaćanje.',
    _ => 'Radnja nije uspjela. Osvježi stanje pa pokušaj ponovno.',
  };
}
