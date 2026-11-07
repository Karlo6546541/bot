import 'package:loop_app/config/design_variant.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/providers/my_activity_provider.dart';
import 'package:loop_app/screens/activity_view.dart';
import 'package:loop_app/screens/deliveries_screen.dart';
import 'package:loop_app/screens/seller_finance_screens.dart';
import 'package:loop_app/services/my_activity_backend.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/theme/app_theme.dart';
import 'package:loop_app/widgets/wallet_ticket.dart';
import 'package:loop_app/widgets/purchase_confirmation.dart';
import 'package:loop_app/services/stripe_backend.dart';

void main() {
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
  });
  tearDown(Hive.close);
  Widget app(Widget page, {MyOnlineActivity? online}) => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
      if (online != null)
        myOnlineActivityProvider.overrideWith((_) async => online),
    ],
    child: MaterialApp(theme: buildLoopTheme(), home: page),
  );

  testWidgets(
    'two fingers select ready packages; one finger does not; shipped packages stay excluded',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (var i = 0; i < 3; i++) {
        await storage.putDelivery(
          Delivery(
            id: 'parcel-$i',
            deviceId: 'seed-1',
            deviceName: 'Paket $i',
            buyerId: SeedData.anaUserId,
            sellerId: SeedData.testUserId,
            createdAt: DateTime.now(),
            method: DeliveryMethod.courier,
            destination: 'Ilica 1',
            trackingNumber: 'DEMO-$i',
            startedAt: DateTime.now(),
            handedOverAt: i == 2 ? DateTime.now() : null,
          ),
        );
      }
      await tester.pumpWidget(app(const DeliveryNotesScreen()));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('note-parcel-0'));
      final second = find.byKey(const ValueKey('note-parcel-1'));
      final scroll = find.byKey(const ValueKey('my-notes-list'));
      await tester.drag(scroll, const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ship-bulk')), findsNothing);
      final a = tester.getCenter(first), b = tester.getCenter(second);
      final one = await tester.startGesture(
        a - const Offset(15, 0),
        pointer: 1,
      );
      final two = await tester.startGesture(
        a + const Offset(15, 0),
        pointer: 2,
      );
      await tester.pump();
      await two.moveTo(b + const Offset(15, 0));
      await tester.pump();
      await one.up();
      await two.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('ship-select-parcel-0')),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('ship-select-parcel-1')),
            )
            .value,
        isTrue,
      );
      expect(find.byKey(const ValueKey('ship-select-parcel-2')), findsNothing);
      expect(find.text('Generiraj naljepnice za 2 paketa'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'swipe ledger and monthly peek export real records without changing balances',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await storage.putTransaction(
          LoopTransaction(
            id: 'sale-$i',
            type: TransactionType.sell,
            userId: SeedData.testUserId,
            sellerId: SeedData.testUserId,
            buyerId: SeedData.anaUserId,
            deviceId: 'seed-1',
            deviceName: 'Prodaja $i',
            price: 50,
            fee: 3,
            amount: 47,
            buyerLabel: 'Ana',
            sellerLabel: 'Test',
            createdAt: now.subtract(Duration(minutes: i)),
          ),
        );
      }
      final balance = storage.userById(SeedData.testUserId)!.credits;
      await tester.pumpWidget(app(const FinancialsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fin-tab-ledger')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('fin-transactions')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fin-tab-reports')));
      await tester.pumpAndSettle();
      final month = DateTime(now.year, now.month);
      await tester.longPress(
        find.byKey(ValueKey('fin-month-${month.toIso8601String()}')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fin-month-export')), findsOneWidget);
      String? csv;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            csv = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('fin-month-export')));
      await tester.pumpAndSettle();
      expect(csv, contains('Prodaja 0'));
      expect(csv, contains('47.00'));
      expect(storage.userById(SeedData.testUserId)!.credits, balance);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'vault groups unpaid online orders and never reveals another buyer record',
    (tester) async {
      final online = MyOnlineActivity(
        orders: [
          {
            'id': 'unpaid-1',
            'buyer_id': SeedData.testUserId,
            'seller_id': SeedData.anaUserId,
            'status': 'awaiting_payment',
            'total_cents': 2500,
            'created_at': DateTime.now().toIso8601String(),
            'source_snapshot': {'name': 'Čeka stvarnu naplatu'},
          },
          {
            'id': 'foreign-1',
            'buyer_id': SeedData.markoUserId,
            'seller_id': SeedData.anaUserId,
            'status': 'paid',
            'total_cents': 5000,
            'created_at': DateTime.now().toIso8601String(),
            'source_snapshot': {'name': 'Tuđa kupnja'},
          },
        ],
      );
      await tester.pumpWidget(
        app(const Scaffold(body: ActivityView()), online: online),
      );
      await tester.pumpAndSettle();
      expect(find.text('Čeka stvarnu naplatu'), findsOneWidget);
      expect(find.text('Tuđa kupnja'), findsNothing);
      expect(find.text('Još nema kupnji'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      final ticket = find.byKey(const ValueKey('online-order-unpaid-1'));
      expect(
        find.descendant(
          of: ticket,
          matching: find.byKey(const ValueKey('tracking-dot-0-active')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: ticket, matching: find.byType(CinematicTracking)),
        kSimpleDesign ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'inline payment requires a full slide and reports success without popping the screen',
    (tester) async {
      var charges = 0, confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                const Text('Obavijesti ostaju otvorene'),
                PurchaseConfirmationSheet(
                  embedded: true,
                  title: 'Neplaćena narudžba',
                  totalCents: 2500,
                  address: 'Testna 1, Zagreb',
                  loadCard: () async => (hasCard: true, last4: '4242'),
                  addCard: (_) async => false,
                  reserve: () async => {
                    'id': 'pending-order',
                    'total_cents': 2500,
                  },
                  chooseDelivery: (_, _) async {},
                  charge: (_, _) async {
                    charges++;
                    return SavedCardChargeStatus.paid;
                  },
                  onResult: (paid) => confirmed = paid,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('purchase-slide'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.tap(slider);
      await tester.pumpAndSettle();
      expect(charges, 0);
      final thumb = find.descendant(
        of: slider,
        matching: find.byKey(const ValueKey('vision-slide-thumb')),
      );
      await tester.drag(thumb, Offset(tester.getSize(slider).width - 56, 0));
      await tester.pumpAndSettle();
      expect(charges, 1);
      expect(confirmed, isTrue);
      expect(find.text('Obavijesti ostaju otvorene'), findsOneWidget);
      expect(find.byKey(const ValueKey('purchase-close')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a pending legacy shipment stays at paid and never enters the arrived section',
    (tester) async {
      await storage.putDelivery(
        Delivery(
          id: 'pending-legacy',
          deviceId: 'seed-1',
          deviceName: 'Čeka slanje',
          buyerId: SeedData.testUserId,
          sellerId: SeedData.anaUserId,
          createdAt: DateTime.now(),
        ),
      );
      await tester.pumpWidget(app(const Scaffold(body: ActivityView())));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('activity-section-Čeka slanje')),
        kSimpleDesign ? findsNothing : findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('activity-section-Stiglo')),
        findsNothing,
      );
      if (kSimpleDesign) {
        await tester.tap(
          find.byKey(const ValueKey('delivery-open-pending-legacy')),
        );
        await tester.pumpAndSettle();
      }
      expect(
        tester.widget<CinematicTracking>(find.byType(CinematicTracking)).stage,
        0,
      );
      expect(find.byKey(const ValueKey('tracking-dot-2-active')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
