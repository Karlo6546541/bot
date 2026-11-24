import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/services/payments.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:loop_app/widgets/payment_sheet.dart';

void main() {
  final now = DateTime(2026, 10, 24);

  test('provjera kartice: Luhn, marka, istek, CVC', () {
    expect(luhnValid(TestCards.success), isTrue);
    expect(luhnValid('4242 4242 4242 4241'), isFalse);
    expect(CardBrand.of(TestCards.success), CardBrand.visa);
    expect(CardBrand.of(TestCards.mastercard), CardBrand.mastercard);
    expect(CardBrand.of(TestCards.amex), CardBrand.amex);
    expect(
      TestPayments.validate(TestCards.success, '12/29', '123', now: now),
      isNull,
    );
    expect(
      TestPayments.validate('1234 5678', '12/29', '123', now: now),
      'Broj kartice nije ispravan.',
    );
    expect(
      TestPayments.validate(TestCards.success, '13/29', '123', now: now),
      isNotNull,
    );
    // Vrijedi do kraja mjeseca isteka.
    expect(
      TestPayments.validate(TestCards.success, '10/26', '123', now: now),
      isNull,
    );
    expect(
      TestPayments.validate(TestCards.success, '09/26', '123', now: now),
      'Kartica je istekla.',
    );
    expect(
      TestPayments.validate(TestCards.amex, '12/29', '123', now: now),
      isNotNull,
    );
    expect(
      TestPayments.validate(TestCards.amex, '12/29', '1234', now: now),
      isNull,
    );
  });

  test('tokenizacija vraća samo oznaku; testne odbijene kartice', () {
    expect(
      TestPayments.tokenize(TestCards.success, '12/29', '123', now: now),
      'Visa •••• 4242',
    );
    expect(
      TestPayments.tokenize(TestCards.mastercard, '12/29', '123', now: now),
      'Mastercard •••• 4444',
    );
    expect(
      () => TestPayments.tokenize(TestCards.declined, '12/29', '123', now: now),
      throwsA(isA<TradeException>()),
    );
    expect(
      () => TestPayments.tokenize(
        TestCards.insufficient,
        '12/29',
        '123',
        now: now,
      ),
      throwsA(isA<TradeException>()),
    );
    expect(
      TestPayments.wallet(WalletKind.googlePay),
      'Google Pay · Visa •••• 4242',
    );
  });

  testWidgets('Google Pay i Apple Pay (testni novčanik)', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await addPaymentMethod(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    for (final (key, label) in [
      ('pay-google', 'Google Pay · Visa •••• 4242'),
      ('pay-apple', 'Apple Pay · Visa •••• 4242'),
    ]) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wallet-confirm')));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(result, label);
    }
  });
}
