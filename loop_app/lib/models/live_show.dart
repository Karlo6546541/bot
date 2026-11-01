import '../l10n/tr.dart';

/// Live aukcija (kao Whatnot): prodavatelj ide uživo, pokazuje predmete i
/// za svaki sam pokreće kratku licitaciju. Live traje dok je domaćin uživo —
/// predmete može dodavati usput, a kraj je kad ga završi ili ode.
///
/// Emisiju mijenja samo domaćin (početak licitacije, novi predmeti, "još sam
/// tu"), a ponude i chat su zasebni zapisi. Ponuda u zadnjih
/// [LiveShow.bidBonus] produljuje licitaciju. Zato svaki uređaj iz
/// istih podataka izračuna isto stanje, bez središnjeg poslužitelja.
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
    this.video = false,
    this.hostSeenAt,
    this.coverPath,
    this.category,
    this.relistUnsold = true,
    this.modIds = const [],
    this.verifiedOnly = false,
    this.summary,
  });

  final String id;
  final String hostId;
  final String hostLabel;
  final String title;

  /// Najavljeni početak (odmah ili zakazano).
  final DateTime startsAt;
  final DateTime createdAt;

  /// Predmeti u liveu (domaćin ih može dodavati i tijekom livea).
  final List<LiveLot> lots;

  /// Trajanje licitacije jednog predmeta.
  final int lotSeconds;

  /// Domaćin je završio live.
  final DateTime? endedAt;

  /// Indeksi predmeta čija je prodaja već provedena.
  final List<int> settled;

  /// Domaćin prenosi video s kamere (inače se prikazuju fotografije).
  final bool video;

  /// Zadnji znak da je domaćin u sobi (osvježava se dok je uživo).
  final DateTime? hostSeenAt;

  /// Naslovna slika (thumbnail) emisije — prikazuje se na kartici i dok
  /// live ne krene.
  final String? coverPath;

  /// Glavna kategorija emisije (naziv iz [DeviceCategory]).
  final String? category;

  /// Neprodani predmeti nakon livea idu na Kupi odmah po početnoj cijeni.
  final bool relistUnsold;

  /// Moderatori koje je postavio domaćin (utišavaju i uklanjaju gledatelje).
  final List<String> modIds;

  /// Licitirati smiju samo provjereni kupci ([AppUser] s karticom koji su
  /// već kupovali ili imaju potvrđenu e-poštu).
  final bool verifiedOnly;

  /// Sažetak analitike (gledatelji, ponude, prosječno gledanje, novi
  /// pratitelji), spremljen prije brisanja zapisa u sobi.
  final Map<String, num>? summary;

  bool isMod(String? userId) => userId != null && modIds.contains(userId);

  /// Domaćin ili moderator.
  bool canModerate(String? userId) => userId == hostId || isMod(userId);

  static const maxMods = 5;
  static const maxTitle = 60;
  static const maxLots = 50;

  /// Trgovci (obrt, tvrtka).
  static const businessMaxLots = 200;

  /// Trajanje licitacije jednog predmeta (5 i 10 s = brze licitacije).
  static const lotDurations = [5, 10, 15, 20, 30, 45, 60];

  /// Svaka prihvaćena ponuda dok sat teče dodaje toliko vremena.
  static const bidBonus = Duration(seconds: 2);

  /// Zadnje sekunde licitacije (sat crveni, "+2 s" se ističe).
  static const hotWindow = Duration(seconds: 5);

  /// Live se ne može zakazati dalje od ovoga.
  static const maxScheduleAhead = Duration(days: 7);

  /// Domaćin se javlja svakih toliko dok je u sobi.
  static const heartbeat = Duration(seconds: 30);

  /// Bez znaka domaćina ovoliko dugo — live je gotov (otišao je).
  static const hostTimeout = Duration(minutes: 2);

  /// Zakazani live na koji domaćin ne dođe nestaje nakon ovoga.
  static const noShow = Duration(hours: 1);

  LiveShow copyWith({
    DateTime? endedAt,
    List<int>? settled,
    List<LiveLot>? lots,
    DateTime? hostSeenAt,
    List<String>? modIds,
    bool? verifiedOnly,
    Map<String, num>? summary,
  }) => LiveShow(
    id: id,
    hostId: hostId,
    hostLabel: hostLabel,
    title: title,
    startsAt: startsAt,
    createdAt: createdAt,
    lots: lots ?? this.lots,
    lotSeconds: lotSeconds,
    endedAt: endedAt ?? this.endedAt,
    settled: settled ?? this.settled,
    video: video,
    hostSeenAt: hostSeenAt ?? this.hostSeenAt,
    coverPath: coverPath,
    category: category,
    relistUnsold: relistUnsold,
    modIds: modIds ?? this.modIds,
    verifiedOnly: verifiedOnly ?? this.verifiedOnly,
    summary: summary ?? this.summary,
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
    'video': video,
    'hostSeenAt': hostSeenAt?.toIso8601String(),
    'coverPath': coverPath,
    'category': category,
    'relistUnsold': relistUnsold,
    if (modIds.isNotEmpty) 'modIds': modIds,
    if (verifiedOnly) 'verifiedOnly': true,
    if (summary != null) 'summary': summary,
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
    video: m['video'] == true,
    hostSeenAt: m['hostSeenAt'] == null
        ? null
        : DateTime.tryParse('${m['hostSeenAt']}'),
    coverPath: m['coverPath'] as String?,
    category: m['category'] as String?,
    relistUnsold: m['relistUnsold'] != false,
    modIds: [for (final i in (m['modIds'] as List? ?? const [])) '$i'],
    verifiedOnly: m['verifiedOnly'] == true,
    summary: m['summary'] is Map
        ? {
            for (final e in (m['summary'] as Map).entries)
              '${e.key}': (e.value as num?) ?? 0,
          }
        : null,
  );
}

/// Kako se predmet prodaje u liveu.
enum LotMode {
  /// Klasična licitacija: najviša ponuda pobjeđuje.
  auction('🔨', 'Licitacija'),

  /// Padajuća cijena (nizozemska aukcija): cijena pada svake sekunde, a
  /// prvi koji uzme — kupuje. Toga na Whatnotu nema.
  dutch('⬇️', 'Pada cijena'),

  /// Nagradna igra: gledatelji se prijave, dobitnik se izvlači.
  giveaway('🎁', 'Nagradna igra');

  const LotMode(this.emoji, this._label);
  final String emoji;
  final String _label;
  String get label => t(_label);
}

/// Jedan predmet u live aukciji.
class LiveLot {
  const LiveLot({
    required this.deviceId,
    required this.deviceName,
    required this.startPrice,
    this.startedAt,
    this.mode = LotMode.auction,
    this.floorPrice = 1,
    this.seconds,
    this.followersOnly = false,
  });

  /// Trajanje samo za ovaj predmet (nagradna igra: do 5 minuta); inače
  /// vrijedi [LiveShow.lotSeconds].
  final int? seconds;

  /// Nagradna igra: sudjeluju samo pratitelji domaćina.
  final bool followersOnly;

  /// Trajanja nagradne igre (kao Whatnot: najviše 5 minuta).
  static const giveawaySeconds = [60, 120, 180, 300];

  final String deviceId;
  final String deviceName;

  /// Licitacija: početna cijena. Pada cijena: cijena na početku (najviša).
  final double startPrice;

  /// Kad je domaćin pokrenuo licitaciju (null = čeka na red).
  final DateTime? startedAt;
  final LotMode mode;

  /// Pada cijena: najniža cijena (na kraju vremena).
  final double floorPrice;

  /// Cijena od koje se računa provizija (10 % razlike): početna cijena,
  /// a kod padajuće cijene najniža (ispod nje prodavatelj ne prodaje).
  double get basePrice => mode == LotMode.dutch ? floorPrice : startPrice;

  /// Korak licitiranja u liveu: uvijek 1 € (bez obzira na cijenu).
  static double increment(double price) => 1;

  /// Pada cijena: koliko predmet košta nakon [elapsed] od početka.
  double dutchPrice(Duration elapsed, int seconds) {
    final f = (elapsed.inMilliseconds / (seconds * 1000)).clamp(0.0, 1.0);
    final p = startPrice - (startPrice - floorPrice) * f;
    return p.ceilToDouble().clamp(floorPrice, startPrice);
  }

  LiveLot started(DateTime at) => LiveLot(
    deviceId: deviceId,
    deviceName: deviceName,
    startPrice: startPrice,
    startedAt: at,
    mode: mode,
    floorPrice: floorPrice,
    seconds: seconds,
    followersOnly: followersOnly,
  );

  Map<String, dynamic> toMap() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'startPrice': startPrice,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (mode != LotMode.auction) 'mode': mode.name,
    if (mode == LotMode.dutch) 'floorPrice': floorPrice,
    if (seconds != null) 'seconds': seconds,
    if (followersOnly) 'followersOnly': true,
  };

  factory LiveLot.fromMap(Map<dynamic, dynamic> m) => LiveLot(
    deviceId: m['deviceId'] as String,
    deviceName: m['deviceName'] as String? ?? '',
    startPrice: (m['startPrice'] as num).toDouble(),
    startedAt: m['startedAt'] == null
        ? null
        : DateTime.tryParse('${m['startedAt']}'),
    mode: LotMode.values.firstWhere(
      (v) => v.name == m['mode'],
      orElse: () => LotMode.auction,
    ),
    floorPrice: (m['floorPrice'] as num?)?.toDouble() ?? 1,
    seconds: (m['seconds'] as num?)?.toInt(),
    followersOnly: m['followersOnly'] == true,
  );
}

/// Vrsta događaja u live aukciji: ponuda, poruka, ulazak, "uzimam"
/// (pada cijena), prijava na nagradnu igru, procjena cijene (stari zapisi
/// uklonjene igre "Pogodi cijenu" — ne koriste se) i "podsjeti me"
/// (zakazani live).
enum LiveEventType {
  bid,
  chat,
  join,
  take,
  enter,
  guess,
  remind,
  mod,

  /// Gledatelj je u sobi: javlja se svake minute, [LiveEvent.amount] je
  /// broj sekundi od zadnjeg javljanja (za prosječno vrijeme gledanja).
  watch,

  /// Gledatelj je zapratio domaćina iz sobe showa.
  follow,

  /// Domaćin je prije vremena završio nagradnu igru ([LiveEvent.lot]).
  stop,

  /// Domaćin je platio promociju: [LiveEvent.text] je vrsta (`quick` ili
  /// `show`), [LiveEvent.amount] plaćeni iznos (vidi `LiveBoost`).
  boost,

  /// Gledatelj je podijelio show (za community boost).
  share,

  /// Domaćin je na kraju showa poslao gledatelje u drugi live (raid):
  /// [LiveEvent.text] je ID tog showa.
  raid,
}

/// Radnje moderacije: tekst događaja [LiveEventType.mod] je `radnja:korisnik`.
const modMute = 'mute';
const modUnmute = 'unmute';
const modBan = 'ban';

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

  /// Kopija s drugim iznosom (npr. cijena "uzimam" izračunata iz vremena).
  LiveEvent withAmount(double value) => LiveEvent(
    id: id,
    showId: showId,
    type: type,
    userId: userId,
    userLabel: userLabel,
    at: at,
    lot: lot,
    amount: value,
    text: text,
  );

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
