import '../l10n/tr.dart';
import '../utils/formatters.dart';

/// Vrsta obavijesti — određuje tekst i kamo vodi dodir.
enum NotificationKind {
  outbid('🔔', 'Netko te nadmašio na aukciji "{0}" — nova ponuda {1}.'),
  newBid('🔨', 'Nova ponuda na tvojoj aukciji "{0}": {1}.'),
  auctionWon('🏆', 'Osvojio si aukciju "{0}" za {1}. Odaberi dostavu.'),
  giveawayWon('🎁', 'Osvojio si "{0}" u nagradnoj igri {1}. Odaberi dostavu.'),
  auctionLost('😕', 'Aukcija "{0}" je završila — nisi pobijedio.'),
  auctionSold('💰', 'Tvoja aukcija "{0}" je završila: prodano za {1}.'),
  auctionUnsold('⏱️', 'Tvoja aukcija "{0}" je završila bez ponuda.'),
  itemSold('🎉', '{1} je kupio tvoj predmet "{0}". Dobivaš {2}.'),
  priceDrop('📉', 'Predmet s tvoje liste želja "{0}" je pojeftinio na {1}.'),
  newReview('⭐', '{0} te ocijenio: {1}'),
  referral('🎁', '{0} se registrirao s tvojim kodom.'),
  newMessage('💬', 'Nova poruka od {0}: {1}'),
  swapOffer('🔄', '{0} ti nudi zamjenu za "{1}".'),
  swapAccepted('🤝', '{0} je prihvatio zamjenu za "{1}".'),
  swapDeclined('✖️', '{0} je odbio zamjenu za "{1}".'),
  reportResolved('🛡️', 'Tvoja prijava je obrađena. Hvala!'),
  bargainNew('💶', '{0} nudi {1} za "{2}".'),
  bargainAccepted(
    '✅',
    '{0} je prihvatio tvoju ponudu od {1} za "{2}". Kupi u roku od 48 sati.',
  ),
  bargainDeclined('✖️', 'Ponuda za "{1}" je odbijena ({0}).'),
  bargainCountered('↩️', '{0} ti daje protuponudu {1} za "{2}".'),
  counterAccepted('🤝', '{0} je prihvatio protuponudu {1} za "{2}".'),
  newFollower('👤', '{0} te sada prati.'),
  followedNewItem('🆕', '{0} je objavio novi oglas: "{1}" za {2}.'),
  followedDiscount('🏷️', '{0}: popust −{1}% na "{2}" — sada {3}.'),
  soldOut('📦', 'Rasprodano: "{0}" — prodan je zadnji komad.'),
  followedAuction('🔨', '{0} je pokrenuo aukciju: "{1}" od {2}.'),
  auctionEndingSoon(
    '⏰',
    'Aukcija "{0}" završava za manje od 10 minuta — trenutno {1}.',
  ),
  outbidAuto(
    '🤖',
    'Automatska ponuda drugog kupca je viša na aukciji "{0}" — sada {1}.',
  ),
  contentRemoved(
    '🛡️',
    'Tvoj oglas "{0}" je uklonjen. Razlog: {1}. Ako se ne slažeš, podnesi žalbu.',
  ),
  liveStarted('🔴', '{0} ide uživo: "{1}" ({2}).'),
  shipReady(
    '📦',
    '{0} je odabrao dostavu za "{1}" — kod za paketomat je spreman.',
  ),
  parcelPickedUp('✅', '{0} je preuzeo "{1}" iz paketomata.'),
  parcelArrived(
    '📬',
    '"{0}" te čeka u paketomatu {1}. PIN za preuzimanje: {2}',
  );

  const NotificationKind(this.emoji, this._template);
  final String emoji;
  final String _template;

  static NotificationKind fromName(String? n) => NotificationKind.values
      .firstWhere((k) => k.name == n, orElse: () => NotificationKind.newBid);

  /// Skupina za filtre na ekranu obavijesti.
  NotificationGroup get group => switch (this) {
    outbid ||
    outbidAuto ||
    newBid ||
    auctionWon ||
    giveawayWon ||
    auctionLost ||
    auctionSold ||
    auctionUnsold ||
    followedAuction ||
    liveStarted ||
    auctionEndingSoon => NotificationGroup.auctions,
    itemSold ||
    shipReady ||
    parcelPickedUp ||
    parcelArrived ||
    priceDrop ||
    soldOut ||
    followedNewItem ||
    followedDiscount => NotificationGroup.trade,
    bargainNew ||
    bargainAccepted ||
    bargainDeclined ||
    bargainCountered ||
    counterAccepted ||
    swapOffer ||
    swapAccepted ||
    swapDeclined => NotificationGroup.offers,
    newMessage => NotificationGroup.messages,
    newReview ||
    referral ||
    newFollower ||
    reportResolved ||
    contentRemoved => NotificationGroup.social,
  };

  /// Obavijesti o aukciji na kojoj korisnik licitira (gumb "Licitiraj").
  bool get invitesBid =>
      this == outbid ||
      this == outbidAuto ||
      this == auctionEndingSoon ||
      this == followedAuction;
}

/// Skupine obavijesti (filteri).
enum NotificationGroup {
  auctions('🔨', 'Aukcije'),
  trade('🛍️', 'Kupnje i prodaje'),
  offers('💶', 'Ponude'),
  social('👥', 'Društvo'),
  messages('💬', 'Poruke');

  const NotificationGroup(this.emoji, this._label);
  final String emoji;
  final String _label;
  String get label => t(_label);
}

/// Obavijesti koje korisnik može isključiti (Postavke obavijesti). Važne
/// obavijesti (rezultat aukcije, prodaja, poruke, ponude) uvijek stižu.
enum NotificationPref {
  outbid(
    NotificationGroup.auctions,
    'Netko me nadmašio',
    'Kad tvoja ponuda više nije najviša (i automatska).',
    [NotificationKind.outbid, NotificationKind.outbidAuto],
  ),
  newBid(
    NotificationGroup.auctions,
    'Nove ponude na mojim aukcijama',
    'Svaka nova ponuda na aukciji koju si pokrenuo.',
    [NotificationKind.newBid],
  ),
  endingSoon(
    NotificationGroup.auctions,
    'Aukcija uskoro završava',
    '10 minuta prije kraja aukcija koje pratiš ili na kojima licitiraš.',
    [NotificationKind.auctionEndingSoon],
  ),
  followedAuction(
    NotificationGroup.auctions,
    'Nove aukcije trgovina koje pratim',
    'Kad trgovina koju pratiš pokrene aukciju ili live.',
    [NotificationKind.followedAuction, NotificationKind.liveStarted],
  ),
  priceDrop(
    NotificationGroup.trade,
    'Pojeftinjenja',
    'Kad predmet koji ti se sviđa pojeftini.',
    [NotificationKind.priceDrop],
  ),
  followedShops(
    NotificationGroup.trade,
    'Novi oglasi i popusti trgovina koje pratim',
    'Novi oglasi i sniženja u trgovinama koje pratiš.',
    [NotificationKind.followedNewItem, NotificationKind.followedDiscount],
  ),
  newFollower(
    NotificationGroup.social,
    'Novi pratitelji',
    'Kad te netko počne pratiti.',
    [NotificationKind.newFollower],
  );

  const NotificationPref(this.group, this._title, this._hint, this.kinds);
  final NotificationGroup group;
  final String _title;
  final String _hint;
  final List<NotificationKind> kinds;

  String get title => t(_title);
  String get hint => t(_hint);

  /// Postavka koja uključuje/isključuje [kind] (null = uvijek stiže).
  static NotificationPref? of(NotificationKind kind) =>
      values.where((p) => p.kinds.contains(kind)).firstOrNull;
}

/// Obavijest u aplikaciji. Tekst se gradi pri prikazu (na jeziku
/// korisnika): brojevi u [args] su iznosi u kreditima.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.kind,
    required this.createdAt,
    this.args = const [],
    this.targetId,
    this.read = false,
  });

  final String id;
  final String userId;
  final NotificationKind kind;
  final List<Object> args;

  /// Aukcija, predmet, korisnik ili razgovor — ovisno o [kind].
  final String? targetId;
  final bool read;
  final DateTime createdAt;

  String get text => t(kind._template, [
    for (final a in args) a is num ? formatCredits(a.toDouble()) : a,
  ]);

  AppNotification markRead() => AppNotification(
    id: id,
    userId: userId,
    kind: kind,
    createdAt: createdAt,
    args: args,
    targetId: targetId,
    read: true,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'userId': userId,
    'kind': kind.name,
    'args': args,
    'targetId': targetId,
    'read': read,
    'createdAt': createdAt.toIso8601String(),
  };

  factory AppNotification.fromMap(Map<dynamic, dynamic> m) => AppNotification(
    id: m['id'] as String,
    userId: m['userId'] as String,
    kind: NotificationKind.fromName(m['kind'] as String?),
    args: [for (final a in (m['args'] as List? ?? const [])) a as Object],
    targetId: m['targetId'] as String?,
    read: m['read'] as bool? ?? false,
    createdAt: DateTime.parse(m['createdAt'] as String),
  );
}
