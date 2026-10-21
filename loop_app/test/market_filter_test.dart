import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/services/market_filter.dart';

void main() {
  final device = Device(
    id: 'test-device',
    name: 'Čitač knjiga',
    model: 'Model Š',
    description: 'Odlično očuvan uređaj',
    condition: DeviceCondition.excellent,
    price: 100,
    category: DeviceCategory.books,
    createdAt: DateTime(2026, 1, 1),
  );

  test('pretraga ne ovisi o hrvatskim dijakriticima', () {
    expect(const MarketFilter(query: 'citac knjiga').matches(device), isTrue);
    expect(const MarketFilter(query: 'model s').matches(device), isTrue);
    expect(const MarketFilter(query: 'ocuvan').matches(device), isTrue);
  });

  test('više riječi može biti u različitim poljima', () {
    expect(
      const MarketFilter(query: '  MODEL   citac  ').matches(device),
      isTrue,
    );
    expect(const MarketFilter(query: 'citac konzola').matches(device), isFalse);
  });

  test('pretraga uključuje i kategoriju', () {
    expect(const MarketFilter(query: 'knjige').matches(device), isTrue);
  });

  test('filter cijene i stanja', () {
    expect(
      const MarketFilter(
        minPrice: 100,
        maxPrice: 100,
        condition: DeviceCondition.excellent,
      ).matches(device),
      isTrue,
    );
    expect(const MarketFilter(maxPrice: 99).matches(device), isFalse);
    expect(
      const MarketFilter(condition: DeviceCondition.good).matches(device),
      isFalse,
    );
  });

  test('priuštivost uračunava 2 posto naknade', () {
    expect(
      const MarketFilter(onlyAffordable: true, credits: 101.99).matches(device),
      isFalse,
    );
    expect(
      const MarketFilter(onlyAffordable: true, credits: 105).matches(device),
      isTrue,
    );
  });
}
