import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/device_detail_screen.dart';
import 'package:loop_app/screens/live_home_screen.dart';
import 'package:loop_app/screens/live_screens.dart';
import 'package:loop_app/screens/profile_screen.dart';
import 'package:loop_app/screens/public_profile_screen.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:loop_app/theme/app_theme.dart';
import 'package:loop_app/widgets/live_shop_widgets.dart';

void main() {
  late StorageService storage;
  late Device item;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
    item = await TradeService(storage).addDevice(
      userId: SeedData.anaUserId,
      name: 'Fotoaparat iz shopa',
      model: 'EOS',
      condition: DeviceCondition.good,
      price: 80,
      category: DeviceCategory.camera,
    );
  });
  tearDown(Hive.close);
  Widget app(Widget page, {double textScale = 1}) => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      theme: buildLoopTheme(),
      locale: const Locale('hr'),
      supportedLocales: const [Locale('hr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: page,
    ),
  );
  testWidgets(
    'seller profile opens products by default and preserves the item purchase flow',
    (tester) async {
      await tester.pumpWidget(
        app(const PublicProfileScreen(userId: SeedData.anaUserId)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('shop-item-${item.id}')),
        250,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.ensureVisible(find.byKey(ValueKey('shop-item-${item.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('shop-item-${item.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceDetailScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('buy-now')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('own Profile shows the actual shop before account management', (
    tester,
  ) async {
    await storage.saveSession(userId: SeedData.anaUserId);
    await tester.pumpWidget(app(const Scaffold(body: ProfileScreen())));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('account-shop-item-${item.id}')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.byKey(const ValueKey('account-open-shop')), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const ValueKey('account-open-shop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-open-shop')));
    await tester.pumpAndSettle();
    expect(find.byType(PublicProfileScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'live shop keeps available products separate from live lots and opens the seller shop',
    (tester) async {
      final extra = await TradeService(storage).addDevice(
        userId: SeedData.anaUserId,
        name: 'Torba za fotoaparat',
        model: 'Crna',
        condition: DeviceCondition.good,
        price: 25,
        category: DeviceCategory.camera,
      );
      final live = LiveService(storage);
      final show = await live.create(
        hostId: SeedData.anaUserId,
        title: 'Foto shop uživo',
        items: [(item.id, 10)],
        lotSeconds: 60,
      );
      await live.startLot(SeedData.anaUserId, show.id);
      await tester.pumpWidget(app(LiveRoomScreen(showId: show.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-queue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-tab-shop')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('live-shop-buy-${extra.id}')), findsOneWidget);
      expect(
        find.byKey(ValueKey('live-shop-product-${item.id}')),
        findsNothing,
      );
      expect(find.byType(LiveRoomScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('live-open-seller-shop')),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('live-open-seller-shop')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-open-seller-shop')));
      await tester.pumpAndSettle();
      expect(find.byType(PublicProfileScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PublicProfileScreen), findsNothing);
      expect(find.byType(LiveRoomScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final config in [
    (const Size(320, 600), 1.0),
    (const Size(390, 844), 1.5),
  ]) {
    testWidgets(
      'featured live enters the room and keeps extras off stage at $config',
      (tester) async {
        tester.view.physicalSize = config.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final live = LiveService(storage);
        final show = await live.create(
          hostId: SeedData.anaUserId,
          title: 'Fotoaparati i objektivi uživo',
          items: [(item.id, 10)],
          lotSeconds: 60,
        );
        await live.startLot(SeedData.anaUserId, show.id);
        await tester.pumpWidget(
          app(const Scaffold(body: LiveHomeScreen()), textScale: config.$2),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LiveShopFeature), findsOneWidget);
        await tester.ensureVisible(find.byType(LiveShopFeature));
        await tester.tap(find.byType(LiveShopFeature));
        await tester.pumpAndSettle();
        expect(find.byType(LiveRoomScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('live-bid')), findsOneWidget);
        expect(find.byKey(const ValueKey('live-share')), findsNothing);
        expect(find.byKey(const ValueKey('wallet')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('live-room-tools')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('live-share')), findsOneWidget);
        expect(find.byKey(const ValueKey('wallet')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
