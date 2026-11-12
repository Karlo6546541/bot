import '../l10n/tr.dart';

/// Stanje aukcije.
enum AuctionStatus {
  active('U tijeku'),
  sold('Prodano'),
  unsold('Bez ponuda'),
  cancelled('Otkazano');

  const AuctionStatus(this._label);
  final String _label;
  String get label => t(_label);

  static AuctionStatus fromName(String? name) => AuctionStatus.values
      .firstWhere((s) => s.name == name, orElse: () => AuctionStatus.cancelled);
}

/// Vrsta aukcije.
enum AuctionKind {
  /// Klasična: ponude se vide, najviša pobjeđuje.
  classic('Klasična'),

  /// Holandska (padajuća cijena): cijena pada od početne do najniže, a tko
  /// prvi pristane na trenutnu cijenu — kupuje.
  dutch('Holandska'),

  /// Zatvorena: svatko pošalje jednu skrivenu ponudu; na kraju pobjeđuje
  /// najviša i plaća svoj iznos. Ponude se ne vide do kraja.
  sealed('Zatvorena');

  const AuctionKind(this._label);
  final String _label;
  String get label => t(_label);

  static AuctionKind fromName(String? name) => AuctionKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => AuctionKind.classic,
  );
}

/// Jedna ponuda. Ponude su obvezujuće — nikad se ne brišu ni mijenjaju.
class Bid {
  const Bid({
    required this.userId,
    required this.userLabel,
    required this.amount,
    required this.time,
  });

  final String userId;

  /// E-mail ponuđača u trenutku ponude (ostaje čitljiv i nakon brisanja).
  final String userLabel;
  final double amount;
  final DateTime time;

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'userLabel': userLabel,
    'amount': amount,
    'time': time.toIso8601String(),
  };

  factory Bid.fromMap(Map<dynamic, dynamic> map) => Bid(
    userId: map['userId'] as String,
    userLabel: map['userLabel'] as String,
    amount: (map['amount'] as num).toDouble(),
    time: DateTime.parse(map['time'] as String),
  );
}

/// Aukcija jednog predmeta iz portfolija prodavatelja.
///
/// Dok je aukcija aktivna, predmet ostaje u portfoliju prodavatelja, ali se
/// ne može prodati ni ponuditi na drugoj aukciji. Iznos vodeće ponude je
/// blokiran (oduzet sa stanja vodećeg ponuđača) i vraća mu se čim ga netko
/// nadmaši ili se aukcija otkaže.
class Auction {
  const Auction({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.sellerId,
    required this.sellerLabel,
    required this.startPrice,
    required this.createdAt,
    required this.endsAt,
    this.status = AuctionStatus.active,
    this.bids = const [],
    this.listingFee = 0,
    this.buyNowPrice,
    this.autoMax = const {},
    this.watchers = const [],
    this.endingNotified = false,
    this.kind = AuctionKind.classic,
    this.floorPrice = 0,
  });

  final String id;
  final String deviceId;

  /// Naziv predmeta u trenutku objave (za povijest).
  final String deviceName;
  final String sellerId;
  final String sellerLabel;
  final double startPrice;
  final DateTime createdAt;
  final DateTime endsAt;
  final AuctionStatus status;

  /// Ponude od najstarije prema najnovijoj; zadnja je uvijek najviša.
  final List<Bid> bids;

  /// Plaćena naknada za objavu (ne vraća se).
  final double listingFee;

  /// "Kupi odmah": tko plati ovu cijenu odmah osvaja predmet (dok ponude
  /// ne dosegnu tu cijenu). `null` = nema.
  final double? buyNowPrice;

  /// Automatske ponude: korisnik → najviše koliko je spreman dati. Aukcija
  /// licitira umjesto njega najmanjim korakom do tog iznosa.
  final Map<String, double> autoMax;

  /// Korisnici koji prate aukciju (zvono) — dobiju obavijest pred kraj.
  final List<String> watchers;

  /// Obavijest "završava uskoro" je poslana.
  final bool endingNotified;

  /// Vrsta aukcije (klasična, holandska ili zatvorena).
  final AuctionKind kind;

  /// Holandska: najniža cijena na kraju vremena ([startPrice] je najviša).
  final double floorPrice;

  bool get isDutch => kind == AuctionKind.dutch;
  bool get isSealed => kind == AuctionKind.sealed;

  /// Zatvorena aukcija dok traje: ponude i vodeći se ne smiju vidjeti.
  bool get bidsHidden => isSealed && isActive;

  /// Holandska: cijena u trenutku [at] (linearno pada od početne do najniže
  /// cijene do kraja aukcije), zaokruženo na centе.
  double priceAt(DateTime at) {
    if (!isDutch) return currentPrice;
    final total = endsAt.difference(createdAt).inMilliseconds;
    if (total <= 0) return floorPrice;
    final done = at.difference(createdAt).inMilliseconds.clamp(0, total);
    final price = startPrice - (startPrice - floorPrice) * (done / total);
    return (price * 100).round() / 100;
  }

  /// Osnovica za proviziju: kod holandske najniža cijena (ispod nje
  /// prodavatelj ne prodaje), inače početna cijena.
  double get commissionBase => isDutch ? floorPrice : startPrice;

  /// Do kad vrijedi "Kupi odmah" (dok cijena nije dosegnula tu cijenu).
  bool get canBuyNow =>
      isActive && buyNowPrice != null && currentPrice < buyNowPrice!;

  /// Najveći iznos do kojeg korisnik licitira automatski (ili `null`).
  double? autoMaxOf(String userId) => autoMax[userId];

  bool get isActive => status == AuctionStatus.active;

  Bid? get highestBid => bids.isEmpty ? null : bids.last;

  /// Oznaka statusa iz perspektive [viewerId]: prodavatelj vidi
  /// "Prodano", pobjednik "Osvojeno", a svi ostali "Završeno".
  String statusLabelFor(String? viewerId) {
    if (status != AuctionStatus.sold || viewerId == sellerId) {
      return status.label;
    }
    return highestBid?.userId == viewerId ? t('Osvojeno') : t('Završeno');
  }

  /// Trenutna cijena: najviša ponuda ili početna cijena. Holandska: cijena
  /// koja pada s vremenom; zatvorena (dok traje): početna cijena (ponude
  /// su skrivene).
  double get currentPrice {
    if (isDutch && isActive) return priceAt(DateTime.now());
    if (bidsHidden) return startPrice;
    return highestBid?.amount ?? startPrice;
  }

  bool isExpired(DateTime now) => !now.isBefore(endsAt);

  /// Najmanji korak povećanja: 5% trenutne cijene, najmanje 1 €.
  double get minIncrement => stepFor(currentPrice);

  /// Korak licitiranja: uvijek 1 € (i na aukcijama i u liveu).
  static double stepFor(double price) => 1;

  /// Najmanja dopuštena sljedeća ponuda.
  double get minNextBid =>
      isSealed || highestBid == null ? startPrice : currentPrice + minIncrement;

  Auction copyWith({
    AuctionStatus? status,
    List<Bid>? bids,
    DateTime? endsAt,
    Map<String, double>? autoMax,
    List<String>? watchers,
    bool? endingNotified,
  }) => Auction(
    id: id,
    deviceId: deviceId,
    deviceName: deviceName,
    sellerId: sellerId,
    sellerLabel: sellerLabel,
    startPrice: startPrice,
    createdAt: createdAt,
    endsAt: endsAt ?? this.endsAt,
    status: status ?? this.status,
    bids: bids ?? this.bids,
    listingFee: listingFee,
    buyNowPrice: buyNowPrice,
    autoMax: autoMax ?? this.autoMax,
    watchers: watchers ?? this.watchers,
    endingNotified: endingNotified ?? this.endingNotified,
    kind: kind,
    floorPrice: floorPrice,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'sellerId': sellerId,
    'sellerLabel': sellerLabel,
    'startPrice': startPrice,
    'createdAt': createdAt.toIso8601String(),
    'endsAt': endsAt.toIso8601String(),
    'status': status.name,
    'bids': [for (final b in bids) b.toMap()],
    'listingFee': listingFee,
    'buyNowPrice': buyNowPrice,
    'autoMax': autoMax,
    'watchers': watchers,
    'endingNotified': endingNotified,
    if (kind != AuctionKind.classic) 'kind': kind.name,
    if (floorPrice > 0) 'floorPrice': floorPrice,
  };

  factory Auction.fromMap(Map<dynamic, dynamic> map) => Auction(
    id: map['id'] as String,
    deviceId: map['deviceId'] as String,
    deviceName: map['deviceName'] as String,
    sellerId: map['sellerId'] as String,
    sellerLabel: map['sellerLabel'] as String,
    startPrice: (map['startPrice'] as num).toDouble(),
    createdAt: DateTime.parse(map['createdAt'] as String),
    endsAt: DateTime.parse(map['endsAt'] as String),
    status: AuctionStatus.fromName(map['status'] as String?),
    bids: [
      for (final b in (map['bids'] as List? ?? const [])) Bid.fromMap(b as Map),
    ],
    listingFee: (map['listingFee'] as num?)?.toDouble() ?? 0,
    buyNowPrice: (map['buyNowPrice'] as num?)?.toDouble(),
    autoMax: {
      for (final e in ((map['autoMax'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
    watchers: (map['watchers'] as List?)?.cast<String>() ?? const [],
    endingNotified: map['endingNotified'] as bool? ?? false,
    kind: AuctionKind.fromName(map['kind'] as String?),
    floorPrice: (map['floorPrice'] as num?)?.toDouble() ?? 0,
  );
}
