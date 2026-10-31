import '../l10n/tr.dart';

enum BargainStatus {
  pending('Čeka odgovor'),
  countered('Protuponuda'),
  accepted('Prihvaćeno'),
  declined('Odbijeno'),
  cancelled('Povučeno'),
  used('Iskorišteno'),
  expired('Isteklo');

  const BargainStatus(this._label);
  final String _label;
  String get label => t(_label);

  static BargainStatus fromName(String? n) => BargainStatus.values.firstWhere(
    (s) => s.name == n,
    orElse: () => BargainStatus.pending,
  );
}

/// Ponuda cijene (cjenkanje): kupac nudi [amount] za objavljeni predmet,
/// prodavatelj prihvaća, odbija ili daje protuponudu ([counterAmount]).
/// Prihvaćena cijena vrijedi do [validUntil] i samo za tog kupca.
class PriceOffer {
  const PriceOffer({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.buyerId,
    required this.sellerId,
    required this.amount,
    required this.listPrice,
    required this.createdAt,
    this.counterAmount,
    this.status = BargainStatus.pending,
    this.updatedAt,
    this.validUntil,
  });

  final String id;
  final String deviceId;
  final String deviceName;
  final String buyerId;
  final String sellerId;

  /// Iznos koji nudi kupac.
  final double amount;

  /// Cijena oglasa u trenutku ponude.
  final double listPrice;
  final double? counterAmount;
  final BargainStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? validUntil;

  /// Koliko dugo vrijedi prihvaćena cijena.
  static const acceptedFor = Duration(hours: 48);

  /// Ponuda bez odgovora istječe nakon ovoliko vremena.
  static const pendingFor = Duration(days: 3);

  /// Najniža ponuda: ovoliki postotak cijene oglasa.
  static const minPercent = 30;

  /// Dogovorena cijena (protuponuda ako je kupac prihvatio nju).
  double get agreedPrice => counterAmount ?? amount;

  bool get isOpen =>
      status == BargainStatus.pending || status == BargainStatus.countered;

  /// Prihvaćena i još vrijedi u [now].
  bool usableAt(DateTime now) =>
      status == BargainStatus.accepted &&
      validUntil != null &&
      now.isBefore(validUntil!);

  /// Otvorena ponuda koja je predugo bez odgovora.
  bool staleAt(DateTime now) =>
      isOpen && now.difference(updatedAt ?? createdAt) > pendingFor;

  PriceOffer copyWith({
    BargainStatus? status,
    double? counterAmount,
    DateTime? updatedAt,
    DateTime? validUntil,
  }) => PriceOffer(
    id: id,
    deviceId: deviceId,
    deviceName: deviceName,
    buyerId: buyerId,
    sellerId: sellerId,
    amount: amount,
    listPrice: listPrice,
    createdAt: createdAt,
    counterAmount: counterAmount ?? this.counterAmount,
    status: status ?? this.status,
    updatedAt: updatedAt ?? this.updatedAt,
    validUntil: validUntil ?? this.validUntil,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'buyerId': buyerId,
    'sellerId': sellerId,
    'amount': amount,
    'listPrice': listPrice,
    'counterAmount': counterAmount,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'validUntil': validUntil?.toIso8601String(),
  };

  factory PriceOffer.fromMap(Map<dynamic, dynamic> m) => PriceOffer(
    id: m['id'] as String,
    deviceId: m['deviceId'] as String,
    deviceName: m['deviceName'] as String? ?? '',
    buyerId: m['buyerId'] as String,
    sellerId: m['sellerId'] as String,
    amount: (m['amount'] as num).toDouble(),
    listPrice: (m['listPrice'] as num?)?.toDouble() ?? 0,
    counterAmount: (m['counterAmount'] as num?)?.toDouble(),
    status: BargainStatus.fromName(m['status'] as String?),
    createdAt: DateTime.parse(m['createdAt'] as String),
    updatedAt: m['updatedAt'] == null
        ? null
        : DateTime.parse(m['updatedAt'] as String),
    validUntil: m['validUntil'] == null
        ? null
        : DateTime.parse(m['validUntil'] as String),
  );
}
