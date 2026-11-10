import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/config/design_variant.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/live_screens.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:loop_app/theme/app_theme.dart';

import 'helpers/vision_navigation.dart';

void main() {
  late StorageService storage;
  late Device lotItem, shopItem, shopItem2;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
    Future<Device> add(String name, double price) =>
        TradeService(storage).addDevice(
          userId: SeedData.anaUserId,
          name: name,
          model: 'M',
          condition: DeviceCondition.good,
          price: price,
          category: DeviceCategory.camera,
        );
    lotItem = await add('Predmet za licitaciju', 10);
    shopItem = await add('Proizvod iz shopa', 40);
    shopItem2 = await add('Drugi proizvod', 55);
  });
  tearDown(Hive.close);

  Widget app(Widget page) => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      theme: buildLoopTheme(),
      locale: const Locale('hr'),
      supportedLocales: const [Locale('hr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: page,
    ),
  );

  test(
    'samo domaćin predstavlja proizvod, i to samo uz uključenu trgovinu',
    () async {
      final live = LiveService(storage);
      final show = await live.create(
        hostId: SeedData.anaUserId,
        title: 'Shop live',
        shop: true,
      );
      await live.setFeatured(SeedData.anaUserId, show.id, shopItem2.id);
      expect(storage.liveShowById(show.id)!.featuredId, shopItem2.id);
      await live.setFeatured(SeedData.anaUserId, show.id, null);
      expect(storage.liveShowById(show.id)!.featuredId, isNull);
      expect(
        () => live.setFeatured(SeedData.markoUserId, show.id, shopItem.id),
        throwsA(anything),
      );
      final plain = await live.create(
        hostId: SeedData.markoUserId,
        title: 'Bez shopa',
      );
      expect(
        () => live.setFeatured(SeedData.markoUserId, plain.id, shopItem.id),
        throwsA(anything),
      );
    },
  );

  testWidgets('stalna kartica proizvoda, Svi proizvodi i sakrivanje chata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final live = LiveService(storage);
    final show = await live.create(
      hostId: SeedData.anaUserId,
      title: 'Shop live',
      shop: true,
    );
    await live.setFeatured(SeedData.anaUserId, show.id, shopItem2.id);
    await tester.pumpWidget(app(LiveRoomScreen(showId: show.id)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-featured')), findsOneWidget);
    expect(find.text('Drugi proizvod'), findsWidgets);
    expect(find.byKey(const ValueKey('live-featured-buy')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-queue')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-chat-toggle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chat_bubble_outline), findsWidgets);
    // Kupovna kartica ostaje i kad je chat skriven.
    expect(find.byKey(const ValueKey('live-featured-buy')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-queue')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('live-shop-product-${shopItem.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'prva ponuda traži potvrdu obveze; dodirna alternativa potvrđuje',
    (tester) async {
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final live = LiveService(storage);
      final show = await live.create(
        hostId: SeedData.anaUserId,
        title: 'Aukcija live',
        items: [(lotItem.id, 10)],
        lotSeconds: 60,
      );
      await live.startLot(SeedData.anaUserId, show.id);
      await tester.pumpWidget(app(LiveRoomScreen(showId: show.id)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-rules')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-bid')), findsOneWidget);
      expect(storage.bidTermsAccepted, isFalse);
      await tester.tap(find.byKey(const ValueKey('live-bid')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('live-bid-tap-confirm')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('live-bid-tap-confirm')));
      await tester.pumpAndSettle();
      // Nakon izričite potvrde pojavljuje se objašnjenje obveze.
      expect(find.byKey(const ValueKey('bid-terms-ok')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bid-terms-cancel')));
      await tester.pumpAndSettle();
      expect(storage.bidTermsAccepted, isFalse);
      expect(tester.takeException(), isNull);
      await slideBid(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('nova soba: traka radnji, srce, Proizvodi i Kupi odmah', (
    tester,
  ) async {
    if (!kSimpleDesign) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final show = await LiveService(
      storage,
    ).create(hostId: SeedData.anaUserId, title: 'Shop live', shop: true);
    await tester.pumpWidget(app(LiveRoomScreen(showId: show.id)));
    await tester.pumpAndSettle();
    for (final key in [
      'live-follow',
      'live-viewers-open',
      'live-close',
      'live-room-tools',
      'live-rail-share',
      'live-queue',
      'live-heart',
      'live-featured',
      'live-featured-buy',
      'live-no-video',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    // Stari donji "povuci gore" hvat više nije u sobi.
    expect(find.byKey(const ValueKey('live-controls')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('live-queue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-tab-shop')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
