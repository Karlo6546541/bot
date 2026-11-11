import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/config/features.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/sell_screens.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';

import 'helpers/vision_navigation.dart';

void main() {
  if (kLiveEnabled) {
    test('samo aukcije je isključen', () {}, skip: 'LIVE uključen');
    return;
  }
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
  });
  tearDown(Hive.close);

  Widget app() => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: const LoopApp(),
  );

  testWidgets(
    'Prodaj: jedan gumb, bez livea i shopa; forma na jednoj stranici',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await mainTab(tester, 'Prodaj');
      expect(find.byType(SellScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('sell-new')), findsOneWidget);
      expect(find.text('Moji showovi'), findsNothing);
      expect(find.text('Dodaj proizvod'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sell-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sell-form')), findsOneWidget);
      expect(find.byKey(const ValueKey('sell-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('sell-submit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sell-kind-dutch')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sell-floor')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('sell-form')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(const ValueKey('sell-floor')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
