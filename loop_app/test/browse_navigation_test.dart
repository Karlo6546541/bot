import 'helpers/vision_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/config/features.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/for_you_feed.dart';
import 'package:loop_app/screens/deliveries_screen.dart';
import 'package:loop_app/screens/swipe_feed_screen.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

Future<void> openLiveBrowse(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('home-filters')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('home-cat-live')));
  await tester.pumpAndSettle();
}

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

  testWidgets('seller navigation opens hub with live and auction actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('seller-hub-live')), findsOneWidget);
    expect(find.byKey(const ValueKey('seller-hub-auction')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('hub-health')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('hub-health')));
    expect(find.byKey(const ValueKey('hub-health')), findsOneWidget);
    tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('seller-hub-shipments')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('seller-hub-shipments')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('seller-hub-shipments')));
    await tester.pumpAndSettle();
    expect(find.byType(DeliveryNotesScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-filter-all')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !kLiveEnabled);

  testWidgets('browse menu opens categories, auctions and digital shopping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // Mobitel: Pozornica · Kategorije · Studio · Trezor.
    expect(find.byType(NavigationDestination), findsNWidgets(4));
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
    await mainTab(tester, 'Moje');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('activity-tab-purchases')),
      findsOneWidget,
    );
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    await mainTab(tester, 'Profil');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vault-account')), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !kBuyNowEnabled);

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
    await openLiveBrowse(tester);
    expect(find.byKey(ValueKey('browse-live-${ids![0]}')), findsOneWidget);
    expect(find.byKey(ValueKey('browse-live-${ids[1]}')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-category-filter')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('live-category-console')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('live-category-console')),
    );
    await tester.pumpAndSettle();
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
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('live-chat'))).dy,
      lessThanOrEqualTo(320),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !kLiveEnabled);

  testWidgets(
    'feed keeps its queue and controller stable during a drag and sync',
    (tester) async {
      // Feed se više ne prikazuje na početnoj (ona je mreža), pa ga
      // testiramo samog.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            tickIntervalProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ForYouFeed(active: true)),
          ),
        ),
      );
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
