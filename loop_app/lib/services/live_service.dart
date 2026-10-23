import 'package:uuid/uuid.dart';

import '../l10n/tr.dart';
import '../models/app_notification.dart';
import '../models/auction.dart';
import '../models/live_show.dart';
import '../models/loop_transaction.dart';
import '../utils/formatters.dart';
import 'delivery_service.dart';
import 'fee.dart';
import 'inbox.dart';
import 'storage_service.dart';
import 'trade_service.dart';

/// Stanje jednog predmeta u live aukciji.
enum LotStatus { upcoming, running, sold, unsold, skipped }

class LotState {
  const LotState({
    required this.index,
    required this.lot,
    required this.start,
    required this.end,
    required this.bids,
    required this.status,
  });

  final int index;
  final LiveLot lot;
  final DateTime start;

  /// Kraj (uključujući produljenja zbog ponuda u zadnjim sekundama).
  final DateTime end;

  /// Važeće ponude redom (zadnja vodi).
  final List<LiveEvent> bids;
  final LotStatus status;

  LiveEvent? get leader => bids.isEmpty ? null : bids.last;
  double get price => leader?.amount ?? lot.startPrice;
  double get minNext =>
      leader == null ? lot.startPrice : price + Auction.stepFor(price);

  Duration left(DateTime now) =>
      end.isAfter(now) ? end.difference(now) : Duration.zero;
}

/// Izračunato stanje emisije u trenutku [LiveState.at].
class LiveState {
  const LiveState({
    required this.show,
    required this.lots,
    required this.at,
    required this.viewers,
    required this.feed,
  });

  final LiveShow show;
  final List<LotState> lots;
  final DateTime at;

  /// Gledatelji u zadnjih 5 minuta (ulazak, poruka ili ponuda).
  final int viewers;

  /// Chat i ponude, najnovije zadnje.
  final List<LiveEvent> feed;

  LotState? get current =>
      lots.where((l) => l.status == LotStatus.running).firstOrNull;
  LotState? get next =>
      lots.where((l) => l.status == LotStatus.upcoming).firstOrNull;

  bool get isScheduled => at.isBefore(show.startsAt) && show.endedAt == null;
  bool get isOver =>
      show.endedAt != null ||
      lots.every(
        (l) => l.status != LotStatus.upcoming && l.status != LotStatus.running,
      );
  bool get isLive => !isScheduled && !isOver;

  int get soldCount => lots.where((l) => l.status == LotStatus.sold).length;
}

/// Live aukcije: objava emisije, ulazak, chat, ponude i zaključivanje.
class LiveService {
  LiveService(this._storage);

  final StorageService _storage;
  static const _uuid = Uuid();

  /// Gledatelj se broji ovoliko nakon zadnje aktivnosti.
  static const viewerWindow = Duration(minutes: 5);

  // ------------------------------------------------------------ izračun

  /// Stanje emisije iz samih podataka — isto na svakom uređaju.
  ///
  /// Raspored ovisi samo o emisiji i ponudama (ne o tome tko gleda ni o
  /// trenutnom vlasništvu predmeta), pa se prošlost nikad ne mijenja.
  /// [hiddenUsers] (npr. blokirani) skriva samo njihove poruke u chatu.
  static LiveState compute(
    LiveShow show,
    List<LiveEvent> events,
    DateTime now, {
    Set<String> hiddenUsers = const {},
  }) {
    final bidsByLot = <int, List<LiveEvent>>{};
    for (final e in events) {
      if (e.type == LiveEventType.bid) (bidsByLot[e.lot] ??= []).add(e);
    }
    for (final list in bidsByLot.values) {
      list.sort((a, b) => a.at.compareTo(b.at));
    }

    final lots = <LotState>[];
    var t = show.startsAt;
    final ended = show.endedAt;
    for (var i = 0; i < show.lots.length; i++) {
      final lot = show.lots[i];
      final start = t;
      if (ended != null && !start.isBefore(ended)) {
        lots.add(_lot(i, lot, start, start, const [], LotStatus.skipped));
        continue;
      }
      var end = start.add(Duration(seconds: show.lotSeconds));
      final valid = <LiveEvent>[];
      var price = lot.startPrice;
      for (final b in bidsByLot[i] ?? const <LiveEvent>[]) {
        if (b.at.isBefore(start) || b.at.isAfter(end)) continue;
        if (b.userId == show.hostId) continue;
        if (valid.isNotEmpty && valid.last.userId == b.userId) continue;
        final min = valid.isEmpty
            ? lot.startPrice
            : price + Auction.stepFor(price);
        if (b.amount < min) continue;
        valid.add(b);
        price = b.amount;
        // "Sudden death": ponuda u zadnjim sekundama vraća sat.
        if (end.difference(b.at) < LiveShow.suddenDeath) {
          end = b.at.add(LiveShow.suddenDeath);
        }
      }
      if (ended != null && ended.isBefore(end)) {
        // Domaćin je prekinuo live usred licitacije — predmet se ne prodaje.
        lots.add(_lot(i, lot, start, ended, valid, LotStatus.skipped));
        t = ended;
        continue;
      }
      final status = now.isBefore(start)
          ? LotStatus.upcoming
          : !now.isAfter(end)
          ? LotStatus.running
          : valid.isNotEmpty
          ? LotStatus.sold
          : LotStatus.unsold;
      lots.add(_lot(i, lot, start, end, valid, status));
      t = end.add(LiveShow.gap);
    }

    final since = now.subtract(viewerWindow);
    final viewers = <String>{
      for (final e in events)
        if (e.at.isAfter(since)) e.userId,
    }..remove(show.hostId);
    final feed = [
      for (final e in events)
        if (e.type == LiveEventType.bid ||
            (e.type == LiveEventType.chat && !hiddenUsers.contains(e.userId)))
          e,
    ]..sort((a, b) => a.at.compareTo(b.at));
    return LiveState(
      show: show,
      lots: lots,
      at: now,
      viewers: viewers.length,
      feed: feed.length > 60 ? feed.sublist(feed.length - 60) : feed,
    );
  }

  static LotState _lot(
    int i,
    LiveLot lot,
    DateTime start,
    DateTime end,
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

  /// Predmet je u liveu koji još nije došao do njega, upravo se licitira
  /// ili je prodan, a prodaja još nije provedena. Takav predmet se ne smije
  /// prodati, mijenjati ni obrisati (kao predmet na aukciji).
  static bool isLocked(
    StorageService storage,
    String deviceId, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    for (final show in storage.liveShows) {
      final i = show.lots.indexWhere((l) => l.deviceId == deviceId);
      if (i < 0 || show.settled.contains(i)) continue;
      final lot = compute(show, storage.liveEventsOf(show.id), at).lots[i];
      if (lot.status == LotStatus.upcoming ||
          lot.status == LotStatus.running ||
          lot.status == LotStatus.sold) {
        return true;
      }
    }
    return false;
  }

  /// Poruka za predmet zaključan u liveu.
  static String get lockedMessage =>
      t('Predmet je u live aukciji — pričekaj da se licitira.');

  // --------------------------------------------------------- objava

  Future<LiveShow> create({
    required String hostId,
    required String title,
    required List<(String, double)> items,
    int lotSeconds = 30,
    DateTime? startsAt,
    DateTime? now,
    bool video = false,
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
    if (items.isEmpty) {
      throw TradeException(t('Odaberi barem jedan predmet.'));
    }
    if (items.length > LiveShow.maxLots) {
      throw TradeException(
        t('Live može imati najviše {0} predmeta.', ['${LiveShow.maxLots}']),
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
      (s) =>
          s.hostId == hostId &&
          s.endedAt == null &&
          !stateOf(s, now: at).isOver,
    )) {
      throw TradeException(t('Već imaš live u tijeku ili zakazan.'));
    }

    final lots = <LiveLot>[];
    for (final (id, price) in items) {
      final d = _storage.deviceById(id);
      if (d == null || d.ownerId != hostId) {
        throw TradeException(t('U live možeš staviti samo svoje predmete.'));
      }
      if (d.isDigital) {
        throw TradeException(t('Digitalni proizvodi ne idu na live.'));
      }
      if (_storage.activeAuctionFor(id) != null) {
        throw TradeException(t('"{0}" je već na aukciji.', [d.name]));
      }
      if (isLocked(_storage, id, now: at)) throw TradeException(lockedMessage);
      if (price < 1 || price > TradeService.maxListPrice) {
        throw TradeException(t('Početna cijena mora biti barem 1 €.'));
      }
      lots.add(
        LiveLot(
          deviceId: id,
          deviceName: '${d.name} ${d.model}'.trim(),
          startPrice: roundCredits(price),
        ),
      );
      // Predmet u liveu se ne prodaje istovremeno u Marketu.
      if (d.isListed) await _storage.putDevice(d.withListing(null));
    }
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
    );
    await _storage.putLiveShow(show);
    await Inbox(_storage).toFollowers(
      hostId,
      NotificationKind.liveStarted,
      args: [
        host.handle,
        name,
        start.isAfter(at.add(const Duration(minutes: 1)))
            ? formatDateTime(start)
            : t('sada'),
      ],
      targetId: show.id,
      now: at,
    );
    return show;
  }

  /// Domaćin završava live prije kraja.
  Future<void> end(String hostId, String showId, {DateTime? now}) async {
    final show = _require(showId);
    if (show.hostId != hostId) {
      throw TradeException(t('Samo domaćin može završiti live.'));
    }
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

  /// Ponuda na predmet koji se upravo licitira. Vraća novo stanje.
  Future<LiveState> bid(
    String userId,
    String showId,
    double amount, {
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
    final state = stateOf(show, now: at);
    final lot = state.current;
    if (lot == null) {
      throw TradeException(t('Trenutno se ništa ne licitira.'));
    }
    if (lot.leader?.userId == userId) {
      throw TradeException(t('Već vodiš — pričekaj da te netko nadmaši.'));
    }
    final value = roundCredits(amount);
    if (value < lot.minNext) {
      throw TradeException(
        t('Najmanja ponuda je {0}.', [formatCredits(lot.minNext)]),
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
        lot: lot.index,
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
    await _storage.putDevice(device.withOwner(winner.id));
    await _storage.putUser(
      seller.copyWith(
        credits: roundCredits(seller.credits + sellPayout(price)),
      ),
    );
    await _storage.putTransaction(
      LoopTransaction(
        id: txId,
        type: TransactionType.sell,
        userId: seller.id,
        deviceId: device.id,
        deviceName: l.lot.deviceName,
        price: price,
        fee: 0,
        amount: sellPayout(price),
        sellerId: seller.id,
        sellerLabel: seller.handle,
        buyerId: winner.id,
        buyerLabel: winner.handle,
        createdAt: l.end,
        isAuction: true,
      ),
    );
    await _storage.recordSnapshot(seller.id, now: at);
    await _storage.recordSnapshot(winner.id, now: at);
    final inbox = Inbox(_storage);
    await inbox.send(
      winner.id,
      NotificationKind.auctionWon,
      args: [l.lot.deviceName, price],
      targetId: show.id,
      now: at,
    );
    await inbox.send(
      seller.id,
      NotificationKind.itemSold,
      args: [l.lot.deviceName, winner.handle, sellPayout(price)],
      targetId: device.id,
      now: at,
    );
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
      final last = state.lots.isEmpty ? show.startsAt : state.lots.last.end;
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
