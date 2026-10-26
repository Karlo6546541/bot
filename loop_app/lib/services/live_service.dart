import 'dart:math';

import 'package:uuid/uuid.dart';

import '../l10n/tr.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/live_show.dart';
import '../models/loop_transaction.dart';
import '../utils/formatters.dart';
import 'delivery_service.dart';
import 'fee.dart';
import 'inbox.dart';
import 'earnings.dart';
import 'storage_service.dart';
import 'trade_service.dart';

/// Stanje jednog predmeta u live aukciji.
/// [upcoming] = čeka da domaćin pokrene licitaciju.
enum LotStatus { upcoming, running, sold, unsold, skipped }

class LotState {
  const LotState({
    required this.index,
    required this.lot,
    required this.start,
    required this.end,
    required this.bids,
    required this.status,
    this.entrants = 0,
    this.maxes = const {},
  });

  final int index;
  final LiveLot lot;
  LotMode get mode => lot.mode;

  /// Nagradna igra: koliko se gledatelja prijavilo.
  final int entrants;

  /// Početak i kraj licitacije (null dok je predmet na čekanju). Kraj
  /// uključuje produljenja zbog ponuda u zadnjim sekundama.
  final DateTime? start;
  final DateTime? end;

  /// Vidljivi koraci cijene redom: svaki je (vodeći, cijena) nakon jedne
  /// prihvaćene ponude. Zadnji vodi. Kod predmeta na čekanju to su
  /// predlicitacije.
  final List<LiveEvent> bids;
  final LotStatus status;

  /// Najviša (maksimalna) ponuda svakog licitanta. Cijena raste samo
  /// koliko treba da vodeći ostane ispred (kao "custom bid" na Whatnotu).
  final Map<String, double> maxes;

  LiveEvent? get leader => bids.isEmpty ? null : bids.last;
  double get price => leader?.amount ?? lot.startPrice;
  double get minNext =>
      leader == null ? lot.startPrice : price + LiveLot.increment(price);

  /// Moja maksimalna ponuda (null ako nisam licitirao).
  double? maxOf(String? userId) => userId == null ? null : maxes[userId];

  /// Broj različitih licitanata.
  int get bidders => maxes.length;

  Duration left(DateTime now) {
    final e = end;
    return e != null && e.isAfter(now) ? e.difference(now) : Duration.zero;
  }

  /// Pada cijena: trenutna cijena (prije nego što netko uzme).
  double dutchPriceAt(DateTime now, int seconds) {
    final s = start;
    return s == null
        ? lot.startPrice
        : lot.dutchPrice(now.difference(s), seconds);
  }
}

/// Stabilan hash (FNV-1a) — isti na svakom uređaju i platformi, za
/// izvlačenje dobitnika nagradne igre.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Izračunato stanje emisije u trenutku [LiveState.at].
class LiveState {
  const LiveState({
    required this.show,
    required this.lots,
    required this.at,
    required this.viewers,
    required this.feed,
    this.hype = 0,
  });

  final LiveShow show;
  final List<LotState> lots;
  final DateTime at;

  /// Hype-metar 0…1: ponude, "uzimam", prijave, procjene i chat u zadnjih
  /// 30 sekundi.
  final double hype;

  /// Gledatelji u zadnjih 5 minuta (ulazak, poruka ili ponuda).
  final int viewers;

  /// Chat i ponude, najnovije zadnje.
  final List<LiveEvent> feed;

  LotState? get current =>
      lots.where((l) => l.status == LotStatus.running).firstOrNull;

  /// Predmeti koji čekaju da ih domaćin pokrene (redom).
  List<LotState> get queue =>
      lots.where((l) => l.status == LotStatus.upcoming).toList();
  LotState? get next => queue.firstOrNull;

  /// Zadnji završeni predmet (za "PRODANO!" između predmeta).
  LotState? get lastDone {
    LotState? best;
    for (final l in lots) {
      if (l.status != LotStatus.sold && l.status != LotStatus.unsold) continue;
      if (best == null || l.end!.isAfter(best.end!)) best = l;
    }
    return best;
  }

  /// Domaćin se nije javio dulje od [LiveShow.hostTimeout].
  bool get hostAway {
    final seen = show.hostSeenAt;
    return seen == null || at.difference(seen) > LiveShow.hostTimeout;
  }

  /// Domaćin još nije došao (zakazani live).
  bool get isScheduled => !isOver && show.hostSeenAt == null;

  /// Live je gotov: domaćin ga je završio, otišao je (i ništa se više ne
  /// licitira) ili nije došao na zakazani termin.
  bool get isOver {
    if (show.endedAt != null) return current == null;
    if (show.hostSeenAt == null) {
      return at.isAfter(show.startsAt.add(LiveShow.noShow));
    }
    return hostAway && current == null;
  }

  bool get isLive => !isOver && !isScheduled;

  /// Domaćin smije pokrenuti sljedeći predmet.
  bool get canStart => isLive && current == null && show.endedAt == null;

  int get soldCount => lots.where((l) => l.status == LotStatus.sold).length;
}

/// Live aukcije: objava, domaćin pokreće predmete, ulazak, chat, ponude i
/// zaključivanje.
class LiveService {
  LiveService(this._storage);

  final StorageService _storage;
  static const _uuid = Uuid();

  /// Gledatelj se broji ovoliko nakon zadnje aktivnosti.
  static const viewerWindow = Duration(minutes: 5);

  // ------------------------------------------------------------ izračun

  /// Stanje emisije iz samih podataka — isto na svakom uređaju.
  /// [hiddenUsers] (npr. blokirani) skriva samo njihove poruke u chatu.
  static LiveState compute(
    LiveShow show,
    List<LiveEvent> events,
    DateTime now, {
    Set<String> hiddenUsers = const {},
  }) {
    // Događaji po (vrsta, predmet), redom kako su se dogodili.
    final byLot = <(LiveEventType, int), List<LiveEvent>>{};
    for (final e in events) {
      (byLot[(e.type, e.lot)] ??= []).add(e);
    }
    for (final list in byLot.values) {
      list.sort((a, b) => a.at.compareTo(b.at));
    }

    // Vidljive ponude za chat (s cijenom nakon automatskog licitiranja —
    // maksimalne ponude se ne prikazuju).
    final bidFeed = <LiveEvent>[];
    final ended = show.endedAt;
    final seen = show.hostSeenAt;
    // Live je gotov za predmete na čekanju (više se neće licitirati).
    final closed =
        ended != null ||
        (seen != null && now.difference(seen) > LiveShow.hostTimeout) ||
        (seen == null && now.isAfter(show.startsAt.add(LiveShow.noShow)));
    final lots = <LotState>[];
    for (var i = 0; i < show.lots.length; i++) {
      final lot = show.lots[i];
      final start = lot.startedAt;
      final allBids = byLot[(LiveEventType.bid, i)] ?? const <LiveEvent>[];
      if (start == null) {
        // Predmet na čekanju: predlicitacije (ponude prije početka).
        final pre = lot.mode == LotMode.auction && !closed
            ? _proxy(lot, allBids.where((b) => !b.at.isAfter(now)), show)
            : null;
        // Predlicitacije se ne prikazuju u chatu (odnose se na drugi
        // predmet) — vide se u popisu predmeta.
        lots.add(
          LotState(
            index: i,
            lot: lot,
            start: null,
            end: null,
            bids: pre?.steps ?? const [],
            maxes: pre?.maxes ?? const {},
            status: closed ? LotStatus.skipped : LotStatus.upcoming,
          ),
        );
        continue;
      }
      var end = start.add(Duration(seconds: show.lotSeconds));
      final valid = <LiveEvent>[];
      var maxes = const <String, double>{};
      var entrants = 0;
      bool inWindow(LiveEvent e) =>
          !e.at.isBefore(start) &&
          !e.at.isAfter(end) &&
          e.userId != show.hostId;
      switch (lot.mode) {
        case LotMode.auction:
          // Predlicitacije (prije početka) i ponude dok sat teče; svaka
          // ponuda dodaje 2 s.
          final r = _proxy(
            lot,
            allBids.where((b) => !b.at.isAfter(now)),
            show,
            start: start,
            end: end,
          );
          valid.addAll(r.steps);
          bidFeed.addAll(r.steps);
          maxes = r.maxes;
          end = r.end ?? end;
        case LotMode.dutch:
          // Prvi koji uzme kupuje po cijeni u tom trenutku.
          final take = (byLot[(LiveEventType.take, i)] ?? const <LiveEvent>[])
              .where(inWindow)
              .firstOrNull;
          if (take != null) {
            valid.add(
              take.withAmount(
                lot.dutchPrice(take.at.difference(start), show.lotSeconds),
              ),
            );
            end = take.at;
          }
        case LotMode.giveaway:
          // Dobitnik se "izvlači" stabilnim hashom — isti na svakom uređaju.
          final first = <String, LiveEvent>{};
          for (final e
              in byLot[(LiveEventType.enter, i)] ?? const <LiveEvent>[]) {
            if (inWindow(e)) first.putIfAbsent(e.userId, () => e);
          }
          entrants = first.length;
          if (first.isNotEmpty) {
            final ids = first.keys.toList()..sort();
            final pick = ids[stableHash('${show.id}:$i') % ids.length];
            valid.add(first[pick]!.withAmount(0));
          }
      }
      if (ended != null && !ended.isBefore(start) && ended.isBefore(end)) {
        // Domaćin je završio live usred licitacije — predmet se ne prodaje.
        lots.add(_lot(i, lot, start, ended, valid, LotStatus.skipped));
        continue;
      }
      final done = now.isAfter(end);
      final status = now.isBefore(start)
          ? LotStatus.upcoming
          : !done
          ? LotStatus.running
          : valid.isNotEmpty
          ? LotStatus.sold
          : LotStatus.unsold;
      lots.add(
        LotState(
          index: i,
          lot: lot,
          start: start,
          end: end,
          // Nagradna igra: dobitnik se ne otkriva dok traje prijava.
          bids: lot.mode == LotMode.giveaway && status == LotStatus.running
              ? const []
              : valid,
          status: status,
          entrants: entrants,
          maxes: maxes,
        ),
      );
    }

    final since = now.subtract(viewerWindow);
    final viewers = <String>{
      for (final e in events)
        if (e.at.isAfter(since)) e.userId,
    }..remove(show.hostId);
    final feed = [
      ...bidFeed,
      for (final e in events)
        if (e.type == LiveEventType.chat && !hiddenUsers.contains(e.userId)) e,
    ]..sort((a, b) => a.at.compareTo(b.at));
    // Hype-metar: ponude i "uzimam" vrijede više od chata i prijava.
    final hot = now.subtract(const Duration(seconds: 30));
    var heat = 0.0;
    for (final e in events) {
      if (!e.at.isAfter(hot) || e.at.isAfter(now)) continue;
      heat += switch (e.type) {
        LiveEventType.bid || LiveEventType.take => 3,
        LiveEventType.chat || LiveEventType.enter || LiveEventType.guess => 1,
        LiveEventType.join || LiveEventType.remind => 0,
      };
    }
    return LiveState(
      show: show,
      lots: lots,
      at: now,
      hype: (heat / 30).clamp(0.0, 1.0),
      viewers: viewers.length,
      feed: feed.length > 60 ? feed.sublist(feed.length - 60) : feed,
    );
  }

  /// Licitacija s maksimalnim ponudama (kao "custom bid" na Whatnotu):
  /// svaka ponuda je najviše što je licitant spreman platiti, a cijena
  /// raste samo za jedan korak iznad drugog najvišeg. Kod jednakih
  /// ponuda vodi ranija. Vodeći može povisiti svoj maksimum (cijena se ne
  /// mijenja). Ponude prije [start] su predlicitacije i ne produljuju sat.
  static ({List<LiveEvent> steps, Map<String, double> maxes, DateTime? end})
  _proxy(
    LiveLot lot,
    Iterable<LiveEvent> bids,
    LiveShow show, {
    DateTime? start,
    DateTime? end,
  }) {
    LiveEvent? leader;
    var leaderMax = 0.0;
    var price = lot.startPrice;
    var close = end;
    final steps = <LiveEvent>[];
    final maxes = <String, double>{};
    for (final b in bids) {
      if (b.userId == show.hostId) continue;
      if (close != null && b.at.isAfter(close)) continue;
      // Dok sat teče ponuda je "skok": cijena odmah postaje taj iznos
      // (gumb "Licitiraj" nudi korak više, vlastiti iznos skače odmah).
      // Predlicitacije (prije početka) ostaju maksimalne ponude.
      final running = start != null && !b.at.isBefore(start);
      if (leader == null) {
        if (b.amount < lot.startPrice) continue;
        leader = b;
        leaderMax = b.amount;
        if (running) price = b.amount;
      } else if (b.userId == leader.userId) {
        // Vodeći povisuje svoj maksimum — cijena ostaje ista.
        if (b.amount > leaderMax) {
          leaderMax = b.amount;
          maxes[b.userId] = b.amount;
        }
        continue;
      } else {
        if (b.amount < price + LiveLot.increment(price)) continue;
        if (b.amount > leaderMax) {
          price = running
              ? b.amount
              : min(b.amount, leaderMax + LiveLot.increment(leaderMax));
          leader = b;
          leaderMax = b.amount;
        } else {
          // Automatska ponuda vodećeg ga drži ispred.
          price = min(leaderMax, b.amount + LiveLot.increment(b.amount));
        }
      }
      maxes[b.userId] = max(maxes[b.userId] ?? 0, b.amount);
      steps.add(
        LiveEvent(
          id: b.id,
          showId: b.showId,
          type: LiveEventType.bid,
          userId: leader.userId,
          userLabel: leader.userLabel,
          at: b.at,
          lot: b.lot,
          amount: roundCredits(price),
        ),
      );
      final s = start;
      if (s != null &&
          close != null &&
          !b.at.isBefore(s) &&
          !b.at.isAfter(close)) {
        close = close.add(LiveShow.bidBonus);
      }
    }
    return (steps: steps, maxes: maxes, end: close);
  }

  static LotState _lot(
    int i,
    LiveLot lot,
    DateTime? start,
    DateTime? end,
    List<LiveEvent> bids,
    LotStatus status,
  ) => LotState(
    index: i,
    lot: lot,
    start: start,
    end: end,
    bids: bids,
    status: status,
  );

  LiveState stateOf(LiveShow show, {DateTime? now, String? viewerId}) {
    final viewer = viewerId == null ? null : _storage.userById(viewerId);
    return compute(
      show,
      _storage.liveEventsOf(show.id),
      now ?? DateTime.now(),
      hiddenUsers: {...?viewer?.blockedIds},
    );
  }

  /// Predmet je u liveu koji još traje i čeka na red, upravo se licitira
  /// ili je prodan, a prodaja još nije provedena. Takav predmet se ne smije
  /// prodati, mijenjati ni obrisati (kao predmet na aukciji).
  static bool isLocked(
    StorageService storage,
    String deviceId, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    for (final show in storage.liveShows) {
      final indices = [
        for (var i = 0; i < show.lots.length; i++)
          if (show.lots[i].deviceId == deviceId && !show.settled.contains(i)) i,
      ];
      if (indices.isEmpty) continue;
      final state = compute(show, storage.liveEventsOf(show.id), at);
      for (final i in indices) {
        final s = state.lots[i].status;
        if (s == LotStatus.upcoming ||
            s == LotStatus.running ||
            s == LotStatus.sold) {
          return true;
        }
      }
    }
    return false;
  }

  /// Poruka za predmet zaključan u liveu.
  static String get lockedMessage =>
      t('Predmet je u live aukciji — pričekaj da se licitira.');

  // --------------------------------------------------------- objava

  /// Nova emisija. Predmeti su neobavezni — domaćin ih može dodavati i
  /// tijekom livea. Live "odmah" znači da je domaćin već u sobi.
  Future<LiveShow> create({
    required String hostId,
    required String title,
    List<(String, double)> items = const [],
    int lotSeconds = 30,
    DateTime? startsAt,
    DateTime? now,
    bool video = false,
    String? coverPath,
    String? category,
    bool relistUnsold = true,
  }) async {
    final at = now ?? DateTime.now();
    final host = _storage.userById(hostId);
    if (host == null || host.isGuest) {
      throw TradeException(t('Za live aukciju se prijavi.'));
    }
    final name = title.trim();
    if (name.length < 3) throw TradeException(t('Upiši naslov livea.'));
    if (name.length > LiveShow.maxTitle) {
      throw TradeException(
        t('Naslov može imati najviše {0} znakova.', ['${LiveShow.maxTitle}']),
      );
    }
    final maxLots = _maxLots(hostId);
    if (items.length > maxLots) {
      throw TradeException(
        t('Live može imati najviše {0} predmeta.', ['$maxLots']),
      );
    }
    if (!LiveShow.lotDurations.contains(lotSeconds)) {
      throw TradeException(t('Odaberi trajanje licitacije.'));
    }
    final start = startsAt ?? at;
    if (start.isBefore(at.subtract(const Duration(minutes: 1))) ||
        start.isAfter(at.add(LiveShow.maxScheduleAhead))) {
      throw TradeException(
        t('Live se može zakazati najviše 7 dana unaprijed.'),
      );
    }
    if (_storage.liveShows.any(
      (s) => s.hostId == hostId && !stateOf(s, now: at).isOver,
    )) {
      throw TradeException(t('Već imaš live u tijeku ili zakazan.'));
    }

    final lots = <LiveLot>[];
    for (final (id, price) in items) {
      if (lots.any((l) => l.deviceId == id)) continue;
      lots.add(await _prepareLot(hostId, id, price, at));
    }
    final later = start.isAfter(at.add(const Duration(minutes: 1)));
    final show = LiveShow(
      id: _uuid.v4(),
      hostId: hostId,
      hostLabel: host.handle,
      title: name,
      startsAt: start,
      createdAt: at,
      lots: lots,
      lotSeconds: lotSeconds,
      video: video,
      hostSeenAt: later ? null : at,
      coverPath: coverPath,
      category: category,
      relistUnsold: relistUnsold,
    );
    await _storage.putLiveShow(show);
    await Inbox(_storage).toFollowers(
      hostId,
      NotificationKind.liveStarted,
      args: [host.handle, name, later ? formatDateTime(start) : t('sada')],
      targetId: show.id,
      now: at,
    );
    return show;
  }

  /// Provjera predmeta za live; predmet izlazi iz ponude dok se licitira.
  Future<LiveLot> _prepareLot(
    String hostId,
    String deviceId,
    double price,
    DateTime at,
  ) async {
    final d = _storage.deviceById(deviceId);
    if (d == null || d.ownerId != hostId) {
      throw TradeException(t('U live možeš staviti samo svoje predmete.'));
    }
    if (d.isDigital) {
      throw TradeException(t('Digitalni proizvodi ne idu na live.'));
    }
    if (_storage.activeAuctionFor(deviceId) != null) {
      throw TradeException(t('"{0}" je već na aukciji.', [d.name]));
    }
    if (isLocked(_storage, deviceId, now: at)) {
      throw TradeException(lockedMessage);
    }
    if (price < 1 || price > TradeService.maxListPrice) {
      throw TradeException(t('Početna cijena mora biti barem 1 €.'));
    }
    if (d.isListed) await _storage.putDevice(d.withListing(null));
    return LiveLot(
      deviceId: deviceId,
      deviceName: '${d.name} ${d.model}'.trim(),
      startPrice: roundCredits(price),
    );
  }

  LiveShow _requireHost(String hostId, String showId) {
    final show = _require(showId);
    if (show.hostId != hostId) {
      throw TradeException(t('To može samo domaćin livea.'));
    }
    return show;
  }

  /// Domaćin dodaje predmet tijekom livea (ide na kraj reda).
  Future<LiveShow> addLot(
    String hostId,
    String showId,
    String deviceId,
    double price, {
    LotMode mode = LotMode.auction,
    double floorPrice = 1,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final show = _requireHost(hostId, showId);
    if (show.endedAt != null || stateOf(show, now: at).isOver) {
      throw TradeException(t('Live je završio.'));
    }
    final maxLots = _maxLots(hostId);
    if (show.lots.length >= maxLots) {
      throw TradeException(
        t('Live može imati najviše {0} predmeta.', ['$maxLots']),
      );
    }
    if (mode == LotMode.dutch && (floorPrice < 1 || floorPrice >= price)) {
      throw TradeException(
        t('Najniža cijena mora biti barem 1 € i manja od početne.'),
      );
    }
    final base = await _prepareLot(
      hostId,
      deviceId,
      mode == LotMode.giveaway ? 1 : price,
      at,
    );
    final lot = LiveLot(
      deviceId: base.deviceId,
      deviceName: base.deviceName,
      startPrice: mode == LotMode.giveaway ? 0 : base.startPrice,
      mode: mode,
      floorPrice: roundCredits(floorPrice),
    );
    final updated = show.copyWith(lots: [...show.lots, lot]);
    await _storage.putLiveShow(updated);
    return updated;
  }

  /// Domaćin pokreće licitaciju za predmet [index] (ili prvi na čekanju).
  Future<LiveShow> startLot(
    String hostId,
    String showId, {
    int? index,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final show = _requireHost(hostId, showId);
    final state = stateOf(show, now: at);
    if (show.endedAt != null || state.isOver) {
      throw TradeException(t('Live je završio.'));
    }
    if (state.current != null) {
      throw TradeException(t('Pričekaj da završi licitacija u tijeku.'));
    }
    final i = index ?? state.next?.index;
    if (i == null || i < 0 || i >= show.lots.length) {
      throw TradeException(t('Dodaj predmet za licitaciju.'));
    }
    final lot = show.lots[i];
    if (lot.startedAt != null) {
      throw TradeException(t('Ovaj predmet je već licitiran.'));
    }
    final d = _storage.deviceById(lot.deviceId);
    if (d == null || d.ownerId != hostId) {
      throw TradeException(t('Predmet više nije tvoj.'));
    }
    final lots = [...show.lots];
    lots[i] = lot.started(at);
    final updated = show.copyWith(lots: lots, hostSeenAt: at);
    await _storage.putLiveShow(updated);
    if (show.hostSeenAt == null) await _remindViewers(updated, at);
    return updated;
  }

  /// "Još sam tu": domaćin je u sobi (live traje dok se javlja).
  Future<void> heartbeat(String hostId, String showId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final show = _requireHost(hostId, showId);
    if (show.endedAt != null) return;
    await _storage.putLiveShow(show.copyWith(hostSeenAt: at));
    if (show.hostSeenAt == null) await _remindViewers(show, at);
  }

  /// Zakazani live je krenuo: obavijest svima koji su tražili podsjetnik.
  Future<void> _remindViewers(LiveShow show, DateTime at) async {
    final inbox = Inbox(_storage);
    final sent = <String>{};
    for (final e in _storage.liveEventsOf(show.id)) {
      if (e.type != LiveEventType.remind || !sent.add(e.userId)) continue;
      await inbox.send(
        e.userId,
        NotificationKind.liveStarted,
        args: [show.hostLabel, show.title, t('sada')],
        targetId: show.id,
        now: at,
      );
    }
  }

  // ------------------------------------------- igre i posebni predmeti

  LiveEvent _event(
    LiveEventType type,
    String userId,
    String showId, {
    required DateTime at,
    int lot = 0,
    double amount = 0,
  }) => LiveEvent(
    id: _uuid.v4(),
    showId: showId,
    type: type,
    userId: userId,
    userLabel: _storage.userById(userId)?.handle ?? '',
    at: at,
    lot: lot,
    amount: amount,
  );

  /// Zajedničke provjere za gledatelja: prijavljen, nije domaćin, nije
  /// blokiran, a trenutni predmet je zadane vrste.
  (LiveShow, LotState) _viewerLot(
    String userId,
    String showId,
    LotMode mode,
    DateTime at,
  ) {
    final user = _storage.userById(userId);
    if (user == null || user.isGuest) {
      throw TradeException(t('Za licitiranje se prijavi.'));
    }
    final show = _require(showId);
    if (show.hostId == userId) {
      throw TradeException(t('Ne možeš licitirati na svom liveu.'));
    }
    if (_storage.userById(show.hostId)?.blockedIds.contains(userId) ?? false) {
      throw TradeException(t('Ne možeš licitirati na ovom liveu.'));
    }
    final lot = stateOf(show, now: at).current;
    if (lot == null || lot.mode != mode) {
      throw TradeException(t('Trenutno se ništa ne licitira.'));
    }
    return (show, lot);
  }

  /// Pada cijena: "Uzimam!" — prvi kupuje po trenutnoj cijeni. Vraća je li
  /// baš ovaj korisnik bio prvi.
  Future<bool> take(String userId, String showId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final (show, lot) = _viewerLot(userId, showId, LotMode.dutch, at);
    requireCheckout(_storage.userById(userId)!);
    await _storage.putLiveEvent(
      _event(
        LiveEventType.take,
        userId,
        showId,
        at: at,
        lot: lot.index,
        amount: lot.dutchPriceAt(at, show.lotSeconds),
      ),
    );
    return stateOf(show, now: at).lots[lot.index].leader?.userId == userId;
  }

  /// Nagradna igra: prijava (jednom po predmetu).
  Future<void> enterGiveaway(
    String userId,
    String showId, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final (_, lot) = _viewerLot(userId, showId, LotMode.giveaway, at);
    requireCheckout(_storage.userById(userId)!);
    if (hasEntered(userId, showId, lot.index)) return;
    await _storage.putLiveEvent(
      _event(LiveEventType.enter, userId, showId, at: at, lot: lot.index),
    );
  }

  bool hasEntered(String userId, String showId, int lot) => _storage
      .liveEventsOf(showId)
      .any(
        (e) =>
            e.type == LiveEventType.enter && e.userId == userId && e.lot == lot,
      );

  /// Zakazani live: "Podsjeti me" — obavijest kad domaćin krene uživo.
  Future<void> remind(String userId, String showId, {DateTime? now}) async {
    final user = _storage.userById(userId);
    if (user == null || user.isGuest) {
      throw TradeException(t('Za podsjetnik se prijavi.'));
    }
    _require(showId);
    if (wantsReminder(userId, showId)) return;
    await _storage.putLiveEvent(
      _event(LiveEventType.remind, userId, showId, at: now ?? DateTime.now()),
    );
  }

  bool wantsReminder(String userId, String showId) => _storage
      .liveEventsOf(showId)
      .any((e) => e.type == LiveEventType.remind && e.userId == userId);

  /// Domaćin završava live (predmeti na čekanju ostaju njemu).
  Future<void> end(String hostId, String showId, {DateTime? now}) async {
    final show = _requireHost(hostId, showId);
    if (show.endedAt != null) return;
    await _storage.putLiveShow(show.copyWith(endedAt: now ?? DateTime.now()));
  }

  // ----------------------------------------------- gledatelji, chat, ponude

  /// Ulazak u live (broji se za gledatelje; najviše jednom u 5 minuta).
  Future<void> join(String userId, String showId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final user = _storage.userById(userId);
    if (user == null) return;
    final recent = _storage
        .liveEventsOf(showId)
        .any(
          (e) => e.userId == userId && e.at.isAfter(at.subtract(viewerWindow)),
        );
    if (recent) return;
    await _storage.putLiveEvent(
      LiveEvent(
        id: _uuid.v4(),
        showId: showId,
        type: LiveEventType.join,
        userId: userId,
        userLabel: user.handle,
        at: at,
      ),
    );
  }

  Future<void> chat(
    String userId,
    String showId,
    String text, {
    DateTime? now,
  }) async {
    final user = _storage.userById(userId);
    if (user == null || user.isGuest) {
      throw TradeException(t('Za chat se prijavi.'));
    }
    final body = text.trim();
    if (body.isEmpty) return;
    if (body.length > LiveEvent.maxText) {
      throw TradeException(
        t('Poruka može imati najviše {0} znakova.', ['${LiveEvent.maxText}']),
      );
    }
    _require(showId);
    await _storage.putLiveEvent(
      LiveEvent(
        id: _uuid.v4(),
        showId: showId,
        type: LiveEventType.chat,
        userId: userId,
        userLabel: user.handle,
        at: now ?? DateTime.now(),
        text: body,
      ),
    );
  }

  /// Prije prve ponude traži se samo način plaćanja (pobjedniku se
  /// naplaćuje automatski); dostavu pobjednik bira nakon pobjede.
  static void requireCheckout(AppUser user) {
    if (user.paymentCard == null) {
      throw TradeException(t('Prije licitiranja dodaj način plaćanja.'));
    }
  }

  /// Ponuda na predmet koji se upravo licitira — ili predlicitacija na
  /// predmet [lot] koji tek čeka na red. [amount] je maksimalna ponuda:
  /// sustav licitira umjesto tebe do tog iznosa. Vraća novo stanje.
  Future<LiveState> bid(
    String userId,
    String showId,
    double amount, {
    int? lot,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final user = _storage.userById(userId);
    if (user == null || user.isGuest) {
      throw TradeException(t('Za licitiranje se prijavi.'));
    }
    final show = _require(showId);
    if (show.hostId == userId) {
      throw TradeException(t('Ne možeš licitirati na svom liveu.'));
    }
    if (_storage.userById(show.hostId)?.blockedIds.contains(userId) ?? false) {
      throw TradeException(t('Ne možeš licitirati na ovom liveu.'));
    }
    requireCheckout(user);
    final state = stateOf(show, now: at);
    final LotState? target;
    if (lot == null) {
      target = state.current;
    } else {
      final l = lot >= 0 && lot < state.lots.length ? state.lots[lot] : null;
      target =
          l != null &&
              (l.status == LotStatus.upcoming || l.status == LotStatus.running)
          ? l
          : null;
      if (target == null || state.isOver) {
        throw TradeException(t('Za ovaj predmet se više ne može licitirati.'));
      }
    }
    if (target == null || target.mode != LotMode.auction) {
      throw TradeException(t('Trenutno se ništa ne licitira.'));
    }
    final value = roundCredits(amount);
    if (value > TradeService.maxListPrice) {
      throw TradeException(
        t('Najveća ponuda je {0}.', [formatCredits(TradeService.maxListPrice)]),
      );
    }
    if (target.leader?.userId == userId) {
      final mine = target.maxOf(userId) ?? target.price;
      if (value <= mine) {
        throw TradeException(
          t('Već vodiš — tvoja najviša ponuda je {0}.', [formatCredits(mine)]),
        );
      }
    } else if (value < target.minNext) {
      throw TradeException(
        t('Najmanja ponuda je {0}.', [formatCredits(target.minNext)]),
      );
    }
    await _storage.putLiveEvent(
      LiveEvent(
        id: _uuid.v4(),
        showId: showId,
        type: LiveEventType.bid,
        userId: userId,
        userLabel: user.handle,
        at: at,
        lot: target.index,
        amount: value,
      ),
    );
    return stateOf(show, now: at);
  }

  // ------------------------------------------------------- zaključivanje

  /// Provodi prodaje završenih predmeta (pobjednik plaća karticom,
  /// prodavatelj dobiva zaradu, pobjednik bira dostavu). Pokreće ga
  /// domaćin ili pobjednik — s istim ID-jevima, pa je ponavljanje bezopasno.
  Future<int> settleDue({String? userId, DateTime? now}) async {
    final at = now ?? DateTime.now();
    var count = 0;
    for (final show in _storage.liveShows) {
      final state = stateOf(show, now: at);
      final settled = {...show.settled};
      // Live je gotov: neprodani predmeti idu na Kupi odmah (radi domaćin).
      if (state.isOver &&
          show.relistUnsold &&
          (userId == null || userId == show.hostId)) {
        for (final l in state.lots) {
          if ((l.status == LotStatus.unsold || l.status == LotStatus.skipped) &&
              !settled.contains(l.index) &&
              l.mode != LotMode.giveaway) {
            await _relist(show, l);
            settled.add(l.index);
          }
        }
      }
      for (final l in state.lots) {
        if (l.status != LotStatus.sold || settled.contains(l.index)) continue;
        final winner = l.leader!;
        if (userId != null &&
            userId != show.hostId &&
            userId != winner.userId) {
          continue;
        }
        await _settleLot(show, l, at);
        settled.add(l.index);
        count++;
      }
      if (settled.length != show.settled.length) {
        await _storage.putLiveShow(
          _storage.liveShowById(show.id)!.copyWith(settled: settled.toList()),
        );
      }
    }
    return count;
  }

  /// Trgovac (obrt, tvrtka) smije više predmeta u jednom liveu.
  int _maxLots(String hostId) => _storage.userById(hostId)?.isTrader ?? false
      ? LiveShow.businessMaxLots
      : LiveShow.maxLots;

  /// Neprodani predmet nakon livea ide na Kupi odmah po početnoj cijeni
  /// (ako domaćin ima podatke prodavatelja i predmet je još njegov).
  Future<void> _relist(LiveShow show, LotState l) async {
    final host = _storage.userById(show.hostId);
    final d = _storage.deviceById(l.lot.deviceId);
    if (host?.seller == null ||
        d == null ||
        d.ownerId != show.hostId ||
        d.isListed) {
      return;
    }
    try {
      await TradeService(_storage).list(
        userId: show.hostId,
        deviceId: d.id,
        price: max(1, l.lot.startPrice),
      );
    } on TradeException {
      // Predmet je u međuvremenu na aukciji ili u drugom liveu.
    }
  }

  Future<void> _settleLot(LiveShow show, LotState l, DateTime at) async {
    final winner = _storage.userById(l.leader!.userId);
    final seller = _storage.userById(show.hostId);
    final device = _storage.deviceById(l.lot.deviceId);
    final txId = 'live-${show.id}-${l.index}';
    if (winner == null ||
        seller == null ||
        device == null ||
        device.ownerId != show.hostId ||
        _storage.transactions.any((t) => t.id == txId)) {
      return;
    }
    final price = l.price;
    final fee = auctionCommission(price, l.lot.basePrice);
    final payout = auctionPayout(price, l.lot.basePrice);
    // Upis prodaje samo jednom (atomski) — domaćin i pobjednik mogu
    // istovremeno provoditi prodaju s dva uređaja.
    final sale = LoopTransaction(
      id: txId,
      type: TransactionType.sell,
      userId: seller.id,
      deviceId: device.id,
      deviceName: l.lot.deviceName,
      price: price,
      fee: fee,
      amount: payout,
      sellerId: seller.id,
      sellerLabel: seller.handle,
      buyerId: winner.id,
      buyerLabel: winner.handle,
      createdAt: l.end!,
      isAuction: true,
    );
    final claimed = await _storage.claimTransaction(sale);
    if (!claimed) return;
    await _storage.putDevice(device.withOwner(winner.id));
    await Earnings(_storage).credit(sale);
    await _storage.recordSnapshot(seller.id, now: at);
    await _storage.recordSnapshot(winner.id, now: at);
    final inbox = Inbox(_storage);
    await inbox.send(
      winner.id,
      l.mode == LotMode.giveaway
          ? NotificationKind.giveawayWon
          : NotificationKind.auctionWon,
      args: l.mode == LotMode.giveaway
          ? [l.lot.deviceName, show.hostLabel]
          : [l.lot.deviceName, price],
      targetId: show.id,
      now: at,
    );
    await inbox.send(
      seller.id,
      NotificationKind.itemSold,
      args: [l.lot.deviceName, winner.handle, payout],
      targetId: device.id,
      now: at,
    );
    // Kupac sam bira način dostave (u "Moje → Kupljeno"); sve što osvoji
    // u istom liveu putuje u jednom paketu i dostava se plaća jednom.
    await DeliveryService(_storage).createPending(
      id: txId,
      userId: winner.id,
      deviceId: device.id,
      deviceName: l.lot.deviceName,
      sellerId: seller.id,
      now: at,
    );
  }

  /// Briše događaje (chat, ponude) liveova završenih prije više od 2 dana.
  Future<void> purgeOld({DateTime? now}) async {
    final at = now ?? DateTime.now();
    for (final show in _storage.liveShows) {
      final state = stateOf(show, now: at);
      final last = [
        show.startsAt,
        ?show.hostSeenAt,
        ?show.endedAt,
        for (final l in state.lots) ?l.end,
      ].reduce((a, b) => a.isAfter(b) ? a : b);
      if (state.isOver && at.difference(last) > const Duration(days: 2)) {
        for (final e in _storage.liveEventsOf(show.id)) {
          await _storage.deleteLiveEvent(e.id);
        }
      }
    }
  }

  LiveShow _require(String id) {
    final s = _storage.liveShowById(id);
    if (s == null) throw TradeException(t('Live ne postoji.'));
    return s;
  }
}
