import '../l10n/tr.dart';
import '../services/fee.dart';

/// Glavni odjeljak Marketa. Svaka kategorija pripada jednom odjeljku.
enum ItemSection {
  electronics('Elektronika'),
  collectibles('Kolekcionarstvo'),
  hobbies('Hobiji'),
  crafts('Rukotvorine'),
  activities('Aktivnosti'),
  digital('Digitalno');

  const ItemSection(this._label);
  final String _label;
  String get label => t(_label);

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
  experiences('Doživljaji', 'Doživljaj', ItemSection.activities),

  // Digitalno (datoteka koju kupac preuzima)
  models3d('3D modeli', '3D model', ItemSection.digital),
  software('Softver', 'Softver', ItemSection.digital),
  ebooks('E-knjige i tečajevi', 'E-knjiga', ItemSection.digital),
  templates('Predlošci i grafika', 'Predložak', ItemSection.digital),
  sounds('Glazba i zvukovi', 'Audio', ItemSection.digital);

  const DeviceCategory(this._label, this._singular, this.section);

  /// Množina — za filtere i grupe ("Mobiteli").
  final String _label;
  String get label => t(_label);

  /// Jednina — za karticu i formu ("Mobitel").
  final String _singular;
  String get singular => t(_singular);

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

  const DeviceCondition(this._label);
  final String _label;
  String get label => t(_label);

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
    this.listPrice,
    this.listedAt,
    this.marketChecked = false,
    this.file,
    this.quantity = 1,
    this.discountPercent = 0,
    this.discountUntil,
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

  /// Cijena po kojoj vlasnik prodaje predmet u Marketu (`null` = nije
  /// objavljen). Kupac plaća ovu cijenu (umanjenu za popust) + 2%, a
  /// vlasnik dobiva punu cijenu.
  final double? listPrice;
  final DateTime? listedAt;

  /// Predmet je prošao automatsku objavu u Marketu (ili ga je vlasnik sam
  /// objavio/uklonio). Stari predmeti iz portfolija nemaju ovu oznaku pa se
  /// jednom automatski objave — kasnije "Ukloni iz Marketa" se poštuje.
  final bool marketChecked;

  /// Datoteka digitalnog proizvoda (3D model, softver, e-knjiga…).
  final DigitalFile? file;

  /// Količina na zalihi (komada). Svaka kupnja skida jedan komad; zadnji
  /// komad prelazi kupcu. Digitalni proizvodi nemaju zalihu.
  final int quantity;

  static const maxQuantity = 999;

  /// Popust u postocima (0 = bez popusta) — vrijedi trajno ili do
  /// [discountUntil].
  final int discountPercent;
  final DateTime? discountUntil;

  static const maxDiscount = 90;

  /// Digitalni proizvod: prodaje se više puta, vlasnik ga zadržava, a
  /// kupac preuzima datoteku odmah nakon plaćanja.
  bool get isDigital => category.section == ItemSection.digital;

  /// Predmet platforme (LOOP Market) — svatko ga može kupiti.
  bool get isOnMarket => ownerId == null;

  /// Korisnik je objavio svoj predmet u Marketu.
  bool get isListed => ownerId != null && listPrice != null;

  /// Može se kupiti u Marketu (od platforme ili od korisnika).
  bool get isForSale => isOnMarket || isListed;

  /// Cijena prije popusta.
  double get basePrice => listPrice ?? price;

  /// Popust vrijedi u trenutku [now] (samo za objavljene predmete).
  bool discountActiveAt(DateTime now) =>
      isListed &&
      discountPercent > 0 &&
      (discountUntil == null || now.isBefore(discountUntil!));

  bool get hasDiscount => discountActiveAt(DateTime.now());

  /// Cijena u trenutku [now] (s popustom ako vrijedi).
  double priceAt(DateTime now) => discountActiveAt(now)
      ? ((basePrice * (100 - discountPercent)).roundToDouble()) / 100
      : basePrice;

  /// Cijena za kupca u Marketu (s popustom ako vrijedi), bez naknade.
  double get askPrice => priceAt(DateTime.now());

  /// Cijena koju kupac vidi i plaća (uključuje naknadu platforme).
  double get shownPrice => buyTotal(askPrice);

  /// Redovna cijena za kupca (prije popusta), s uključenom naknadom.
  double get shownBasePrice => buyTotal(basePrice);

  /// Više komada na zalihi (kupnja ne prenosi oglas, nego kopiju predmeta).
  bool get hasStock => !isDigital && quantity > 1;

  ItemSection get section => category.section;

  Device _copy({
    String? id,
    Object? ownerId = _keep,
    List<String>? imagePaths,
    Object? listPrice = _keep,
    Object? listedAt = _keep,
    bool? marketChecked,
    Object? file = _keep,
    int? quantity,
    int? discountPercent,
    Object? discountUntil = _keep,
    DateTime? createdAt,
  }) => Device(
    id: id ?? this.id,
    name: name,
    model: model,
    condition: condition,
    price: price,
    category: category,
    createdAt: createdAt ?? this.createdAt,
    ownerId: ownerId == _keep ? this.ownerId : ownerId as String?,
    imagePaths: imagePaths ?? this.imagePaths,
    description: description,
    listPrice: listPrice == _keep ? this.listPrice : listPrice as double?,
    listedAt: listedAt == _keep ? this.listedAt : listedAt as DateTime?,
    marketChecked: marketChecked ?? this.marketChecked,
    file: file == _keep ? this.file : file as DigitalFile?,
    quantity: quantity ?? this.quantity,
    discountPercent: discountPercent ?? this.discountPercent,
    discountUntil: discountUntil == _keep
        ? this.discountUntil
        : discountUntil as DateTime?,
  );

  /// Kopija s novim vlasnikom; `null` vraća predmet u Market.
  /// Novi vlasnik poništava objavu, zalihu i popust.
  Device withOwner(String? ownerId) => _copy(
    ownerId: ownerId,
    listPrice: null,
    listedAt: null,
    // Kupljeni predmet se ne objavljuje sam od sebe.
    marketChecked: true,
    quantity: 1,
    discountPercent: 0,
    discountUntil: null,
  );

  /// Jedan komad sa zalihe za kupca (novi predmet u njegovom portfoliju).
  Device unitFor(String buyerId, String newId, DateTime at) =>
      _copy(id: newId, createdAt: at).withOwner(buyerId);

  /// Objava u Marketu po cijeni [price] (`null` = ukloni iz Marketa).
  Device withListing(double? price, {DateTime? at, int? quantity}) => _copy(
    listPrice: price,
    listedAt: price == null ? null : at ?? DateTime.now(),
    marketChecked: true,
    quantity: quantity,
  );

  /// Zaliha nakon prodaje jednog komada.
  Device withQuantity(int quantity) => _copy(quantity: quantity);

  /// Popust [percent] % do [until] (`null` = trajno); 0 uklanja popust.
  Device withDiscount(int percent, DateTime? until) => _copy(
    discountPercent: percent,
    discountUntil: percent == 0 ? null : until,
  );

  Device withImages(List<String> paths) => _copy(imagePaths: paths);

  /// Kopija s novom datotekom (vlasnik je zamijenio datoteku).
  Device withFile(DigitalFile f) => _copy(file: f);

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
    'listPrice': listPrice,
    'listedAt': listedAt?.toIso8601String(),
    'marketChecked': marketChecked,
    'file': file?.toMap(),
    'quantity': quantity,
    'discountPercent': discountPercent,
    'discountUntil': discountUntil?.toIso8601String(),
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
    listPrice: (map['listPrice'] as num?)?.toDouble(),
    listedAt: map['listedAt'] == null
        ? null
        : DateTime.parse(map['listedAt'] as String),
    marketChecked: map['marketChecked'] as bool? ?? false,
    file: map['file'] == null ? null : DigitalFile.fromMap(map['file'] as Map),
    quantity: (map['quantity'] as num?)?.toInt() ?? 1,
    discountPercent: (map['discountPercent'] as num?)?.toInt() ?? 0,
    discountUntil: map['discountUntil'] == null
        ? null
        : DateTime.parse(map['discountUntil'] as String),
  );
}

const _keep = Object();

/// Datoteka digitalnog proizvoda. [ref] je mjesto pohrane (online put u
/// privatnom spremištu ili lokalni ključ) — vidi `FileStore`.
class DigitalFile {
  const DigitalFile({
    required this.ref,
    required this.name,
    required this.size,
    required this.uploadedAt,
  });

  final String ref;

  /// Izvorni naziv datoteke (npr. "kocka.stl").
  final String name;

  /// Veličina u bajtovima.
  final int size;
  final DateTime uploadedAt;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// "1,4 MB" / "820 KB".
  String get sizeLabel {
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
    }
    return '${(size / 1024).ceil()} KB';
  }

  Map<String, dynamic> toMap() => {
    'ref': ref,
    'name': name,
    'size': size,
    'uploadedAt': uploadedAt.toIso8601String(),
  };

  factory DigitalFile.fromMap(Map<dynamic, dynamic> m) => DigitalFile(
    ref: m['ref'] as String,
    name: m['name'] as String? ?? 'datoteka',
    size: (m['size'] as num?)?.toInt() ?? 0,
    uploadedAt: DateTime.parse(m['uploadedAt'] as String),
  );
}
