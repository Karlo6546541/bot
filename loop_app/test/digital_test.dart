import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/services/auction_service.dart';
import 'package:loop_app/services/file_store.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/swap_service.dart';
import 'package:loop_app/services/trade_service.dart';

/// Digitalni proizvodi: datoteka, višestruka prodaja, preuzimanje.
void main() {
  late StorageService storage;
  late TradeService trade;

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    trade = TradeService(storage);
  });

  tearDown(() => Hive.close());

  DigitalFile file(String name) => DigitalFile(
    ref: 'local:t/$name',
    name: name,
    size: 1234,
    uploadedAt: DateTime(2026),
  );

  Future<Device> addModel({double price = 40}) => trade.addDevice(
    userId: SeedData.demoUserId,
    name: 'Nosač za mobitel',
    model: 'STL, PLA',
    condition: DeviceCondition.good, // zanemaruje se
    price: price,
    category: DeviceCategory.models3d,
    listOnMarket: false, // zanemaruje se — digitalno je uvijek u Marketu
    file: file('nosac.stl'),
  );

  test('digitalni proizvod treba datoteku; uvijek nov i u Marketu', () async {
    await expectLater(
      trade.addDevice(
        userId: SeedData.demoUserId,
        name: 'X',
        model: 'Y',
        condition: DeviceCondition.good,
        price: 10,
        category: DeviceCategory.software,
      ),
      throwsA(isA<TradeException>()),
    );
    final d = await addModel();
    expect(d.isDigital, isTrue);
    expect(d.isListed, isTrue);
    expect(d.condition, DeviceCondition.brandNew);
    expect(d.file!.name, 'nosac.stl');
    expect(d.file!.extension, 'stl');
  });

  test('prodaje se više puta, vlasnik ga zadržava', () async {
    final d = await addModel(price: 40);
    final demoBefore = storage.userById(SeedData.demoUserId)!.credits;
    final testBefore = storage.userById(SeedData.testUserId)!.credits;

    await trade.buy(userId: SeedData.testUserId, deviceId: d.id);
    await trade.buy(userId: SeedData.markoUserId, deviceId: d.id);

    expect(storage.deviceById(d.id)!.ownerId, SeedData.demoUserId);
    expect(storage.deviceById(d.id)!.isListed, isTrue);
    expect(storage.userById(SeedData.testUserId)!.credits, testBefore - 40.8);
    expect(storage.userById(SeedData.demoUserId)!.credits, demoBefore + 2 * 40);
    expect(trade.buyersOf(d.id), {SeedData.testUserId, SeedData.markoUserId});

    // Isti kupac ne plaća dvaput; vlasnik ne kupuje svoje.
    await expectLater(
      trade.buy(userId: SeedData.testUserId, deviceId: d.id),
      throwsA(isA<TradeException>()),
    );
    await expectLater(
      trade.buy(userId: SeedData.demoUserId, deviceId: d.id),
      throwsA(isA<TradeException>()),
    );
  });

  test('preuzimanje: samo vlasnik i kupci', () async {
    final d = await addModel();
    expect(trade.canDownload(SeedData.demoUserId, d.id), isTrue);
    expect(trade.canDownload(SeedData.testUserId, d.id), isFalse);
    await trade.buy(userId: SeedData.testUserId, deviceId: d.id);
    expect(trade.canDownload(SeedData.testUserId, d.id), isTrue);
    expect(trade.canDownload(SeedData.markoUserId, d.id), isFalse);

    await storage.saveSession(userId: SeedData.testUserId);
    final state = AppState.fromStorage(storage);
    expect(state.hasPurchased(d.id), isTrue);
    expect(state.myDigitalPurchases.map((x) => x.id), [d.id]);
    expect(state.buyersCount(d.id), 1);
  });

  test('nema prodaje LOOP-u, aukcije ni zamjene', () async {
    final d = await addModel(price: 200);
    await expectLater(
      trade.sell(userId: SeedData.demoUserId, deviceId: d.id),
      throwsA(isA<TradeException>()),
    );
    await expectLater(
      AuctionService(storage).create(
        userId: SeedData.demoUserId,
        deviceId: d.id,
        startPrice: 100,
        duration: const Duration(hours: 1),
      ),
      throwsA(isA<TradeException>()),
    );
    final mine = await trade.addDevice(
      userId: SeedData.testUserId,
      name: 'PS5',
      model: 'Slim',
      condition: DeviceCondition.good,
      price: 300,
      category: DeviceCategory.console,
    );
    await expectLater(
      SwapService(storage).offer(
        fromId: SeedData.testUserId,
        wantedDeviceId: d.id,
        offeredDeviceId: mine.id,
      ),
      throwsA(isA<TradeException>()),
    );
  });

  test('s kupcima se ne briše; zamjena datoteke zadržava kupce', () async {
    final d = await addModel();
    await trade.buy(userId: SeedData.testUserId, deviceId: d.id);
    await expectLater(
      trade.deleteOwn(userId: SeedData.demoUserId, deviceId: d.id),
      throwsA(isA<TradeException>()),
    );
    final old = await trade.replaceFile(
      SeedData.demoUserId,
      d.id,
      file('nosac_v2.stl'),
    );
    expect(old!.name, 'nosac.stl');
    expect(storage.deviceById(d.id)!.file!.name, 'nosac_v2.stl');
    expect(trade.canDownload(SeedData.testUserId, d.id), isTrue);
    // Bez kupaca se smije obrisati.
    final other = await addModel();
    await trade.deleteOwn(userId: SeedData.demoUserId, deviceId: other.id);
    expect(storage.deviceById(other.id), isNull);
  });

  test('demo: LOOP Originals se kupuje i datoteka postoji', () async {
    final cube = storage.devices.firstWhere(
      (d) => d.name == 'Kocka za kalibraciju',
    );
    expect(cube.isDigital, isTrue);
    expect(cube.isOnMarket, isTrue);
    await trade.buy(userId: SeedData.testUserId, deviceId: cube.id);
    expect(
      storage.deviceById(cube.id)!.isOnMarket,
      isTrue,
    ); // i dalje u Marketu

    final bytes = await FileStore(storage).read(cube.file!);
    final text = utf8.decode(bytes);
    expect(text, startsWith('solid loop_kocka'));
    expect('facet normal'.allMatches(text), hasLength(12));
  });

  test('provjera datoteke: vrsta i veličina', () {
    final store = FileStore(storage);
    expect(store.validate(PickedFile('model.stl', utf8.encode('x'))), isNull);
    expect(
      store.validate(PickedFile('virus.exe', utf8.encode('x'))),
      isNotNull,
    );
    expect(
      store.validate(PickedFile('prazno.zip', utf8.encode(''))),
      isNotNull,
    );
    expect(
      DigitalFile(
        ref: '',
        name: 'a.zip',
        size: 3 * 1024 * 1024 + 400000,
        uploadedAt: DateTime(2026),
      ).sizeLabel,
      '3,4 MB',
    );
  });
}
