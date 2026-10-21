import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

/// Feed na početnoj, popust, ponuda cijene i praćenje kroz sučelje.
void main() {
  for (final size in const [Size(1400, 1000), Size(400, 860)]) {
    testWidgets('feed → oglas na popustu → ponuda cijene → prati ($size)', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final storage = StorageService();
      late Device lamp;
      await tester.runAsync(() async {
        await storage.init(inMemory: true);
        final trade = TradeService(storage);
        lamp = await trade.addDevice(
          userId: SeedData.testUserId,
          name: 'Stolna lampa',
          model: 'Mjed',
          condition: DeviceCondition.good,
          price: 100,
          category: DeviceCategory.values.firstWhere(
            (c) => c.section != ItemSection.digital,
          ),
          quantity: 2,
        );
        await trade.setDiscount(
          userId: SeedData.testUserId,
          deviceId: lamp.id,
          percent: 10,
        );
      });
      addTearDown(() => tester.runAsync(Hive.close));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            tickIntervalProvider.overrideWithValue(null),
          ],
          child: const LoopApp(),
        ),
      );
      await tester.ensureVisible(find.text('Prijavi se'));
      await tester.tap(find.text('Prijavi se'));
      await tester.pumpAndSettle();

      // Početna: "Za tebe" s oglasom na popustu.
      expect(find.text('Za tebe'), findsOneWidget);
      final card = find.descendant(
        of: find.byKey(const ValueKey('home-feed')),
        matching: find.text('Stolna lampa'),
      );
      expect(card, findsOneWidget);
      expect(find.text('−10% popust'), findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();

      // Detalji: cijena s popustom i prekrižena redovna.
      expect(find.text('90 €'), findsWidgets);
      expect(find.text('100 €'), findsWidgets);

      // Ponuda cijene.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('make-offer')),
        200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('make-offer')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('amount-field')), '70');
      await tester.tap(find.byKey(const ValueKey('amount-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Ponuda je poslana prodavatelju'), findsOneWidget);
      expect(
        find.text('⏳ Ponudio si 70 € — čeka se odgovor prodavatelja.'),
        findsOneWidget,
      );
      expect(storage.bargains.single.amount, 70);

      // Prati prodavatelja.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('follow')),
        -200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('follow')));
      await tester.pumpAndSettle();
      expect(find.text('Pratiš'), findsOneWidget);
      expect(
        storage.userById(SeedData.demoUserId)!.following,
        contains(SeedData.testUserId),
      );
    });
  }
}
