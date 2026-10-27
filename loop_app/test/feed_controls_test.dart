import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/screens/auctions_screen.dart';
import 'package:loop_app/screens/for_you_ranker.dart';
import 'package:loop_app/screens/swipe_feed_screen.dart';
import 'package:loop_app/services/feed_preferences.dart';
import 'package:loop_app/services/feed_watch_time.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:loop_app/widgets/feed.dart' show FeedEntry;
import 'package:loop_app/widgets/photo_viewer.dart';

void main() {
  test('covered routes, other tabs and background time are excluded', () {
    var now = DateTime(2026, 10, 27);
    final time = FeedWatchTime(now: () => now);
    time.setVisible(true);
    now = now.add(const Duration(seconds: 2));
    time.setVisible(false);
    now = now.add(const Duration(minutes: 10));
    time.setVisible(false);
    time.setVisible(true);
    now = now.add(const Duration(seconds: 3));
    expect(time.take(), const Duration(seconds: 5));
    expect(time.take(), Duration.zero);
  });

  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
  });
  tearDown(() => Hive.close());

  test('hidden sellers and listings survive reload and stay account scoped', () async {
    final prefs = FeedPreferences()
      ..hide('listing')
      ..hideSeller(SeedData.anaUserId);
    await storage.saveFeedPreferences(SeedData.testUserId, prefs);
    final restored = storage.feedPreferences(SeedData.testUserId);
    expect(restored.hidden, contains('listing'));
    expect(restored.sellers, contains(SeedData.anaUserId));
    expect(storage.feedPreferences(SeedData.demoUserId).hidden, isEmpty);
    expect(storage.feedPreferences(null).sellers, isEmpty);
    await storage.addRecentCategories(['phones']);
    await storage.saveSession(userId: SeedData.demoUserId);
    expect(storage.recentCategories, isEmpty);
  });

  test('seen history has a cooldown and bounded storage', () {
    final prefs = FeedPreferences();
    final now = DateTime(2026, 10, 27);
    for (var i = 0; i < 600; i++) {
      prefs.recordSeen('item-$i', now);
    }
    final restored = FeedPreferences.fromMap(prefs.toMap());
    expect(restored.seen.length, 500);
    expect(restored.seenRecently('item-599', now), isTrue);
    expect(restored.seenRecently('item-599', now.add(const Duration(hours: 25))), isFalse);
    expect(restored.seen.containsKey('item-0'), isFalse);
  });

  test('explicit controls exclude listings and override positive category signals', () {
    final state = AppState.fromStorage(storage);
    final all = browseItems(state);
    final target = all.firstWhere((i) => i.device != null && i.device!.ownerId != SeedData.testUserId);
    final key = ForYouRanker.keyOf(target);
    final prefs = FeedPreferences()..hide(key);
    final ranker = ForYouRanker(state, now: DateTime.now(), preferences: prefs,
      boost: {for (final c in target.categories) c: 6});
    expect(ranker.rank(all, limit: 100).map((p) => ForYouRanker.keyOf(p.item)), isNot(contains(key)));
    prefs.hidden.clear();
    final seller = target.device!.ownerId;
    if (seller != null) {
      prefs.hideSeller(seller);
      expect(ranker.rank(all, limit: 100).any((p) =>
        (p.item.show?.hostId ?? p.item.auction?.sellerId ?? p.item.device?.ownerId) == seller), isFalse);
    }
  });

  testWidgets('horizontal gallery, zoom and details keep the current listing', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final d = await TradeService(storage).addDevice(
      userId: SeedData.anaUserId, name: 'Gallery product', model: 'Test model',
      condition: DeviceCondition.good, price: 40, category: DeviceCategory.values.first,
      // Missing local files intentionally use the image fallback.
      imagePaths: const ['/missing-a.jpg', '/missing-b.jpg'],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [storageProvider.overrideWithValue(storage), tickIntervalProvider.overrideWithValue(null)],
      child: MaterialApp(navigatorObservers: [feedRouteObserver], home: SwipeFeedScreen(
        entries: [FeedEntry.item(d.id)],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('post-gallery')), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-zoom')));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Zatvori'));
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-description')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('post-details')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
