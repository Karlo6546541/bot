import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/services/storage_service.dart';

Future<Widget> buildApp(WidgetTester tester) async {
  final storage = StorageService();
  await tester.runAsync(() => storage.init(inMemory: true));
  addTearDown(() => tester.runAsync(Hive.close));
  return ProviderScope(
    overrides: [storageProvider.overrideWithValue(storage)],
    child: const LoopApp(),
  );
}

void main() {
  for (final size in const [Size(1400, 1000), Size(400, 860)]) {
    testWidgets('login → prodaja → kupnja → aktivnost ($size)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await buildApp(tester));
      await tester.tap(find.text('Prijavi se'));
      await tester.pumpAndSettle();

      // Portfolio demo korisnika
      expect(find.text('1,250.00'), findsOneWidget);
      expect(find.text('SILVER'), findsOneWidget);
      expect(find.text('iPhone 13'), findsOneWidget);

      // Prodaja
      await tester.tap(find.text('Prodaj odmah').first);
      await tester.pumpAndSettle();
      expect(find.text('Fee (5%)'), findsOneWidget);
      await tester.tap(find.text('Potvrdi prodaju'));
      await tester.pumpAndSettle();
      expect(find.text('Uspješno prodano'), findsOneWidget);
      expect(find.text('1,544.50'), findsOneWidget);

      // Kupnja (AirPods Pro 2: 185 + 5% = 194.25)
      await tester.tap(find.text('Market').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'AirPods');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kupi odmah'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Potvrdi kupnju'));
      await tester.pumpAndSettle();
      expect(find.text('Uspješno kupljeno'), findsOneWidget);

      // Aktivnost: najnovije na vrhu
      await tester.tap(find.text('Aktivnost').last);
      await tester.pumpAndSettle();
      expect(find.text('+294.50 LC'), findsOneWidget);
      expect(find.text('−194.25 LC'), findsOneWidget);
    });
  }

  testWidgets('admin prijava i dashboard', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.tap(find.text('Admin prijava'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'admin123');
    await tester.tap(find.text('Prijava'));
    await tester.pumpAndSettle();

    expect(find.textContaining('LOOP Admin'), findsOneWidget);
    expect(find.text('Ukupni volume'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.group_outlined));
    await tester.pumpAndSettle();
    expect(find.text('demo@loop.com'), findsOneWidget);
  });
}
