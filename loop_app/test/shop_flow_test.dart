import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';

/// Swipe feed aukcija (kao TikTok) i pretraga.
void main() {
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
      // Aukcije → kartica otvara swipe feed (kao TikTok).
      await tester.tap(find.text('Istraži').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Polaroid SX-70'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('swipe-feed')), findsOneWidget);
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

  testWidgets('pretraga aukcija i računa', (tester) async {
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

    await tester.tap(find.byKey(const ValueKey('open-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('global-search')),
      'polaroid',
    );
    await tester.pumpAndSettle();
    expect(find.text('Aukcije (1)'), findsOneWidget);
    expect(find.text('Polaroid SX-70'), findsOneWidget);
    // Oglasi iz Marketa se više ne pretražuju.
    await tester.enterText(
      find.byKey(const ValueKey('global-search')),
      'airpods',
    );
    await tester.pumpAndSettle();
    expect(find.text('Aukcije (0)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('global-search')), 'ana');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Računi (1)'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('account-${SeedData.anaUserId}')),
      findsOneWidget,
    );
  });
}
