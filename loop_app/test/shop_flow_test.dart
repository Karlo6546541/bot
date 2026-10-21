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
import 'package:loop_app/widgets/shop_widgets.dart';

/// Feed objava (swipe kao TikTok), trgovine, praćenje, ocjena i dijeljenje.
void main() {
  for (final size in const [Size(1400, 1000), Size(400, 860)]) {
    testWidgets('objave → swipe → lajk, prati, ponuda → trgovina ($size)', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      debugForceShareSheet = true;
      addTearDown(() => debugForceShareSheet = false);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final storage = StorageService();
      await tester.runAsync(() async {
        await storage.init(inMemory: true);
        final trade = TradeService(storage);
        final lamp = await trade.addDevice(
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

      // Nema više LOOP Marketa: svi predmeti imaju prodavatelja.
      expect(storage.devices.where((d) => d.ownerId == null), isEmpty);

      // Početna: gumb za objave i trgovine za tebe.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('watch-posts')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Trgovine za tebe'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('watch-posts')));
      await tester.pumpAndSettle();

      // Swipe feed: listaj dok se ne pojavi lampa.
      final feed = find.byKey(const ValueKey('swipe-feed'));
      expect(feed, findsOneWidget);
      for (
        var i = 0;
        i < 60 && find.text('Stolna lampa · Mjed').evaluate().isEmpty;
        i++
      ) {
        await tester.fling(feed, const Offset(0, -600), 2000);
        await tester.pumpAndSettle();
      }
      expect(find.text('Stolna lampa · Mjed'), findsOneWidget);
      // Cijena za kupca: 90 € + 2% = 91,80 €, prekrižena 102 €.
      expect(find.text('91,80 €'), findsOneWidget);
      expect(find.text('102 €'), findsOneWidget);
      expect(find.textContaining('aknad'), findsNothing);

      // Lajk, prati, ponuda cijene.
      await tester.tap(find.byKey(const ValueKey('post-like')));
      await tester.pumpAndSettle();
      expect(storage.userById(SeedData.demoUserId)!.favorites, isNotEmpty);
      await tester.tap(find.byKey(const ValueKey('post-follow')));
      await tester.pumpAndSettle();
      expect(
        storage.userById(SeedData.demoUserId)!.following,
        contains(SeedData.testUserId),
      );
      await tester.tap(find.byKey(const ValueKey('post-offer')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('amount-field')),
        '71,40',
      );
      await tester.tap(find.byKey(const ValueKey('amount-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Ponuda je poslana prodavatelju'), findsOneWidget);
      // Prodavatelj vidi iznos bez naknade (71,40 / 1,02 = 70).
      expect(storage.bargains.single.amount, 70);
      expect(storage.viewsOf(storage.bargains.single.deviceId), 1);

      // Dijeljenje: izbornik s aplikacijama.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-share')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('share-WhatsApp')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-Viber')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-SMS')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('share-copy')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Trgovina @test: pratitelji, ocjena trgovine.
      await tester.tap(find.text('Market').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shops-chip')));
      await tester.pumpAndSettle();
      expect(find.text('Trgovine'), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('shop-${SeedData.testUserId}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stat-followers')));
      await tester.pumpAndSettle();
      expect(find.text('Pratitelji (1)'), findsOneWidget);
      expect(find.text('@demo · 0 pratitelja'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rate-shop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.star_outline_rounded).at(3));
      await tester.tap(find.text('Pošalji ocjenu'));
      await tester.pumpAndSettle();
      expect(find.text('Tvoja ocjena: 4★'), findsOneWidget);
    });
  }
}
