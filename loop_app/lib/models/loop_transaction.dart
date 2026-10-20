enum TransactionType {
  buy('Kupnja'),
  sell('Prodaja');

  const TransactionType(this.label);
  final String label;
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
  );
}
