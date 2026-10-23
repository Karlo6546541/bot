import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:loop_app/widgets/photo_viewer.dart';

/// 1×1 PNG kao data: URL (slika kakvu web sprema bez online baze).
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA'
    'DUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  testWidgets('dodir na sliku otvara pregled; listanje i zatvaranje', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final storage = StorageService();
    await tester.runAsync(() async {
      await storage.init(inMemory: true);
      // iPhone 13 demo korisnika s tri fotografije.
      await TradeService(
        storage,
      ).setImages(SeedData.demoUserId, 'seed-9', [_png, '$_png#2', '$_png#3']);
    });
    addTearDown(() => tester.runAsync(Hive.close));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
        ],
        child: const LoopApp(),
      ),
    );
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();

    // Profil → Moji predmeti → detalji predmeta.
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('my-items')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('my-items')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('iPhone 13'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('iPhone 13'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget); // brojač u galeriji

    // Dodir na veliku sliku → pregled preko cijelog ekrana.
    await tester.tapAt(tester.getCenter(find.byType(PageView).first));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsOneWidget);

    // Listanje povlačenjem i tipkovnicom.
    final viewerPages = find.descendant(
      of: find.byType(PhotoViewer),
      matching: find.byType(PageView),
    );
    await tester.drag(viewerPages, const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PhotoViewer),
        matching: find.text('2 / 3'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.chevron_right).last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PhotoViewer),
        matching: find.text('3 / 3'),
      ),
      findsOneWidget,
    );

    // Zatvaranje.
    await tester.tap(find.byTooltip('Zatvori'));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);
  });
}
