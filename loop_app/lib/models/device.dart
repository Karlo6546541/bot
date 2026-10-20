/// Kategorija uređaja. Filter u Marketu grupira sve osim mobitela,
/// laptopa i tableta pod "Ostalo".
enum DeviceCategory {
  phone('Mobitel'),
  laptop('Laptop'),
  tablet('Tablet'),
  audio('Slušalice'),
  console('Konzola'),
  other('Ostalo');

  const DeviceCategory(this.label);
  final String label;

  static DeviceCategory fromName(String? name) => DeviceCategory.values
      .firstWhere((c) => c.name == name, orElse: () => DeviceCategory.other);
}

/// Stanje uređaja.
enum DeviceCondition {
  excellent('Odlično'),
  veryGood('Vrlo dobro'),
  good('Dobro'),
  forParts('Za dijelove');

  const DeviceCondition(this.label);
  final String label;

  static DeviceCondition fromName(String? name) => DeviceCondition.values
      .firstWhere((c) => c.name == name, orElse: () => DeviceCondition.good);
}

/// Rabljeni uređaj. Ako je [ownerId] `null`, uređaj je u Marketu
/// (vlasnik je platforma) i svatko ga može kupiti.
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.model,
    required this.condition,
    required this.price,
    required this.category,
    required this.createdAt,
    this.ownerId,
  });

  final String id;
  final String name;
  final String model;
  final DeviceCondition condition;
  final double price;
  final DeviceCategory category;
  final String? ownerId;
  final DateTime createdAt;

  bool get isOnMarket => ownerId == null;

  /// Kopija s novim vlasnikom; `null` vraća uređaj u Market.
  Device withOwner(String? ownerId) => Device(
    id: id,
    name: name,
    model: model,
    condition: condition,
    price: price,
    category: category,
    createdAt: createdAt,
    ownerId: ownerId,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'model': model,
    'condition': condition.name,
    'price': price,
    'category': category.name,
    'ownerId': ownerId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Device.fromMap(Map<dynamic, dynamic> map) => Device(
    id: map['id'] as String,
    name: map['name'] as String,
    model: map['model'] as String,
    condition: DeviceCondition.fromName(map['condition'] as String?),
    price: (map['price'] as num).toDouble(),
    category: DeviceCategory.fromName(map['category'] as String?),
    ownerId: map['ownerId'] as String?,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
