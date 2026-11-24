import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/create_auction_screen.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  testWidgets(
    'nova aukcija: popis predmeta s pretragom i skupljenim odabirom',
    (tester) async {
      final storage = StorageService();
      await tester.runAsync(() async {
        await storage.init(inMemory: true);
        await storage.saveSession(userId: SeedData.demoUserId);
        for (final n in ['Walkman Sony', 'Gameboy Color']) {
          await TradeService(storage).addDevice(
            userId: SeedData.demoUserId,
            name: n,
            model: '',
            condition: DeviceCondition.good,
            price: 40,
            category: DeviceCategory.values.first,
            listOnMarket: false,
          );
        }
      });
      addTearDown(() => tester.runAsync(Hive.close));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageProvider.overrideWithValue(storage)],
          child: const MaterialApp(home: CreateAuctionScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Walkman Sony'), findsOneWidget);
      expect(find.text('Gameboy Color'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('auction-item-search')),
        'walk',
      );
      await tester.pumpAndSettle();
      expect(find.text('Walkman Sony'), findsOneWidget);
      expect(find.text('Gameboy Color'), findsNothing);
      await tester.tap(find.text('Walkman Sony'));
      await tester.pumpAndSettle();
      // Odabir se skupi u jedan red s "Promijeni".
      expect(find.byKey(const ValueKey('auction-change-item')), findsOneWidget);
      expect(find.byKey(const ValueKey('auction-item-search')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('auction-change-item')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auction-item-search')), findsOneWidget);
    },
  );
}
