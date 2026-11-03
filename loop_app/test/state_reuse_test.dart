import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
  });
  tearDown(() => Hive.close());

  test(
    'nepromijenjene tablice se ne čitaju ponovno, promijenjene da',
    () async {
      final a = AppState.fromStorage(storage);
      final b = AppState.fromStorage(storage, previous: a);
      expect(identical(b.devices, a.devices), isTrue);
      expect(identical(b.users, a.users), isTrue);
      expect(identical(b.liveEvents, a.liveEvents), isTrue);
      expect(b.sameAs(a), isTrue);

      await TradeService(storage).addDevice(
        userId: SeedData.demoUserId,
        name: 'Novi predmet',
        model: '',
        condition: DeviceCondition.good,
        price: 10,
        category: DeviceCategory.values.firstWhere(
          (c) => c.section != ItemSection.digital,
        ),
      );
      final c = AppState.fromStorage(storage, previous: b);
      expect(identical(c.devices, b.devices), isFalse);
      expect(c.devices.length, b.devices.length + 1);
      // Ostalo se ne dira.
      expect(identical(c.deliveries, b.deliveries), isTrue);
      expect(c.sameAs(b), isFalse);
    },
  );

  test('izvedeni popisi se pamte po snimci, ali ne između snimki', () async {
    final a = AppState.fromStorage(storage);
    expect(identical(a.marketDevices, a.marketDevices), isTrue);
    expect(identical(a.activeAuctions, a.activeAuctions), isTrue);
    final b = AppState.fromStorage(storage, previous: a);
    expect(identical(a.marketDevices, b.marketDevices), isFalse);
    expect(a.marketDevices.length, b.marketDevices.length);
  });
}
