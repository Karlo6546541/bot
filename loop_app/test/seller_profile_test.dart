import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/config/design_variant.dart';
import 'package:loop_app/models/app_user.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/public_profile_screen.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:loop_app/theme/app_theme.dart';

/// Kompaktni profil prodavača (novi izgled): pokreće se s
/// `--dart-define=SIMPLE_DESIGN=true`.
void main() {
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
  });
  tearDown(Hive.close);

  Widget app(String userId, {double scale = 1}) => ProviderScope(
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
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: PublicProfileScreen(userId: userId),
    ),
  );

  Future<void> addProducts(int n) async {
    for (var i = 0; i < n; i++) {
      await TradeService(storage).addDevice(
        userId: SeedData.anaUserId,
        name: 'Proizvod $i',
        model: 'M',
        condition: DeviceCondition.good,
        price: 10.0 + i,
        category: i.isEven ? DeviceCategory.camera : DeviceCategory.audio,
      );
    }
  }

  for (final size in [
    const Size(360, 740),
    const Size(390, 844),
    const Size(430, 932),
    const Size(1280, 800),
  ]) {
    testWidgets('profil: ponuda se vidi bez dugog pomicanja na $size', (
      tester,
    ) async {
      if (!kSimpleDesign) return;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await addProducts(10);
      await tester.pumpWidget(app(SeedData.anaUserId));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-stats')), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-message')), findsOneWidget);
      expect(find.byKey(const ValueKey('shop-grid')), findsOneWidget);
      final cards = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_ShopGridCard',
      );
      final first = tester.getRect(cards.first);
      expect(first.top, lessThan(size.height * .8));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('profil: dugo ime i povećan tekst bez prelijevanja', (
    tester,
  ) async {
    if (!kSimpleDesign) return;
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ana = storage.userById(SeedData.anaUserId)!;
    await storage.putUser(
      ana.copyWith(
        shopName:
            'Vrlo dugo ime trgovine koje se ne smije prelijevati ni na malom ekranu',
      ),
    );
    await addProducts(4);
    await tester.pumpWidget(app(SeedData.anaUserId, scale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('profil bez proizvoda nema prazan shop', (tester) async {
    if (!kSimpleDesign) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Korisnik bez ijednog predmeta.
    // Novi korisnik bez ijednog predmeta.
    final empty = AppUser(
      id: 'user-nema-ponude',
      email: 'nema@test.hr',
      name: 'Nema Ponude',
      credits: 0,
      createdAt: DateTime(2026),
      username: 'nemaponude',
    );
    await storage.putUser(empty);
    await tester.pumpWidget(app(empty.id));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shop-grid')), findsNothing);
    expect(find.byKey(const ValueKey('shop-tab-items')), findsNothing);
    expect(find.byKey(const ValueKey('shop-tab-reviews')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vlasnik vidi Uredi profil, ne Prati i Poruku', (tester) async {
    if (!kSimpleDesign) return;
    await storage.saveSession(userId: SeedData.anaUserId);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(SeedData.anaUserId));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-message')), findsNothing);
    expect(find.byKey(const ValueKey('follow')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('povratak iz proizvoda čuva položaj u shopu', (tester) async {
    if (!kSimpleDesign) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await addProducts(24);
    await tester.pumpWidget(app(SeedData.anaUserId));
    await tester.pumpAndSettle();
    final scroll = find.byKey(const ValueKey('profile-scroll'));
    await tester.drag(scroll, const Offset(0, -500));
    await tester.pumpAndSettle();
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        )
        .position
        .pixels;
    final before = offset();
    expect(before, greaterThan(100));
    final card = find.byWidgetPredicate(
      (w) =>
          w.runtimeType.toString() == '_ShopGridCard' &&
          w.key is ValueKey<String>,
    );
    await tester.tap(card.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(offset(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aktivan live: kompaktna kartica s Gledaj uživo', (tester) async {
    if (!kSimpleDesign) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final show = await LiveService(
      storage,
    ).create(hostId: SeedData.anaUserId, title: 'Ana uživo');
    await tester.pumpWidget(app(SeedData.anaUserId));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('profile-live-${show.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-watch-live')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-grid')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
