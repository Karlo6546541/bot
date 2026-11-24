import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/config/features.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/add_device_screen.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';

void main() {
  testWidgets('izlaz s nespremljenim podacima traži potvrdu odbacivanja', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.demoUserId);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => AddDeviceScreen.open(ctx),
                child: const Text('Otvori'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Otvori'));
    await tester.pumpAndSettle();
    // Prazan obrazac se zatvara bez pitanja.
    await tester.tap(find.byKey(const ValueKey('add-close')));
    await tester.pumpAndSettle();
    expect(find.byType(AddDeviceScreen), findsNothing);
    await tester.tap(find.text('Otvori'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('add-name')), 'Gitara');
    await tester.tap(find.byKey(const ValueKey('add-close')));
    await tester.pumpAndSettle();
    expect(find.text('Odbaciti promjene?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-keep')));
    await tester.pumpAndSettle();
    expect(find.byType(AddDeviceScreen), findsOneWidget);
    // Sistemski Back također traži potvrdu.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Odbaciti promjene?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-discard')));
    await tester.pumpAndSettle();
    expect(find.byType(AddDeviceScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await Hive.close();
  }, skip: !kLiveEnabled);
}
