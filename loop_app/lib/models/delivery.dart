import '../l10n/tr.dart';

/// Način dostave. Cijena je u kreditima; trajanje je u demo verziji
/// ubrzano (minute umjesto dana) kako bi se statusi mogli vidjeti uživo.
enum DeliveryMethod {
  pickup(
    'Osobno preuzimanje',
    'Subhasto točka, Zagreb · odmah spremno',
    0,
    2,
    0,
  ),
  parcelLocker(
    'BOX NOW paketomat',
    'Odaberi paketomat na karti · 1–2 dana',
    3,
    3,
    1,
  ),
  courier('Kurir na adresu', 'Dostava na kućnu adresu · 2–3 dana', 6, 4, 2),
  express('Ekspresna dostava', 'Kurir isti ili sljedeći dan', 12, 2, 1),
  europe(
    'Dostava u EU',
    'Kurir na adresu u drugoj državi EU · 4–7 dana',
    14,
    5,
    6,
  ),
  digital('Digitalna dostava', 'Ulaznica/vaučer na e-mail · odmah', 0, 1, 0);

  const DeliveryMethod(
    this._label,
    this._subtitle,
    this.cost,
    this.demoMinutes,
    this.realDays,
  );

  final String _label;
  String get label => t(_label);
  final String _subtitle;
  String get subtitle => t(_subtitle);

  /// Cijena dostave u kreditima.
  final double cost;

  /// Ukupno trajanje u demo verziji (minute).
  final int demoMinutes;

  /// Približno trajanje u stvarnosti (dani) — samo za prikaz.
  final int realDays;

  bool get needsAddress => this == courier || this == express || this == europe;
  bool get needsLocker => this == parcelLocker;

  static DeliveryMethod fromName(String? n) => DeliveryMethod.values.firstWhere(
    (m) => m.name == n,
    orElse: () => DeliveryMethod.courier,
  );
}

/// Veličina paketa (bira prodavač pri objavi). Dodaje se na cijenu
/// dostave; paketomat prima samo male i srednje, ekspres ne vozi glomazno.
enum ParcelSize {
  small('Malo', 'do 2 kg · kartice, sat, mobitel', 0),
  medium('Srednje', 'do 10 kg · konzola, cipele, knjige', 3),
  large('Veliko', 'do 30 kg · gramofon, monitor, kofer', 9),
  bulky('Glomazno', 'preko 30 kg · bicikl, namještaj', 29);

  const ParcelSize(this._label, this._hint, this.extra);
  final String _label;
  String get label => t(_label);
  final String _hint;
  String get hint => t(_hint);

  /// Doplata na dostavu (€) u Hrvatskoj; u EU dvostruko.
  final double extra;

  static ParcelSize fromName(String? n) => ParcelSize.values.firstWhere(
    (s) => s.name == n,
    orElse: () => ParcelSize.small,
  );
}

/// Status pošiljke. Za osobno preuzimanje koraci su drugačiji
/// (vidi [Delivery.steps]).
enum DeliveryStatus {
  awaitingChoice('Odaberi dostavu'),
  ordered('Plaćeno'),
  packed('Zapakirano'),
  shipped('Poslano'),
  inTransit('U transportu'),
  inLocker('U paketomatu'),
  pickedUp('Preuzeto'),
  readyForPickup('Spremno za preuzimanje'),
  sent('Poslano e-mailom'),
  delivered('Dostavljeno');

  const DeliveryStatus(this._label);
  final String _label;
  String get label => t(_label);
}

/// Fiktivni paketomati za demo.
const kDemoLockers = <String>[
  'Paketomat Zagreb – Trg bana Jelačića',
  'Paketomat Zagreb – Arena Centar',
  'Paketomat Split – Riva',
  'Paketomat Rijeka – Korzo',
  'Paketomat Osijek – Trg Ante Starčevića',
];

/// Pošiljka kupljenog predmeta (iz Marketa ili osvojene aukcije).
///
/// Status se ne sprema, nego se računa iz proteklog vremena — tako je isti
/// na svim uređajima i ne treba ga nitko "pomicati".
class Delivery {
  const Delivery({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.buyerId,
    required this.createdAt,
    this.method,
    this.destination,
    this.cost = 0,
    this.trackingNumber,
    this.startedAt,
    this.confirmedAt,
    this.fromAuction = false,
    this.sellerId,
    this.reviewed = false,
    this.dropOffPin,
    this.pickupPin,
  });

  final String id;
  final String deviceId;
  final String deviceName;
  final String buyerId;
  final DateTime createdAt;

  /// `null` dok kupac (pobjednik aukcije) ne odabere način dostave.
  final DeliveryMethod? method;

  /// Adresa ili paketomat (prazno za preuzimanje i digitalnu dostavu).
  final String? destination;
  final double cost;
  final String? trackingNumber;

  /// Kad je dostava stvarno krenula (nakon odabira načina).
  final DateTime? startedAt;

  /// Kupac je potvrdio primitak.
  final DateTime? confirmedAt;
  final bool fromAuction;

  /// Prodavatelj (korisnik) — `null` kad je prodavatelj Subhasto Market.
  final String? sellerId;

  /// Kupac je ocijenio prodavatelja.
  final bool reviewed;

  /// BOX NOW PIN-ovi (nasumični, nastaju kad dostava krene). Ne mogu se
  /// izračunati iz javnog broja pošiljke.
  final String? dropOffPin;
  final String? pickupPin;

  /// Kupac može ocijeniti prodavatelja nakon potvrde primitka.
  bool get canReview => confirmedAt != null && sellerId != null && !reviewed;

  bool get awaitingChoice => method == null;

  /// Koraci za ovaj način dostave.
  List<DeliveryStatus> get steps => switch (method) {
    null => const [DeliveryStatus.awaitingChoice],
    DeliveryMethod.pickup => const [
      DeliveryStatus.ordered,
      DeliveryStatus.packed,
      DeliveryStatus.readyForPickup,
      DeliveryStatus.delivered,
    ],
    DeliveryMethod.digital => const [
      DeliveryStatus.ordered,
      DeliveryStatus.sent,
      DeliveryStatus.delivered,
    ],
    DeliveryMethod.parcelLocker => const [
      DeliveryStatus.ordered,
      DeliveryStatus.shipped,
      DeliveryStatus.inTransit,
      DeliveryStatus.inLocker,
      DeliveryStatus.pickedUp,
    ],
    _ => const [
      DeliveryStatus.ordered,
      DeliveryStatus.shipped,
      DeliveryStatus.inTransit,
      DeliveryStatus.delivered,
    ],
  };

  /// Napredak 0–1 prema proteklom (demo) vremenu.
  double progress(DateTime now) {
    final m = method;
    final start = startedAt;
    if (m == null || start == null) return 0;
    if (confirmedAt != null) return 1;
    final total = Duration(minutes: m.demoMinutes).inSeconds;
    return (now.difference(start).inSeconds / total).clamp(0, 1).toDouble();
  }

  /// Indeks trenutnog koraka u [steps].
  int stepIndex(DateTime now) {
    if (method == null) return 0;
    if (confirmedAt != null) return steps.length - 1;
    final p = progress(now);
    // Zadnji korak (Dostavljeno) tek kad je vrijeme isteklo.
    if (p >= 1) return steps.length - 1;
    return (p * (steps.length - 1)).floor();
  }

  DeliveryStatus status(DateTime now) => steps[stepIndex(now)];

  /// Kada je korak [i] dosegnut (ili se očekuje) — za prikaz datuma uz
  /// svaki korak. Prvi korak (Plaćeno) je trenutak kupnje.
  DateTime? stepAt(int i) {
    final m = method;
    final start = startedAt;
    if (m == null || start == null) return null;
    if (i == 0) return createdAt.isBefore(start) ? createdAt : start;
    final total = Duration(minutes: m.demoMinutes).inSeconds;
    return start.add(
      Duration(seconds: (total * i / (steps.length - 1)).round()),
    );
  }

  /// Stiglo kupcu (dostavljeno, ili preuzeto iz paketomata).
  bool isDelivered(DateTime now) => stepIndex(now) == steps.length - 1;

  /// Paketomat: kupac preuzima sam — preuzimanje se bilježi automatski.
  bool get autoConfirms => method == DeliveryMethod.parcelLocker;

  /// Očekivani trenutak isporuke (demo).
  DateTime? eta() =>
      startedAt?.add(Duration(minutes: method?.demoMinutes ?? 0));

  Delivery copyWith({
    DeliveryMethod? method,
    String? destination,
    double? cost,
    String? trackingNumber,
    DateTime? startedAt,
    DateTime? confirmedAt,
    bool? reviewed,
    String? dropOffPin,
    String? pickupPin,
  }) => Delivery(
    id: id,
    deviceId: deviceId,
    deviceName: deviceName,
    buyerId: buyerId,
    createdAt: createdAt,
    method: method ?? this.method,
    destination: destination ?? this.destination,
    cost: cost ?? this.cost,
    trackingNumber: trackingNumber ?? this.trackingNumber,
    startedAt: startedAt ?? this.startedAt,
    confirmedAt: confirmedAt ?? this.confirmedAt,
    fromAuction: fromAuction,
    sellerId: sellerId,
    reviewed: reviewed ?? this.reviewed,
    dropOffPin: dropOffPin ?? this.dropOffPin,
    pickupPin: pickupPin ?? this.pickupPin,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'buyerId': buyerId,
    'createdAt': createdAt.toIso8601String(),
    'method': method?.name,
    'destination': destination,
    'cost': cost,
    'trackingNumber': trackingNumber,
    'startedAt': startedAt?.toIso8601String(),
    'confirmedAt': confirmedAt?.toIso8601String(),
    'fromAuction': fromAuction,
    'sellerId': sellerId,
    'reviewed': reviewed,
    'dropOffPin': dropOffPin,
    'pickupPin': pickupPin,
  };

  factory Delivery.fromMap(Map<dynamic, dynamic> m) => Delivery(
    id: m['id'] as String,
    deviceId: m['deviceId'] as String,
    deviceName: m['deviceName'] as String,
    buyerId: m['buyerId'] as String,
    createdAt: DateTime.parse(m['createdAt'] as String),
    method: m['method'] == null
        ? null
        : DeliveryMethod.fromName(m['method'] as String),
    destination: m['destination'] as String?,
    cost: (m['cost'] as num?)?.toDouble() ?? 0,
    trackingNumber: m['trackingNumber'] as String?,
    startedAt: m['startedAt'] == null
        ? null
        : DateTime.parse(m['startedAt'] as String),
    confirmedAt: m['confirmedAt'] == null
        ? null
        : DateTime.parse(m['confirmedAt'] as String),
    fromAuction: m['fromAuction'] as bool? ?? false,
    sellerId: m['sellerId'] as String?,
    reviewed: m['reviewed'] as bool? ?? false,
    dropOffPin: m['dropOffPin'] as String?,
    pickupPin: m['pickupPin'] as String?,
  );
}
