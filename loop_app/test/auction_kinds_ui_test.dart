import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/app_user.dart';
import 'package:loop_app/models/auction.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/auction_detail_screen.dart';
import 'package:loop_app/services/auction_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/theme/app_theme.dart';

void main() {
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.markoUserId);
  });
  tearDown(Hive.close);

  Widget app(String id) => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      theme: buildLoopTheme(),
      locale: const Locale('hr'),
      supportedLocales: const [Locale('hr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: AuctionDetailScreen(auctionId: id),
    ),
  );

  testWidgets('holandska aukcija: padajuća cijena i gumb Kupi', (tester) async {
    final a = await AuctionService(storage).create(
      userId: SeedData.demoUserId,
      deviceId: 'seed-9',
      startPrice: 200,
      duration: const Duration(hours: 2),
      kind: AuctionKind.dutch,
      floorPrice: 100,
    );
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(a.id));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dutch-price')), findsOneWidget);
    expect(find.byKey(const ValueKey('dutch-take')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-bid')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bez povezane kartice ponuda se ne šalje', (tester) async {
    final marko = storage.userById(SeedData.markoUserId)!;
    await storage.putUser(
      AppUser.fromMap({...marko.toMap(), 'paymentCard': null}),
    );
    final a = await AuctionService(storage).create(
      userId: SeedData.demoUserId,
      deviceId: 'seed-9',
      startPrice: 50,
      duration: const Duration(hours: 2),
    );
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(a.id));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-bid')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bid-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Poveži karticu za licitiranje'), findsOneWidget);
    await tester.tap(find.text('Odustani'));
    await tester.pumpAndSettle();
    expect(storage.auctionById(a.id)!.bids, isEmpty);
  });

  testWidgets('holandska: bez kartice nema kupnje', (tester) async {
    final marko = storage.userById(SeedData.markoUserId)!;
    await storage.putUser(
      AppUser.fromMap({...marko.toMap(), 'paymentCard': null}),
    );
    final a = await AuctionService(storage).create(
      userId: SeedData.demoUserId,
      deviceId: 'seed-9',
      startPrice: 200,
      duration: const Duration(hours: 2),
      kind: AuctionKind.dutch,
      floorPrice: 100,
    );
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(a.id));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dutch-take')));
    await tester.pumpAndSettle();
    expect(find.text('Poveži karticu za licitiranje'), findsOneWidget);
    await tester.tap(find.text('Odustani'));
    await tester.pumpAndSettle();
    expect(storage.auctionById(a.id)!.isActive, isTrue);
  });

  test('nekadašnja zatvorena aukcija čita se kao klasična', () {
    expect(AuctionKind.fromName('sealed'), AuctionKind.classic);
    expect(AuctionKind.values, [AuctionKind.classic, AuctionKind.dutch]);
  });
}
