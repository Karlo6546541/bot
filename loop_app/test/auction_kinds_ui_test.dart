import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
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

  testWidgets('zatvorena aukcija: skrivene ponude i polje za ponudu', (
    tester,
  ) async {
    final a = await AuctionService(storage).create(
      userId: SeedData.demoUserId,
      deviceId: 'seed-9',
      startPrice: 50,
      duration: const Duration(hours: 2),
      kind: AuctionKind.sealed,
    );
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(a.id));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auction-kind')), findsOneWidget);
    expect(find.byKey(const ValueKey('sealed-hidden')), findsOneWidget);
    expect(find.byKey(const ValueKey('sealed-amount')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-bid')), findsNothing);
    expect(find.byKey(const ValueKey('dutch-take')), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.byKey(const ValueKey('sealed-amount')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
