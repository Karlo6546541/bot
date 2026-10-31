import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/models/country.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/widgets/delivery_picker.dart';

void main() {
  testWidgets('GLS paketomat s popisa', (tester) async {
    final hr = countryOf('HR');
    final gls = hr.carriers.firstWhere((c) => c.id == 'hr-gls-locker');
    DeliveryChoice? last;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DeliveryPicker(
              options: [
                DeliveryOption(
                  DeliveryMethod.parcelLocker,
                  carrier: gls,
                  to: hr,
                ),
                const DeliveryOption(DeliveryMethod.pickup),
              ],
              onChanged: (c) => last = c,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('delivery-hr-gls-locker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('locker-tile')), findsOneWidget);
    expect(last!.destination, startsWith('GLS #'));
    await tester.tap(find.byKey(const ValueKey('boxnow-list')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('locker-search')),
      'Split',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Split').last);
    await tester.pumpAndSettle();
    expect(last!.destination, contains('Split'));
    expect(
      DeliveryService.validate(last!.method, last!.destination, carrier: gls),
      isNull,
    );
  });
}
