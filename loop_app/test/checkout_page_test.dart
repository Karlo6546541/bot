import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/services/delivery_locations.dart';
import 'package:loop_app/services/stripe_backend.dart';
import 'package:loop_app/theme/app_theme.dart';
import 'package:loop_app/widgets/purchase_confirmation.dart';

void main() {
  PurchaseConfirmationSheet sheet({
    bool hasCard = true,
    List<String>? calls,
    String address = 'Preloge 5, 40000 Ivanovec',
  }) => PurchaseConfirmationSheet(
    page: true,
    title: 'Ruth Ozeki',
    subtitle: 'Novo s etiketama',
    recipient: 'Karlo Švenda',
    address: address,
    itemCents: 400,
    shippingCents: 289,
    totalCents: 689,
    loadCard: () async => (hasCard: hasCard, last4: hasCard ? '4242' : null),
    addCard: (_) async {
      calls?.add('addCard');
      return true;
    },
    reserve: () async {
      calls?.add('reserve');
      return {'id': 'order-1', 'total_cents': 400};
    },
    chooseDelivery: (id, DeliveryDestination d) async =>
        calls?.add('delivery:${d.data['address']}'),
    orderTotal: (_) async => 689,
    charge: (id, _) async {
      calls?.add('charge:$id');
      return SavedCardChargeStatus.paid;
    },
  );

  Future<void> open(
    WidgetTester tester,
    PurchaseConfirmationSheet s,
    List<bool> result,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLoopTheme(),
        locale: const Locale('hr'),
        supportedLocales: const [Locale('hr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => result.add(await showCheckoutPage(ctx, s)),
              child: const Text('Kupi odmah'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Kupi odmah'));
    await tester.pumpAndSettle();
  }

  testWidgets('Kupi odmah otvara cijeli ekran Završetak kupnje', (
    tester,
  ) async {
    await open(tester, sheet(), []);
    expect(find.text('Završetak kupnje'), findsOneWidget);
    expect(find.text('Ruth Ozeki'), findsOneWidget);
    expect(find.text('Novo s etiketama'), findsOneWidget);
    expect(find.text('Karlo Švenda'), findsOneWidget);
    expect(find.byKey(const ValueKey('purchase-address-text')), findsOneWidget);
    expect(find.text('Pojedinosti o dostavi'), findsOneWidget);
    expect(find.text('Plaćanje'), findsOneWidget);
    expect(find.textContaining('4242'), findsOneWidget);
    expect(find.text('Sažetak cijene'), findsOneWidget);
    expect(find.byKey(const ValueKey('purchase-protection')), findsOneWidget);
    expect(find.byKey(const ValueKey('purchase-total')), findsOneWidget);
    expect(find.text('Plati'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plati rezervira, bira dostavu, naplaćuje i zatvara ekran', (
    tester,
  ) async {
    final calls = <String>[];
    final result = <bool>[];
    await open(tester, sheet(calls: calls), result);
    await tester.tap(find.byKey(const ValueKey('purchase-pay')));
    await tester.pumpAndSettle();
    expect(calls, [
      'reserve',
      'delivery:Preloge 5, 40000 Ivanovec',
      'charge:order-1',
    ]);
    expect(result, [true]);
    expect(find.text('Završetak kupnje'), findsNothing);
  });

  testWidgets('bez kartice gumb traži karticu, a ne naplaćuje', (tester) async {
    final calls = <String>[];
    await open(tester, sheet(hasCard: false, calls: calls), []);
    expect(find.text('Dodaj karticu'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('purchase-pay')));
    await tester.pumpAndSettle();
    expect(calls, ['addCard']);
    expect(find.text('Završetak kupnje'), findsOneWidget);
  });

  testWidgets('bez adrese ne naplaćuje dok se ne upiše', (tester) async {
    final calls = <String>[];
    await open(tester, sheet(address: '', calls: calls), []);
    expect(find.byKey(const ValueKey('purchase-address')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('purchase-pay')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.byKey(const ValueKey('purchase-error')), findsOneWidget);
  });
}
