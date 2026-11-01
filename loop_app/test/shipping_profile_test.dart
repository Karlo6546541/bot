import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/add_device_screen.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/shipping_profile.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  test('profil dostave: veličina paketa iz težine i dimenzija', () {
    ShippingProfile p(int g, [int l = 0, int w = 0, int h = 0]) =>
        ShippingProfile(
          id: 'x',
          name: 'x',
          weightGrams: g,
          lengthCm: l,
          widthCm: w,
          heightCm: h,
        );
    expect(p(800, 20, 15, 5).parcelSize, ParcelSize.small);
    expect(p(1500, 60, 40, 30).parcelSize, ParcelSize.medium);
    expect(p(9000).parcelSize, ParcelSize.medium);
    expect(p(25000, 80, 60, 50).parcelSize, ParcelSize.large);
    expect(p(40000).parcelSize, ParcelSize.bulky);
    expect(p(1200, 30, 20, 10).summary, '1,2 kg · 30 × 20 × 10 cm');
    expect(
      ShippingProfile.validate(
        name: 'Kutija',
        weightGrams: 500,
        lengthCm: 10,
        widthCm: 0,
        heightCm: 5,
        maxItems: 0,
      ),
      isNotNull,
    );
    final round = ShippingProfile.fromMap(
      p(1200, 30, 20, 10).copyWith(maxItems: 3).toMap(),
    );
    expect(round.maxItems, 3);
    expect(round.heightCm, 10);
  });

  group('paketi iz istog livea', () {
    const seller = SeedData.demoUserId;
    const buyer = SeedData.testUserId;
    late StorageService storage;
    late DeliveryService deliveries;

    setUp(() async {
      storage = StorageService();
      await storage.init(inMemory: true);
      await storage.saveSession(userId: buyer);
      deliveries = DeliveryService(storage);
    });
    tearDown(() => Hive.close());

    test(
      'najviše 2 u paketu: treći predmet otvara novi plaćeni paket',
      () async {
        final trade = TradeService(storage);
        const profile = ShippingProfile(
          id: 'sp1',
          name: 'Kartice',
          weightGrams: 300,
          maxItems: 2,
        );
        for (var i = 0; i < 3; i++) {
          final d = await trade.addDevice(
            userId: seller,
            name: 'Kartica $i',
            model: '',
            condition: DeviceCondition.good,
            price: 5,
            category: DeviceCategory.values.firstWhere(
              (c) => c.section != ItemSection.digital,
            ),
          );
          await storage.putDevice(d.withShipping(profile));
          await deliveries.createPending(
            id: 'live-show1-$i',
            userId: buyer,
            deviceId: d.id,
            deviceName: d.name,
            sellerId: seller,
          );
        }
        await deliveries.choose(
          userId: buyer,
          deliveryId: 'live-show1-0',
          method: DeliveryMethod.courier,
          destination: 'Ilica 1, 10000 Zagreb',
        );
        final costs = [
          for (var i = 0; i < 3; i++)
            storage.deliveryById('live-show1-$i')!.cost,
        ];
        final courier = DeliveryService.costFor(
          DeliveryMethod.courier,
          ParcelSize.small,
        );
        expect(costs, [courier, 0, courier]);
      },
    );
  });

  testWidgets('obrazac predmeta: profil dostave, količina i Spremi skicu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.demoUserId);
    const profile = ShippingProfile(
      id: 'sp-box',
      name: 'Srednja kutija',
      weightGrams: 4000,
      lengthCm: 40,
      widthCm: 30,
      heightCm: 20,
    );
    final me = storage.userById(SeedData.demoUserId)!;
    await storage.putUser(me.copyWith(shippingProfiles: [profile]));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: AddDeviceScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('add-name')), 'iPhone 13');
    await tester.enterText(find.byType(TextFormField).at(1), '300');
    await tester.pumpAndSettle();
    // Profil dostave iz padajućeg izbornika.
    await tester.tap(find.byKey(const ValueKey('add-profile-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Srednja kutija · 4 kg').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-profile-summary')), findsOneWidget);
    // Količina s + (u "Više detalja").
    await tester.ensureVisible(find.byKey(const ValueKey('add-more')));
    await tester.tap(find.byKey(const ValueKey('add-more')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('quantity-plus')));
    await tester.tap(find.byKey(const ValueKey('quantity-plus')));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsWidgets);
    await tester.ensureVisible(find.byKey(const ValueKey('add-save-draft')));
    await tester.tap(find.byKey(const ValueKey('add-save-draft')));
    await tester.pumpAndSettle();
    final d = storage.devices.firstWhere((d) => d.name == 'iPhone 13');
    expect(d.isListed, isFalse);
    expect(d.quantity, 2);
    expect(d.shipping?.id, 'sp-box');
    expect(d.parcelSize, ParcelSize.medium.name);
    await tester.pumpWidget(const SizedBox.shrink());
    await Hive.close();
  });

  test('prodavač šalje u paketomat: kupac dobiva broj i PIN', () async {
    final storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
    final deliveries = DeliveryService(storage);
    await deliveries.createPending(
      id: 'auc-1',
      userId: SeedData.testUserId,
      deviceId: 'dev-1',
      deviceName: 'Walkman',
      sellerId: SeedData.demoUserId,
    );
    // Kupac ne može poslati umjesto prodavača.
    await expectLater(
      deliveries.ship(
        sellerId: SeedData.testUserId,
        deliveryId: 'auc-1',
        method: DeliveryMethod.courier,
        destination: 'Ilica 1, 10000 Zagreb',
      ),
      throwsA(isA<TradeException>()),
    );
    final before = storage.userById(SeedData.testUserId)!;
    final d = await deliveries.ship(
      sellerId: SeedData.demoUserId,
      deliveryId: 'auc-1',
      method: DeliveryMethod.parcelLocker,
      destination: kDemoLockers.first,
    );
    expect(d.method, DeliveryMethod.parcelLocker);
    expect(d.trackingNumber, isNotNull);
    expect(d.pickupPin, isNotNull);
    // Kupčeve spremljene postavke ostaju (bira prodavač).
    expect(
      storage.userById(SeedData.testUserId)!.lastDelivery,
      before.lastDelivery,
    );
    await Hive.close();
  });
}
