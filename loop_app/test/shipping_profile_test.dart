import 'package:flutter_test/flutter_test.dart';
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
}
