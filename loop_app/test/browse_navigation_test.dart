import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/for_you_feed.dart';
import 'package:loop_app/screens/swipe_feed_screen.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
    final trade = TradeService(storage);
    await trade.assignPlatformItems();
    await trade.autoListPortfolios();
  });
  tearDown(() => Hive.close());

  Widget app() => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: const LoopApp(),
  );

  testWidgets('browse menu opens categories, auctions and digital shopping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('home-categories-shortcut')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('home-auctions-shortcut')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-cat-categories')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('categories')), findsOneWidget);
    await tester.tap(find.byTooltip('Natrag'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-cat-timed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-ending')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('auction-category-filter')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('home-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-cat-digital')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-digital')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-ending')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('live category selection filters only live streams and clears', (
    tester,
  ) async {
    final ids = await tester.runAsync(() async {
      final live = LiveService(storage);
      final a = await live.create(
        hostId: SeedData.anaUserId,
        title: 'Konzole uživo',
        category: DeviceCategory.console.name,
      );
      final b = await live.create(
        hostId: SeedData.markoUserId,
        title: 'Knjige uživo',
        category: DeviceCategory.books.name,
      );
      return [a.id, b.id];
    });
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-cat-live')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('browse-live-${ids![0]}')), findsOneWidget);
    expect(find.byKey(ValueKey('browse-live-${ids[1]}')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-category-filter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('live-category-console')),
    );
    await tester.tap(find.byKey(const ValueKey('live-category-console')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('browse-live-${ids[0]}')), findsOneWidget);
    expect(find.byKey(ValueKey('browse-live-${ids[1]}')), findsNothing);
    expect(find.byKey(const ValueKey('home-ending')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('live-category-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-category-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('browse-live-${ids[1]}')), findsOneWidget);
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('browse-live-${ids[0]}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-compact-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-chat')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-chat')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-reaction-🔥')), findsNothing);
    expect(tester.getBottomLeft(find.byKey(const ValueKey('live-chat'))).dy, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'feed keeps its queue and controller stable during a drag and sync',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final feed = find.byType(ForYouFeed);
      final swipe = find.byKey(const ValueKey('for-you-feed'));
      final initial = tester.widget<SwipeFeedScreen>(swipe).entries;
      final pages = find.byKey(const ValueKey('swipe-feed'));
      final controller = tester.widget<PageView>(pages).controller;
      final point = tester.getCenter(pages);
      final gesture = await tester.startGesture(point);
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => TradeService(storage).addDevice(
          userId: SeedData.anaUserId,
          name: 'Novi sinkronizirani oglas',
          model: '',
          condition: DeviceCondition.good,
          price: 35,
          category: DeviceCategory.console,
        ),
      );
      final container = ProviderScope.containerOf(tester.element(feed));
      await container
          .read(appProvider.notifier)
          .toggleFollow(SeedData.anaUserId);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<SwipeFeedScreen>(swipe).entries.length,
        initial.length,
      );
      expect(tester.widget<PageView>(pages).controller, same(controller));
      await gesture.moveBy(const Offset(0, -350));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.widget<PageView>(pages).controller, same(controller));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
