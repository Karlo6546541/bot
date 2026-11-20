import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/search_screen.dart';
import 'package:loop_app/services/storage_service.dart';

void main() {
  testWidgets(
    'prazno polje: savjeti; tipkanje: prijedlozi; potvrda: rezultati',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = StorageService();
      await tester.runAsync(() => storage.init(inMemory: true));
      addTearDown(() => tester.runAsync(Hive.close));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            tickIntervalProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(home: SearchScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('global-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-discover')), findsOneWidget);
      expect(find.text('Pametno traženje'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('global-search')),
        'strip',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-suggestions')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-suggest-run')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('search-suggest-run')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-suggestions')), findsNothing);
      expect(find.byKey(const ValueKey('search-tab-top')), findsOneWidget);
    },
  );
}
