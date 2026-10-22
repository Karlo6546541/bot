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

      // Dodir na opis: cijeli opis i detalji u donjem listu.
      await tester.tap(find.byKey(const ValueKey('post-description')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post-details')), findsOneWidget);
      expect(find.text('Otvori cijeli oglas'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20)); // zatvori list
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post-details')), findsNothing);

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
      await tester.tap(find.byTooltip('Natrag'));
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
      // Filtar kategorija trgovine nastaje sam iz oglasa.
      final cats = find.byKey(const ValueKey('shop-categories'));
      await tester.scrollUntilVisible(
        cats,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final chip = find.descendant(of: cats, matching: find.byType(ChoiceChip));
      expect(chip, findsAtLeastNWidgets(2)); // "Sve" + barem jedna
      await tester.tap(chip.at(1));
      await tester.pumpAndSettle();
      // Ocjene su na svojoj kartici.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('shop-tabs')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ocjene'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rate-shop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.star_outline_rounded).at(3));
      await tester.tap(find.text('Pošalji ocjenu'));
      await tester.pumpAndSettle();
      expect(find.text('Tvoja ocjena: 4★'), findsOneWidget);
    });
  }

  for (final size in const [Size(1400, 1000), Size(400, 860)]) {
    testWidgets('aukcija u swipe feedu: licitiraj i zvono ($size)', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = StorageService();
      await tester.runAsync(() => storage.init(inMemory: true));
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
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('watch-posts')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('watch-posts')));
      await tester.pumpAndSettle();
      final feed = find.byKey(const ValueKey('swipe-feed'));
      for (
        var i = 0;
        i < 60 && find.byKey(const ValueKey('post-bid')).evaluate().isEmpty;
        i++
      ) {
        await tester.fling(feed, const Offset(0, -600), 2000);
        await tester.pumpAndSettle();
      }
      expect(find.text('🔨 AUKCIJA'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('post-watch')));
      await tester.pumpAndSettle();
      expect(
        storage.auctions.any((a) => a.watchers.contains(SeedData.demoUserId)),
        isTrue,
      );
      // Poruka na dnu nestane pa se dodiruje gumb ispod nje.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-bid')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bid-amount')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bid-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Ponuda prihvaćena — vodiš!'), findsOneWidget);
      expect(find.text('Vodiš · automatska ponuda'), findsOneWidget);
    });
  }

  testWidgets('pretraga objava i računa; kupljeno ide u portfolio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = StorageService();
    await tester.runAsync(() => storage.init(inMemory: true));
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

    // Pretraga: objave i računi.
    await tester.tap(find.byKey(const ValueKey('open-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('global-search')),
      'airpods',
    );
    await tester.pumpAndSettle();
    expect(find.text('Objave (1)'), findsOneWidget);
    expect(find.text('AirPods Pro 2'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('global-search')), 'ana');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Računi (1)'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('account-${SeedData.anaUserId}')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Kupnja: predmet nestaje iz Marketa i pojavljuje se u portfoliju.
    await tester.tap(find.text('Market').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'AirPods');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kupi odmah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kupi odmah'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Potvrdi kupnju'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Potvrdi kupnju'));
    await tester.pumpAndSettle();
    expect(find.text('AirPods Pro 2'), findsNothing); // nije više u Marketu
    await tester.tap(find.text('Portfolio').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('AirPods Pro 2'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('AirPods Pro 2'), findsOneWidget);
  });
}
