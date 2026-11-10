import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/config/features.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/auctions_home_screen.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

import 'helpers/vision_navigation.dart';

/// Aplikacija samo za aukcije: bez livea, Kupi odmah i trgovine.
void main() {
  if (kLiveEnabled || kBuyNowEnabled) {
    test('samo aukcije je isključen', () {}, skip: 'LIVE/BUY_NOW uključeni');
    return;
  }
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
    await TradeService(storage).assignPlatformItems();
    await TradeService(storage).autoListPortfolios();
  });
  tearDown(Hive.close);

  Widget app() => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: const LoopApp(),
  );

  testWidgets('Početna je popis aukcija bez livea i trgovine', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(AuctionsHomeScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-view-soon')), findsNothing);
    expect(find.byKey(const ValueKey('home-live-discovery')), findsNothing);
    expect(find.byKey(const ValueKey('home-go-live')), findsNothing);
    // Tab "Završavaju uskoro" se otvara bez greške.
    await tester.tap(find.byKey(const ValueKey('home-view-ending')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Prodaj nudi aukciju, ne live ni Kupi odmah', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await mainTab(tester, 'Prodaj');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('seller-hub-live')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
