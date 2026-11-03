import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/seller_info.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/seller_screens.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';

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
    'saving the existing seller form automatically starts onboarding before any sale',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            tickIntervalProvider.overrideWithValue(null),
            sellerOnboardingProvider.overrideWithValue((seller, country) async {
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
      await tester.scrollUntilVisible(find.byKey(const ValueKey('seller-save')), 250, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.byKey(const ValueKey('seller-save')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(SellerInfoScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'an existing incomplete seller is onboarded automatically and cannot publish yet',
    (tester) async {
      bool? ready;
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
                builder: (ctx) => TextButton(
                  onPressed: () async {
                    ready = await ensureSellerInfo(ctx);
                  },
                  child: const Text('Sell'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sell'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(ready, false);
      expect(find.byType(SellerInfoScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
