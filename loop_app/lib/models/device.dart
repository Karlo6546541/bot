/// Glavni odjeljak Marketa. Svaka kategorija pripada jednom odjeljku.
enum ItemSection {
  electronics('Elektronika'),
  collectibles('Kolekcionarstvo'),
  hobbies('Hobiji'),
  crafts('Rukotvorine'),
  activities('Aktivnosti');

  const ItemSection(this.label);
  final String label;

  List<DeviceCategory> get categories =>
      DeviceCategory.values.where((c) => c.section == this).toList();
}

/// Kategorija predmeta. Boja i ikona za prikaz su u
/// `widgets/category_style.dart`.
enum DeviceCategory {
  // Elektronika
  phone('Mobiteli', 'Mobitel', ItemSection.electronics),
  laptop('Laptopi', 'Laptop', ItemSection.electronics),
  tablet('Tableti', 'Tablet', ItemSection.electronics),
  audio('Slušalice', 'Slušalice', ItemSection.electronics),
  console('Konzole', 'Konzola', ItemSection.electronics),
  watch('Pametni satovi', 'Pametni sat', ItemSection.electronics),
  camera('Kamere', 'Kamera', ItemSection.electronics),
  other('Ostala elektronika', 'Elektronika', ItemSection.electronics),

  // Kolekcionarstvo
  cards('Kartice', 'Kartica', ItemSection.collectibles),
  coins('Kovanice i novčanice', 'Kovanica', ItemSection.collectibles),
  stamps('Marke', 'Marke', ItemSection.collectibles),
  figures('Figure i igračke', 'Figura', ItemSection.collectibles),
  vinyl('Ploče i mediji', 'Ploča', ItemSection.collectibles),

  // Hobiji
  sport('Sportska oprema', 'Sport', ItemSection.hobbies),
  instruments('Glazbeni instrumenti', 'Instrument', ItemSection.hobbies),
  books('Knjige', 'Knjiga', ItemSection.hobbies),
  boardGames('Društvene igre', 'Društvena igra', ItemSection.hobbies),
  models('Modeli i LEGO', 'Model', ItemSection.hobbies),

  // Rukotvorine
  jewelry('Nakit', 'Nakit', ItemSection.crafts),
  ceramics('Keramika', 'Keramika', ItemSection.crafts),
  textile('Pletivo i tekstil', 'Tekstil', ItemSection.crafts),
  woodwork('Drvo', 'Drvo', ItemSection.crafts),
  paintings('Slike i crteži', 'Slika', ItemSection.crafts),

  // Aktivnosti (vaučeri, termini, ulaznice)
  workshops('Radionice', 'Radionica', ItemSection.activities),
  tutoring('Poduke', 'Poduka', ItemSection.activities),
  tickets('Ulaznice', 'Ulaznica', ItemSection.activities),
  experiences('Doživljaji', 'Doživljaj', ItemSection.activities);

  const DeviceCategory(this.label, this.singular, this.section);

  /// Množina — za filtere i grupe ("Mobiteli").
  final String label;

  /// Jednina — za karticu i formu ("Mobitel").
  final String singular;

  final ItemSection section;

  static DeviceCategory fromName(String? name) => DeviceCategory.values
      .firstWhere((c) => c.name == name, orElse: () => DeviceCategory.other);
}

/// Stanje predmeta.
enum DeviceCondition {
  brandNew('Novo'),
  excellent('Odlično'),
  veryGood('Vrlo dobro'),
  good('Dobro'),
  forParts('Za dijelove');

  const DeviceCondition(this.label);
  final String label;

  static DeviceCondition fromName(String? name) => DeviceCondition.values
      .firstWhere((c) => c.name == name, orElse: () => DeviceCondition.good);
}

/// Predmet za trgovanje: uređaj, kolekcionarski predmet, rukotvorina,
/// oprema za hobi ili aktivnost (vaučer/termin). Klasa je zadržala ime
/// `Device` iz prve verzije aplikacije.
///
/// Ako je [ownerId] `null`, predmet je u Marketu (vlasnik je platforma)
/// i svatko ga može kupiti.
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
    this.imagePaths = const [],
    this.description = '',
  });

  final String id;
  final String name;
  final String model;
  final DeviceCondition condition;
  final double price;
  final DeviceCategory category;
  final String? ownerId;
  final DateTime createdAt;

  /// Putanje lokalno spremljenih fotografija (prva je naslovna).
  final List<String> imagePaths;

  /// Opis predmeta (do [maxDescription] znakova, može biti prazan).
  final String description;

  static const maxDescription = 500;

  bool get isOnMarket => ownerId == null;

  ItemSection get section => category.section;

  /// Kopija s novim vlasnikom; `null` vraća predmet u Market.
  Device withOwner(String? ownerId) => Device(
    id: id,
    name: name,
    model: model,
    condition: condition,
    price: price,
    category: category,
    createdAt: createdAt,
    ownerId: ownerId,
    imagePaths: imagePaths,
    description: description,
  );

  Device withImages(List<String> paths) => Device(
    id: id,
    name: name,
    model: model,
    condition: condition,
    price: price,
    category: category,
    createdAt: createdAt,
    ownerId: ownerId,
    imagePaths: paths,
    description: description,
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
    'imagePaths': imagePaths,
    'description': description,
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
    // Stariji zapisi nemaju fotografije.
    imagePaths: (map['imagePaths'] as List?)?.cast<String>() ?? const [],
    description: map['description'] as String? ?? '',
  );
}
