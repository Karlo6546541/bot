import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  late StorageService storage;
  late Device own;
  late Device liked;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
    final trade = TradeService(storage);
    await storage.putUser(
      storage.userById(SeedData.testUserId)!.copyWith(favorites: []),
    );
    own = await trade.addDevice(
      userId: SeedData.testUserId,
      name: 'Moja konzola',
      model: 'PSP',
      condition: DeviceCondition.good,
      price: 45,
      category: DeviceCategory.console,
    );
    liked = storage.devices.firstWhere(
      (d) => d.ownerId != SeedData.testUserId && !d.isDigital,
    );
    await trade.toggleFavorite(SeedData.testUserId, liked.id);
  });
  tearDown(Hive.close);

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
        ],
        child: const LoopApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    // Račun (kao Whatnot): objave su iza "Pogledaj profil".
    expect(find.byKey(const ValueKey('account-home')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-view-profile')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'account opens posts and keeps settings behind its gear on small screens',
    (tester) async {
      await open(tester, size: const Size(320, 600));
      expect(find.byKey(const ValueKey('account-profile')), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-create')), findsOneWidget);
      expect(find.byKey(const ValueKey('seller-info')), findsNothing);
      expect(find.text('Odjavi se'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('my-profile-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('seller-info')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-settings-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-home')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'liked section shows real favorites and removes an unlike immediately',
    (tester) async {
      await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-liked-tab')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-liked-tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('account-post-${liked.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('account-post-${own.id}')), findsNothing);
      await tester.ensureVisible(
        find.byKey(ValueKey('profile-unlike-${liked.id}')),
      );
      await tester.tap(find.byKey(ValueKey('profile-unlike-${liked.id}')));
      await tester.pumpAndSettle();
      expect(
        storage.userById(SeedData.testUserId)!.favorites,
        isNot(contains(liked.id)),
      );
      expect(find.text('Još nema lajkanih oglasa.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'owner can start a post and delete their own item from its menu',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('profile-liked-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-create')));
      await tester.pumpAndSettle();
      expect(find.text('Što želiš pokrenuti?'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      final menu = find.byKey(ValueKey('profile-post-menu-${own.id}'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Obriši predmet').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('Obriši').last));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 650)),
      );
      await tester.pumpAndSettle();
      expect(storage.deviceById(own.id), isNull);
      expect(find.byKey(ValueKey('account-post-${own.id}')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
