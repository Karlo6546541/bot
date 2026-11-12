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

void main() {
  if (kLiveEnabled || !kBuyNowEnabled) {
    test('Početna: aukcije i Kupi odmah', () {}, skip: 'zastavice');
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

  testWidgets('Početna miješa aukcije i Kupi odmah; filter Kupi odmah', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
        ],
        child: const LoopApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-format-buynow')), findsOneWidget);
    expect(find.byType(AuctionTile), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('home-format-buynow')));
    await tester.pumpAndSettle();
    expect(find.byType(AuctionTile), findsNothing);
    expect(find.byType(BuyNowTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
