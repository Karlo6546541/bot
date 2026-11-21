import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/config/features.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/auctions_home_screen.dart';
import 'package:loop_app/screens/device_detail_screen.dart';
import 'package:loop_app/screens/my_listings_screen.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:loop_app/theme/app_theme.dart';

/// Način "oglasnik": oglasi bez aukcija i kupnje u aplikaciji.
void main() {
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
  });
  tearDown(Hive.close);

  Widget app(Widget home) => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      theme: buildLoopTheme(),
      locale: const Locale('hr'),
      supportedLocales: const [Locale('hr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: home,
    ),
  );

  Future<Device> post(String user) => TradeService(storage).addDevice(
    userId: user,
    name: 'Charizard Base Set',
    model: '',
    condition: DeviceCondition.good,
    price: 250,
    category: DeviceCategory.values.first,
  );

  test('oglas istječe nakon 30 dana, a produljenje ga obnavlja', () async {
    final d = await post(SeedData.testUserId);
    final t0 = d.listedAt!;
    expect(d.isListed, isTrue);
    expect(d.expiresAt, t0.add(const Duration(days: 30)));
    expect(d.isExpiredAt(t0.add(const Duration(days: 29))), isFalse);
    expect(d.isExpiredAt(t0.add(const Duration(days: 30))), isTrue);
    final renewed = d.withListing(
      d.listPrice,
      at: t0.add(const Duration(days: 31)),
    );
    expect(renewed.isExpiredAt(t0.add(const Duration(days: 40))), isFalse);
  });

  test('prodano: datum i cijena ostaju, oglas nestaje s popisa', () async {
    final d = await post(SeedData.testUserId);
    final trade = TradeService(storage);
    final sold = await trade.markSold(
      userId: SeedData.testUserId,
      deviceId: d.id,
      price: 230,
    );
    expect(sold.isSold, isTrue);
    expect(sold.isListed, isFalse);
    expect(sold.soldPrice, 230);
    final back = Device.fromMap(sold.toMap());
    expect(back.soldAt, isNotNull);
    expect(back.soldPrice, 230);
    await expectLater(
      trade.markSold(userId: SeedData.anaUserId, deviceId: d.id),
      throwsA(isA<TradeException>()),
    );
  });

  testWidgets('početna: samo oglasi, bez aukcija i filtera vrste', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const Scaffold(body: AuctionsHomeScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Najnoviji oglasi'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-formats')), findsNothing);
    expect(find.textContaining('licit', findRichText: true), findsNothing);
    expect(find.text('Pretraži oglase'), findsOneWidget);
  }, skip: !kClassifiedsMode);

  testWidgets('tuđi oglas: Kontaktiraj prodavatelja umjesto Kupi odmah', (
    tester,
  ) async {
    final d = await post(SeedData.anaUserId);
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(DeviceDetailScreen(deviceId: d.id)));
    await tester.pumpAndSettle();
    expect(find.text('Kontaktiraj prodavatelja'), findsWidgets);
    expect(find.text('Kupi odmah'), findsNothing);
    expect(find.textContaining('Dostava'), findsNothing);
    expect(find.byKey(const ValueKey('safe-buying')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !kClassifiedsMode);

  testWidgets('vlastiti oglas: uredi, produlji, prodano, skini', (
    tester,
  ) async {
    final d = await post(SeedData.testUserId);
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(DeviceDetailScreen(deviceId: d.id)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-price')), findsOneWidget);
    expect(find.byKey(const ValueKey('renew')), findsOneWidget);
    expect(find.byKey(const ValueKey('unlist')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mark-sold')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sold-price')), '240');
    await tester.tap(find.byKey(const ValueKey('sold-confirm')));
    await tester.pumpAndSettle();
    final sold = storage.deviceById(d.id)!;
    expect(sold.isSold, isTrue);
    expect(sold.soldPrice, 240);
    expect(find.textContaining('Prodano'), findsWidgets);
  }, skip: !kClassifiedsMode);

  testWidgets('Moji oglasi: Aktivni, Istekli i Prodano', (tester) async {
    final active = await post(SeedData.testUserId);
    final old = await post(SeedData.testUserId);
    await storage.putDevice(
      old.withListing(
        old.listPrice,
        at: DateTime.now().subtract(const Duration(days: 40)),
      ),
    );
    final sold = await post(SeedData.testUserId);
    await TradeService(
      storage,
    ).markSold(userId: SeedData.testUserId, deviceId: sold.id, price: 200);
    await tester.pumpWidget(app(const MyListingsScreen()));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('my-listing-item-${active.id}')),
      findsOneWidget,
    );
    expect(find.text('Istekli (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('my-listings-tab-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('my-listing-item-${old.id}')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('my-listings-tab-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('my-listing-item-${sold.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !kClassifiedsMode);
}
