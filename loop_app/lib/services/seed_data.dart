import '../models/app_user.dart';
import '../models/device.dart';

/// Demo podaci koji se kreiraju pri prvom pokretanju (i nakon resetiranja).
class SeedData {
  static const demoUserId = 'user-demo';
  static const testUserId = 'user-test';

  static List<AppUser> users(DateTime now) => [
    AppUser(
      id: demoUserId,
      email: 'demo@loop.com',
      name: 'Demo Korisnik',
      credits: 1250,
      createdAt: now,
    ),
    AppUser(
      id: testUserId,
      email: 'test@loop.com',
      name: 'Test Korisnik',
      credits: 800,
      createdAt: now,
    ),
  ];

  static List<Device> devices(DateTime now) {
    var i = 0;
    Device d(
      String name,
      String model,
      DeviceCondition condition,
      double price,
      DeviceCategory category, [
      String? ownerId,
    ]) {
      i++;
      return Device(
        id: 'seed-$i',
        name: name,
        model: model,
        condition: condition,
        price: price,
        category: category,
        ownerId: ownerId,
        // Različita vremena kako bi redoslijed u listama bio stabilan.
        createdAt: now.subtract(Duration(minutes: i)),
      );
    }

    const ex = DeviceCondition.excellent;
    const vg = DeviceCondition.veryGood;
    const gd = DeviceCondition.good;
    return [
      // Market (nisu ničiji)
      d('iPhone 15 Pro', '256GB', ex, 780, DeviceCategory.phone),
      d('MacBook Air M3', '16/512', vg, 1120, DeviceCategory.laptop),
      d('Samsung Galaxy S24', '256GB', ex, 610, DeviceCategory.phone),
      d('iPad Air M2', '128GB', vg, 490, DeviceCategory.tablet),
      d('AirPods Pro 2', 'USB-C', ex, 185, DeviceCategory.audio),
      d('iPhone 14', '128GB', gd, 420, DeviceCategory.phone),
      d('MacBook Pro 14"', 'M3 Pro', ex, 1890, DeviceCategory.laptop),
      d('iPad Pro 11"', 'M2', vg, 720, DeviceCategory.tablet),
      // Portfolio demo korisnika
      d('iPhone 13', '128GB', gd, 310, DeviceCategory.phone, demoUserId),
      d(
        'Laptop Lenovo',
        'ThinkPad',
        vg,
        450,
        DeviceCategory.laptop,
        demoUserId,
      ),
      // Dodatni uređaji u Marketu (novije kategorije)
      d('Apple Watch Series 9', '45mm', ex, 290, DeviceCategory.watch),
      d('Sony A7 III', 'Body', vg, 980, DeviceCategory.camera),
      d('PlayStation 5', 'Disc 825GB', vg, 380, DeviceCategory.console),
      d('Nintendo Switch OLED', '64GB', ex, 230, DeviceCategory.console),
    ];
  }
}
