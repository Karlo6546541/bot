import '../l10n/tr.dart';

enum TransactionType {
  buy('Kupnja'),
  sell('Prodaja'),
  topUp('Uplata'),
  auctionFee('Objava aukcije'),
  delivery('Dostava'),
  swap('Zamjena'),
  promotion('Isticanje računa');

  const TransactionType(this._label);
  final String _label;
  String get label => t(_label);
}

/// Zapis jedne transakcije. Kupac/prodavatelj su spremljeni i kao ID i kao
/// e-mail, kako bi povijest ostala čitljiva i nakon brisanja korisnika.
/// `null` ID znači da je druga strana LOOP Market (platforma).
class LoopTransaction {
  const LoopTransaction({
    required this.id,
    required this.type,
    required this.userId,
    required this.deviceId,
    required this.deviceName,
    required this.price,
    required this.fee,
    required this.amount,
    required this.buyerLabel,
    required this.sellerLabel,
    required this.createdAt,
    this.buyerId,
    this.sellerId,
    this.isAuction = false,
  });

  final String id;
  final TransactionType type;

  /// Korisnik koji je pokrenuo transakciju (njemu se prikazuje u Aktivnosti).
  final String userId;
  final String deviceId;
  final String deviceName;

  /// Cijena uređaja (osnovica za fee).
  final double price;

  /// Fee koji je zadržala platforma.
  final double fee;

  /// Iznos kredita koji je korisnik dobio (prodaja) ili platio (kupnja).
  final double amount;
  final String? buyerId;
  final String? sellerId;
  final String buyerLabel;
  final String sellerLabel;
  final DateTime createdAt;

  /// Transakcija je nastala završetkom aukcije. Takav zapis postoji jednom
  /// i vrijedi za obje strane: prodavatelju je prodaja ([userId]),
  /// pobjedniku ([buyerId]) kupnja.
  final bool isAuction;

  bool involves(String userId) =>
      this.userId == userId || (isAuction && buyerId == userId);

  bool _isAuctionBuyer(String userId) => isAuction && buyerId == userId;

  /// Tip iz perspektive korisnika.
  TransactionType typeFor(String userId) =>
      _isAuctionBuyer(userId) ? TransactionType.buy : type;

  /// Iznos koji je korisnik dobio (prodaja) ili platio (kupnja).
  double amountFor(String userId) => _isAuctionBuyer(userId) ? price : amount;

  /// Fee koji je korisnik platio (na aukciji ga plaća samo prodavatelj).
  double feeFor(String userId) => _isAuctionBuyer(userId) ? 0 : fee;

  /// Kopija u kojoj je ime obrisanog korisnika zamijenjeno s [label].
  LoopTransaction anonymize(String userId, String label) => LoopTransaction(
    id: id,
    type: type,
    userId: this.userId,
    deviceId: deviceId,
    deviceName: deviceName,
    price: price,
    fee: fee,
    amount: amount,
    buyerId: buyerId,
    sellerId: sellerId,
    buyerLabel: buyerId == userId ? label : buyerLabel,
    sellerLabel: sellerId == userId ? label : sellerLabel,
    createdAt: createdAt,
    isAuction: isAuction,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'userId': userId,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'price': price,
    'fee': fee,
    'amount': amount,
    'buyerId': buyerId,
    'sellerId': sellerId,
    'buyerLabel': buyerLabel,
    'sellerLabel': sellerLabel,
    'createdAt': createdAt.toIso8601String(),
    'isAuction': isAuction,
  };

  factory LoopTransaction.fromMap(Map<dynamic, dynamic> map) => LoopTransaction(
    id: map['id'] as String,
    type: TransactionType.values.byName(map['type'] as String),
    userId: map['userId'] as String,
    deviceId: map['deviceId'] as String,
    deviceName: map['deviceName'] as String,
    price: (map['price'] as num).toDouble(),
    fee: (map['fee'] as num).toDouble(),
    amount: (map['amount'] as num).toDouble(),
    buyerId: map['buyerId'] as String?,
    sellerId: map['sellerId'] as String?,
    buyerLabel: map['buyerLabel'] as String,
    sellerLabel: map['sellerLabel'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
    isAuction: map['isAuction'] as bool? ?? false,
  );
}
