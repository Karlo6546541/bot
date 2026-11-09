import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/live_screens.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/theme/app_theme.dart';

void main() {
  testWidgets('novi live na 360 px: koraci, razlog, odbacivanje', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final storage = StorageService();
    await tester.runAsync(() async {
      await storage.init(inMemory: true);
      await storage.saveSession(userId: SeedData.demoUserId);
    });
    addTearDown(() => tester.runAsync(Hive.close));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: buildLiveTheme(),
          home: const CreateLiveShowScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Osnovno'), findsOneWidget);
    expect(find.text('1 od 2'), findsOneWidget);
    expect(find.text('Sada'), findsOneWidget);
    expect(find.text('Zakaži'), findsOneWidget);
    expect(find.text('Samo Kupi odmah'), findsNothing);
    expect(find.text('Brzi boost (15 min)'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('wizard-next')))
          .onPressed,
      isNull,
    );
    expect(find.text('Upiši naslov (barem 3 znaka).'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('live-title')),
      'Retro večer',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('wizard-next')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('wizard-close')));
    await tester.pumpAndSettle();
    expect(find.text('Odbaciti live?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-discard-keep')));
    await tester.pumpAndSettle();
    expect(find.text('Osnovno'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await tester.pumpAndSettle();
    expect(find.text('2 od 2'), findsOneWidget);
    expect(find.text('Predmeti u liveu'), findsOneWidget);
    expect(find.text('Nema predmeta u ovom liveu'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-quick-item')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-from-shop')), findsOneWidget);
    expect(find.textContaining('Kamera uključena'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-quick-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('quick-lot-name')),
      'Game Boy',
    );
    await tester.tap(find.byKey(const ValueKey('quick-mode-buy')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quick-lot-price')), '24');
    await tester.enterText(find.byKey(const ValueKey('quick-lot-qty')), '3');
    await tester.tap(find.byKey(const ValueKey('quick-lot-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Kupi odmah · 24 € · 3 kom'), findsOneWidget);
    expect(find.text('U ovom liveu (1)'), findsOneWidget);
    expect(find.textContaining('1 Kupi odmah'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('live-go')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('wizard-back')));
    await tester.pumpAndSettle();
    expect(find.text('Osnovno'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('live-title')))
          .controller!
          .text,
      'Retro večer',
    );

    expect(tester.takeException(), isNull);
  });
}
