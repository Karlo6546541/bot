import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loop_app/services/stripe_backend.dart';
import 'package:loop_app/services/delivery_locations.dart';
import 'package:loop_app/widgets/purchase_confirmation.dart';

class _Pages extends NavigatorObserver {
  int pagePushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) pagePushes++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    PurchaseConfirmationSheet sheet, {
    ValueChanged<bool>? onResult,
    _Pages? observer,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [?observer],
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Column(
              children: [
                const Text('Izvorni oglas'),
                TextButton(
                  onPressed: () async {
                    final paid = await showPurchaseConfirmation(ctx, sheet);
                    onResult?.call(paid);
                  },
                  child: const Text('Kupi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Kupi'));
    await tester.pumpAndSettle();
  }

  PurchaseConfirmationSheet sheet({
    Future<Map<String, dynamic>> Function()? reserve,
    Future<SavedCardChargeStatus> Function(String, BuildContext)? charge,
    Future<void> Function(String, DeliveryDestination)? delivery,
    String address = 'Testna ulica 1, Zagreb',
    Future<List<DeliveryLocation>> Function(String)? search,
  }) => PurchaseConfirmationSheet(
    title: 'Testni predmet',
    totalCents: 6600,
    address: address,
    searchLockers: search,
    loadCard: () async => (hasCard: true, last4: '4242'),
    addCard: (_) async => false,
    reserve: reserve ?? () async => {'id': 'order-one', 'total_cents': 6600},
    chooseDelivery: delivery ?? (_, _) async {},
    charge: charge ?? (_, _) async => SavedCardChargeStatus.paid,
  );

  testWidgets(
    'purchase is a compact popup over the item, without an orders page',
    (tester) async {
      var reserves = 0, charges = 0;
      final observer = _Pages();
      await open(
        tester,
        sheet(
          reserve: () async {
            reserves++;
            return {'id': 'one', 'total_cents': 6600};
          },
          charge: (_, _) async {
            charges++;
            return SavedCardChargeStatus.paid;
          },
        ),
        observer: observer,
      );
      expect(
        find.byKey(const ValueKey('purchase-confirmation')),
        findsOneWidget,
      );
      expect(find.text('Potvrdi kupnju'), findsOneWidget);
      expect(find.textContaining('4242'), findsOneWidget);
      expect(find.text('Narudžbe'), findsNothing);
      expect(find.textContaining('Stripe račun prodavatelja'), findsNothing);
      expect(observer.pagePushes, 1);
      await tester.tap(find.byKey(const ValueKey('purchase-close')));
      await tester.pumpAndSettle();
      expect(reserves, 0);
      expect(charges, 0);
      expect(find.text('Izvorni oglas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmation selects saved delivery and closes only after paid',
    (tester) async {
      final payment = Completer<SavedCardChargeStatus>();
      final calls = <String>[];
      bool? result;
      await open(
        tester,
        sheet(
          reserve: () async {
            calls.add('reserve');
            return {'id': 'one', 'total_cents': 6600};
          },
          delivery: (id, address) async {
            calls.add('shipping:$id:${address.address}');
          },
          charge: (id, _) {
            calls.add('charge:$id');
            return payment.future;
          },
        ),
        onResult: (paid) => result = paid,
      );
      await tester.tap(find.byKey(const ValueKey('purchase-pay')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('purchase-pay')));
      await tester.pump();
      expect(calls, [
        'reserve',
        'shipping:one:Testna ulica 1, Zagreb',
        'charge:one',
      ]);
      expect(result, isNull);
      payment.complete(SavedCardChargeStatus.paid);
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.byKey(const ValueKey('purchase-confirmation')), findsNothing);
      expect(find.text('Izvorni oglas'), findsOneWidget);
    },
  );

  testWidgets(
    'processing is not reported as paid and retries reuse the order',
    (tester) async {
      var reserves = 0, charges = 0;
      bool? result;
      await open(
        tester,
        sheet(
          reserve: () async {
            reserves++;
            return {'id': 'stable-order', 'total_cents': 6600};
          },
          charge: (id, _) async {
            expect(id, 'stable-order');
            charges++;
            return charges == 1
                ? SavedCardChargeStatus.processing
                : SavedCardChargeStatus.paid;
          },
        ),
        onResult: (paid) => result = paid,
      );
      await tester.tap(find.byKey(const ValueKey('purchase-pay')));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Provjeri plaćanje'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('purchase-pay')));
      await tester.pumpAndSettle();
      expect(reserves, 1);
      expect(charges, 2);
      expect(result, isTrue);
    },
  );

  testWidgets(
    'seller readiness failure stays inside the popup with a clear reason',
    (tester) async {
      await open(
        tester,
        sheet(
          charge: (_, _) async => throw FunctionException(
            status: 409,
            details: {'error': 'SELLER_NOT_READY'},
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('purchase-pay')));
      await tester.pumpAndSettle();
      expect(
        find.text('Prodavatelj ovog oglasa još nije omogućio plaćanje.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('purchase-confirmation')),
        findsOneWidget,
      );
      expect(find.text('Narudžbe'), findsNothing);
    },
  );

  testWidgets(
    'a changed server price requires confirmation again before charging',
    (tester) async {
      var charges = 0;
      await open(
        tester,
        sheet(
          reserve: () async => {'id': 'changed', 'total_cents': 7500},
          charge: (_, _) async {
            charges++;
            return SavedCardChargeStatus.paid;
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('purchase-pay')));
      await tester.pumpAndSettle();
      expect(charges, 0);
      expect(
        find.text('Cijena je promijenjena. Potvrdi novi ukupan iznos.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('purchase-pay')));
      await tester.pumpAndSettle();
      expect(charges, 1);
    },
  );

  testWidgets('missing delivery stays inline and cannot start a payment', (
    tester,
  ) async {
    var reserves = 0;
    await open(
      tester,
      sheet(
        address: '',
        reserve: () async {
          reserves++;
          return {'id': 'one', 'total_cents': 6600};
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('purchase-pay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('purchase-address')), findsOneWidget);
    expect(find.text('Upiši adresu za dostavu.'), findsOneWidget);
    expect(reserves, 0);
  });

  testWidgets(
    'locker is chosen from database results and charged only after confirmation',
    (tester) async {
      var charges = 0;
      DeliveryDestination? selected;
      const locker = DeliveryLocation(
        id: 'boxnow:HR:1692',
        name: 'BOX NOW Dubec',
        address: 'Zagrebačka cesta 162b',
        postalCode: '10360',
        city: 'Sesvete',
        country: 'HR',
      );
      await open(
        tester,
        sheet(
          search: (address) async {
            expect(address, 'Testna ulica 1, Zagreb');
            return [locker];
          },
          delivery: (_, destination) async {
            selected = destination;
          },
          charge: (_, _) async {
            charges++;
            return SavedCardChargeStatus.paid;
          },
        ),
      );
      await tester.tap(find.text('Paketomat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('purchase-pay')));
      await tester.pumpAndSettle();
      expect(find.text('Odaberi paketomat za dostavu.'), findsOneWidget);
      expect(charges, 0);
      await tester.tap(find.text('Odaberi paketomat').first);
      await tester.pumpAndSettle();
      expect(find.text('ID paketomata'), findsNothing);
      await tester.tap(find.text('BOX NOW Dubec'));
      await tester.pumpAndSettle();
      expect(charges, 0);
      await tester.tap(find.byKey(const ValueKey('purchase-pay')));
      await tester.pumpAndSettle();
      expect(selected?.method, 'boxnow');
      expect(selected?.data, {'locker_id': 'boxnow:HR:1692'});
      expect(charges, 1);
    },
  );
}
