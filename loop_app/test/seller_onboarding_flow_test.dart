import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/seller_info.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/seller_screens.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/sync_service.dart';
import 'sync_service_test.dart' show FakeRemote;

void main() {
  late StorageService storage;
  final info = SellerInfo(
    legalName: 'Test Seller',
    oib: '12345678903',
    address: 'Ulica 1, 10000 Zagreb',
    iban: 'HR1723600001101234565',
    birthDate: DateTime(1990, 1, 1),
    updatedAt: DateTime(2026),
  );
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
    await storage.putUser(
      storage.userById(SeedData.testUserId)!.copyWith(seller: info),
    );
  });
  tearDown(Hive.close);
  testWidgets(
    'double save waits for cloud persistence and prepares only once',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final remote = FakeRemote();
      for (final table in storage.exportAll().entries) {
        remote.data[table.key] = Map.of(table.value);
      }
      final sync = SyncService(storage, remote);
      await sync.start();
      remote.writeGate = Completer<void>();
      var preparations = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            syncProvider.overrideWithValue(sync),
            tickIntervalProvider.overrideWithValue(null),
            sellerPreparationProvider.overrideWithValue((_, _) async {
              preparations++;
              return false;
            }),
            sellerOnboardingProvider.overrideWithValue(
              (_, _) async => throw StateError('Unexpected redirect'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => SellerInfoScreen.open(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('seller-save')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('seller-save')));
      await tester.pump();
      expect(find.byType(SellerInfoScreen), findsOneWidget);
      expect(preparations, 0);
      remote.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SellerInfoScreen), findsNothing);
      expect(preparations, 1);
      expect(sync.hasPendingRecord('sellers', SeedData.testUserId), false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(sync.dispose);
    },
  );

  testWidgets(
    'invalid seller details stay editable and cannot replace the saved profile',
    (tester) async {
      var preparations = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            tickIntervalProvider.overrideWithValue(null),
            sellerPreparationProvider.overrideWithValue((_, _) async {
              preparations++;
              return true;
            }),
          ],
          child: MaterialApp(home: const SellerInfoScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('seller-oib')), '1234');
      await tester.tap(find.byKey(const ValueKey('seller-save')));
      await tester.pumpAndSettle();
      expect(find.text('OIB nije ispravan (11 znamenki).'), findsOneWidget);
      expect(storage.userById(SeedData.testUserId)!.seller!.oib, info.oib);
      expect(preparations, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saving prepares the seller account without opening Stripe', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
          sellerPreparationProvider.overrideWithValue((seller, country) async {
            calls++;
            expect(seller.legalName, 'Test Seller');
            expect(country, 'HR');
            return true;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => SellerInfoScreen.open(ctx),
                child: const Text('Open seller form'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open seller form'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('seller-save')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('seller-save')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(SellerInfoScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'existing seller publishes and goes live without Stripe; payouts ask for it',
    (tester) async {
      bool? ready, payouts;
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            tickIntervalProvider.overrideWithValue(null),
            sellerOnboardingProvider.overrideWithValue((seller, country) async {
              calls++;
              return false;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Column(
                  children: [
                    TextButton(
                      onPressed: () async {
                        ready = await ensureSellerInfo(ctx);
                      },
                      child: const Text('Sell'),
                    ),
                    TextButton(
                      onPressed: () async {
                        payouts = await ensurePayoutsReady(ctx);
                      },
                      child: const Text('Payout'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sell'));
      await tester.pumpAndSettle();
      // Objava i live ne otvaraju Stripe.
      expect(calls, 0);
      expect(ready, isTrue);
      await tester.tap(find.text('Payout'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(payouts, isFalse);
      expect(find.byType(SellerInfoScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Stripe unavailable: details are saved but payment readiness stays false',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bool? ready;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            tickIntervalProvider.overrideWithValue(null),
            sellerOnboardingProvider.overrideWithValue(
              (seller, country) async =>
                  throw StateError('PAYMENTS_UNAVAILABLE'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Column(
                  children: [
                    TextButton(
                      onPressed: () => SellerInfoScreen.open(ctx),
                      child: const Text('Open seller form'),
                    ),
                    TextButton(
                      onPressed: () async {
                        ready = await ensurePayoutsReady(ctx);
                      },
                      child: const Text('Sell'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open seller form'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('seller-save')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('seller-save')));
      await tester.pumpAndSettle();
      expect(find.byType(SellerInfoScreen), findsNothing);
      expect(find.textContaining('Radnja nije uspjela'), findsNothing);
      await tester.tap(find.text('Sell'));
      await tester.pumpAndSettle();
      expect(ready, isFalse);
      expect(
        storage.userById(SeedData.testUserId)!.seller!.legalName,
        'Test Seller',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
