/// Live aukcija (kao Whatnot): prodavatelj "ide uživo" s popisom predmeta
/// koji se licitiraju jedan za drugim, kratko i brzo, uz chat.
///
/// Raspored je deterministički: predmet i počinje [LiveShow.gap] nakon što
/// završi prethodni, a ponuda u zadnjih [LiveShow.suddenDeath] sekundi
/// produljuje licitaciju. Zato svaki uređaj iz istih podataka (emisija +
/// događaji) izračuna isto stanje, bez središnjeg poslužitelja.
class LiveShow {
  const LiveShow({
    required this.id,
    required this.hostId,
    required this.hostLabel,
    required this.title,
    required this.startsAt,
    required this.createdAt,
    required this.lots,
    this.lotSeconds = 30,
    this.endedAt,
    this.settled = const [],
  });

  final String id;
  final String hostId;
  final String hostLabel;
  final String title;

  /// Početak prvog predmeta (odmah ili zakazano).
  final DateTime startsAt;
  final DateTime createdAt;

  /// Predmeti redom kojim se licitiraju.
  final List<LiveLot> lots;

  /// Osnovno trajanje licitacije jednog predmeta.
  final int lotSeconds;

  /// Domaćin je ranije završio live (preostali predmeti se ne licitiraju).
  final DateTime? endedAt;

  /// Indeksi predmeta čija je prodaja već provedena.
  final List<int> settled;

  static const maxTitle = 60;
  static const maxLots = 20;
  static const lotDurations = [20, 30, 45, 60];

  /// Pauza između predmeta.
  static const gap = Duration(seconds: 5);

  /// Ponuda u zadnjih toliko sekundi vraća sat na toliko sekundi.
  static const suddenDeath = Duration(seconds: 10);

  /// Live se ne može zakazati dalje od ovoga.
  static const maxScheduleAhead = Duration(days: 7);

  LiveShow copyWith({DateTime? endedAt, List<int>? settled}) => LiveShow(
    id: id,
    hostId: hostId,
    hostLabel: hostLabel,
    title: title,
    startsAt: startsAt,
    createdAt: createdAt,
    lots: lots,
    lotSeconds: lotSeconds,
    endedAt: endedAt ?? this.endedAt,
    settled: settled ?? this.settled,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'hostId': hostId,
    'hostLabel': hostLabel,
    'title': title,
    'startsAt': startsAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'lots': [for (final l in lots) l.toMap()],
    'lotSeconds': lotSeconds,
    'endedAt': endedAt?.toIso8601String(),
    'settled': settled,
  };

  factory LiveShow.fromMap(Map<dynamic, dynamic> m) => LiveShow(
    id: m['id'] as String,
    hostId: m['hostId'] as String,
    hostLabel: m['hostLabel'] as String? ?? '',
    title: m['title'] as String? ?? '',
    startsAt: DateTime.parse(m['startsAt'] as String),
    createdAt: DateTime.parse(m['createdAt'] as String),
    lots: [
      for (final l in (m['lots'] as List? ?? const []))
        if (l is Map) LiveLot.fromMap(l),
    ],
    lotSeconds: (m['lotSeconds'] as num?)?.toInt() ?? 30,
    endedAt: m['endedAt'] == null
        ? null
        : DateTime.parse(m['endedAt'] as String),
    settled: [
      for (final i in (m['settled'] as List? ?? const [])) (i as num).toInt(),
    ],
  );
}

/// Jedan predmet u live aukciji.
class LiveLot {
  const LiveLot({
    required this.deviceId,
    required this.deviceName,
    required this.startPrice,
  });

  final String deviceId;
  final String deviceName;
  final double startPrice;

  Map<String, dynamic> toMap() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'startPrice': startPrice,
  };

  factory LiveLot.fromMap(Map<dynamic, dynamic> m) => LiveLot(
    deviceId: m['deviceId'] as String,
    deviceName: m['deviceName'] as String? ?? '',
    startPrice: (m['startPrice'] as num).toDouble(),
  );
}

/// Vrsta događaja u live aukciji.
enum LiveEventType { bid, chat, join }

/// Ponuda, poruka u chatu ili ulazak gledatelja. Svaki događaj je zaseban
/// zapis (ne mijenja se emisija), pa se istovremene ponude s više uređaja
/// ne prepisuju međusobno.
class LiveEvent {
  const LiveEvent({
    required this.id,
    required this.showId,
    required this.type,
    required this.userId,
    required this.userLabel,
    required this.at,
    this.lot = 0,
    this.amount = 0,
    this.text = '',
  });

  final String id;
  final String showId;
  final LiveEventType type;
  final String userId;
  final String userLabel;
  final DateTime at;

  /// Predmet na koji se ponuda odnosi.
  final int lot;
  final double amount;
  final String text;

  static const maxText = 140;

  Map<String, dynamic> toMap() => {
    'id': id,
    'showId': showId,
    'type': type.name,
    'userId': userId,
    'userLabel': userLabel,
    'at': at.toIso8601String(),
    'lot': lot,
    'amount': amount,
    'text': text,
  };

  factory LiveEvent.fromMap(Map<dynamic, dynamic> m) => LiveEvent(
    id: m['id'] as String,
    showId: m['showId'] as String,
    type: LiveEventType.values.firstWhere(
      (v) => v.name == m['type'],
      orElse: () => LiveEventType.chat,
    ),
    userId: m['userId'] as String,
    userLabel: m['userLabel'] as String? ?? '',
    at: DateTime.parse(m['at'] as String),
    lot: (m['lot'] as num?)?.toInt() ?? 0,
    amount: (m['amount'] as num?)?.toDouble() ?? 0,
    text: m['text'] as String? ?? '',
  );
}
