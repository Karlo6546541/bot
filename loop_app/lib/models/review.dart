/// Ocjena prodavatelja nakon primljene pošiljke (1–5 zvjezdica + komentar).
class Review {
  const Review({
    required this.id,
    required this.sellerId,
    required this.buyerId,
    required this.buyerLabel,
    required this.deliveryId,
    required this.deviceName,
    required this.stars,
    required this.createdAt,
    this.comment = '',
  });

  final String id;
  final String sellerId;
  final String buyerId;
  final String buyerLabel;
  final String deliveryId;
  final String deviceName;

  /// 1–5.
  final int stars;
  final String comment;
  final DateTime createdAt;

  static const maxComment = 200;

  Map<String, dynamic> toMap() => {
    'id': id,
    'sellerId': sellerId,
    'buyerId': buyerId,
    'buyerLabel': buyerLabel,
    'deliveryId': deliveryId,
    'deviceName': deviceName,
    'stars': stars,
    'comment': comment,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Review.fromMap(Map<dynamic, dynamic> m) => Review(
    id: m['id'] as String,
    sellerId: m['sellerId'] as String,
    buyerId: m['buyerId'] as String,
    buyerLabel: m['buyerLabel'] as String? ?? '',
    deliveryId: m['deliveryId'] as String? ?? '',
    deviceName: m['deviceName'] as String? ?? '',
    stars: (m['stars'] as num).toInt(),
    comment: m['comment'] as String? ?? '',
    createdAt: DateTime.parse(m['createdAt'] as String),
  );
}

/// Prosjek i broj ocjena.
class Rating {
  const Rating(this.average, this.count);
  final double average;
  final int count;

  static const none = Rating(0, 0);

  static Rating of(Iterable<Review> reviews) {
    final list = reviews.toList();
    if (list.isEmpty) return none;
    final sum = list.fold<int>(0, (s, r) => s + r.stars);
    return Rating(sum / list.length, list.length);
  }
}
