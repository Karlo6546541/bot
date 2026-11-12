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
  if (kLiveEnabled || !kBuyNowEnabled) {
    test('Prodaj s izborom Aukcija/Kupi odmah', () {}, skip: 'zastavice');
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
      expect(find.byType(SellAuctionScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('sell-form')), findsOneWidget);
      expect(find.byKey(const ValueKey('sell-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('sell-submit')), findsOneWidget);
      expect(find.text('Moji showovi'), findsNothing);
      expect(find.byKey(const ValueKey('sell-close')), findsNothing);
      final scroll = find
          .descendant(
            of: find.byKey(const ValueKey('sell-form')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sell-kind-dutch')),
        200,
        scrollable: scroll,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('sell-kind-dutch'))),
        alignment: 0.3,
      );
      await tester.pumpAndSettle();
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
      // Kupi odmah: bez vrste aukcije, najniže cijene i trajanja.
      await tester.drag(scroll, const Offset(0, 2000));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sell-mode-buynow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sell-kind-dutch')), findsNothing);
      expect(find.byKey(const ValueKey('sell-floor')), findsNothing);
      expect(find.text('Objavi oglas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
