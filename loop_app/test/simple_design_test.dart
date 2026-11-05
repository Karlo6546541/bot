import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/config/design_variant.dart';
import 'package:loop_app/models/auction.dart';
import 'package:loop_app/models/price_offer.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/activity_view.dart';
import 'package:loop_app/screens/public_profile_screen.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'helpers/vision_navigation.dart';

void main() {
  if (!kSimpleDesign) {
    test(
      'the simplified design is opt-in',
      () => expect(kSimpleDesign, isFalse),
    );
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
  Widget app({Widget? home}) => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: home == null
        ? const LoopApp()
        : MaterialApp(home: Scaffold(body: home)),
  );

  testWidgets(
    'reference home keeps all four destinations and discovery routes accessible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(ValueKey('simple-nav-$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('home-shop-discovery')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-shops')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-inline-search')), findsOneWidget);
      await mainTab(tester, 'Moje');
      expect(
        find.byKey(const ValueKey('activity-tab-purchases')),
        findsOneWidget,
      );
      await mainTab(tester, 'Početna');
      expect(find.text('Tenisice'), findsOneWidget);
      expect(find.byKey(const ValueKey('messages-button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-filters')));
      await tester.pumpAndSettle();
      for (final id in [
        'following',
        'soon',
        'categories',
        'timed',
        'digital',
      ]) {
        expect(find.byKey(ValueKey('home-cat-$id')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('home-cat-following')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-following-empty')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('home searches a real shop and opens that seller profile', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final shops = find.byWidgetPredicate(
      (widget) =>
          widget is InkWell &&
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith('home-shop-'),
    );
    expect(shops, findsWidgets);
    final key = tester.widget<InkWell>(shops.first).key! as ValueKey<String>;
    final owner = storage.userById(key.value.substring('home-shop-'.length))!;
    await tester.enterText(
      find.byKey(const ValueKey('home-inline-search')),
      owner.username,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(key), findsOneWidget);
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PublicProfileScreen>(find.byType(PublicProfileScreen))
          .userId,
      owner.id,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'bids and negotiated offers remain reachable as separate activity sections',
    (tester) async {
      final auction = storage.auctions.firstWhere(
        (a) => a.sellerId != SeedData.testUserId,
      );
      await storage.putAuction(
        auction.copyWith(
          endsAt: DateTime.now().add(const Duration(hours: 1)),
          bids: [
            Bid(
              userId: SeedData.testUserId,
              userLabel: 'Test',
              amount: 75,
              time: DateTime.now(),
            ),
          ],
        ),
      );
      await storage.putBargain(
        PriceOffer(
          id: 'simple-offer',
          deviceId: 'seed-1',
          deviceName: 'Ponuda za telefon',
          buyerId: SeedData.testUserId,
          sellerId: SeedData.anaUserId,
          amount: 25,
          listPrice: 30,
          createdAt: DateTime.now(),
          status: BargainStatus.accepted,
          validUntil: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      await tester.pumpWidget(app(home: const ActivityView()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('activity-tab-bids')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activity-tab-bids')));
      await tester.pumpAndSettle();
      expect(find.text(auction.deviceName), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activity-tab-offers')));
      await tester.pumpAndSettle();
      expect(find.text(auction.deviceName), findsNothing);
      await tester.scrollUntilVisible(
        find.textContaining('Ponuda za telefon'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('Ponuda za telefon'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Studio keeps tools without duplicate cards or menu at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await mainTab(tester, 'Prodavač');
    expect(find.byKey(const ValueKey('seller-hub-live')), findsOneWidget);
    expect(find.text('Tvoj prostor za live.'), findsNothing);
    expect(find.byKey(const ValueKey('seller-hub-menu')), findsNothing);
    final list = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .last;
    for (final id in [
      'finance',
      'inventory',
      'shipments',
      'offers',
      'shows',
      'auction',
      'sales',
      'messages',
    ]) {
      final target = find.byKey(ValueKey('seller-hub-$id'));
      await tester.scrollUntilVisible(target, 180, scrollable: list);
      expect(target, findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
