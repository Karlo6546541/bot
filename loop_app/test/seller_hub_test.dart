import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/auctions_screen.dart';
import 'package:loop_app/screens/seller_hub.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';

void main() {
  testWidgets('Moje → Aukcije: Seller Hub s radnjama, otpremom i zdravljem', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
    await LiveService(storage).create(
      hostId: SeedData.testUserId,
      title: 'Moj sljedeći show',
      startsAt: DateTime.now().add(const Duration(hours: 5)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: Scaffold(body: MyAuctionsView())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('my-selling')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('seller-hub')), findsOneWidget);
    // Sažeto: samo radnje i redak stanja; razvijanje otkriva sve.
    expect(find.byKey(const ValueKey('hub-health')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('hub-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hub-add-item')), findsOneWidget);
    expect(find.byKey(const ValueKey('hub-schedule-show')), findsOneWidget);
    expect(find.byKey(const ValueKey('hub-health')), findsOneWidget);
    expect(find.byKey(const ValueKey('hub-shipping-count')), findsOneWidget);
    expect(find.text('Moj sljedeći show'), findsOneWidget);
    // Svi showovi: nadolazeći s radnjama, prošli bez zakazanih.
    await tester.ensureVisible(find.byKey(const ValueKey('hub-all-shows')));
    await tester.tap(find.byKey(const ValueKey('hub-all-shows')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shows-schedule')), findsOneWidget);
    expect(find.text('Moj sljedeći show'), findsOneWidget);
    expect(find.text('Otkaži show'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shows-tab-past')));
    await tester.pumpAndSettle();
    expect(find.text('Još nemaš završenih showova.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await Hive.close();
  });

  test('zdravlje računa: novo, odlično, treba pažnju', () {
    const fresh = AccountHealth(
      ratingAverage: 0,
      ratingCount: 0,
      deliveryRate: null,
      shipments: 0,
    );
    expect(fresh.level, HealthLevel.fresh);
    const great = AccountHealth(
      ratingAverage: 4.8,
      ratingCount: 12,
      deliveryRate: 1,
      shipments: 10,
    );
    expect(great.level, HealthLevel.excellent);
    const okay = AccountHealth(
      ratingAverage: 4.2,
      ratingCount: 5,
      deliveryRate: 0.9,
      shipments: 10,
    );
    expect(okay.level, HealthLevel.good);
    const bad = AccountHealth(
      ratingAverage: 3.1,
      ratingCount: 5,
      deliveryRate: 0.6,
      shipments: 10,
    );
    expect(bad.level, HealthLevel.attention);
  });
}
