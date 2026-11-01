import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/providers/my_activity_provider.dart';
import 'package:loop_app/screens/auctions_screen.dart';
import 'package:loop_app/services/my_activity_backend.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';

void main() {
  testWidgets('new My tabs include authoritative live rooms and shipments', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
          myOnlineActivityProvider.overrideWith(
            (ref) async => MyOnlineActivity(
              rooms: [
                {
                  'id': 'room-online',
                  'title': 'Moj prijenos iz baze',
                  'status': 'ended',
                },
              ],
              orders: [
                {
                  'id': 'order-online',
                  'seller_id': SeedData.testUserId,
                  'buyer_id': 'other',
                  'total_cents': 1200,
                  'status': 'paid',
                },
              ],
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MyAuctionsView())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('my-live')));
    await tester.pumpAndSettle();
    expect(find.text('Moj prijenos iz baze'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('online-order-order-online')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('my-notes-tab')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('online-order-order-online')),
      findsOneWidget,
    );
    expect(find.text('Moj prijenos iz baze'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await Hive.close();
  });
}
