import 'package:uuid/uuid.dart';

import '../models/auction.dart';
import '../models/loop_transaction.dart';
import '../utils/formatters.dart';
import 'auction_policy.dart';
import 'delivery_service.dart';
import 'fee.dart';
import 'live_service.dart';
import 'earnings.dart';
import 'storage_service.dart';
import 'trade_service.dart';
import '../l10n/tr.dart';
import '../models/app_notification.dart';
import 'inbox.dart';

/// Ishod završene aukcije (za obavijesti sudionicima).
class AuctionResult {
  const AuctionResult(this.auction, {this.winnerId});
  final Auction auction;
  final String? winnerId;
}

/// Pravila aukcija:
/// - ponude su obvezujuće i ne mogu se povući ni smanjiti;
/// - vodeći ponuđač ne može dati novu ponudu dok ga netko ne nadmaši;
/// - ponuda ne može biti veća od raspoloživog stanja;
/// - iznos vodeće ponude je blokiran (oduzet s kredita) i vraća se kad
///   ponuđača netko nadmaši ili se aukcija otkaže;
/// - ponuda u zadnjoj minuti produljuje aukciju na 1 minutu od ponude;
/// - na kraju pobjednik dobiva predmet, prodavatelj iznos umanjen za 10 %
///   razlike iznad početne cijene.
class AuctionService {
  AuctionService(this._storage) : policy = AuctionPolicy(_storage);

  final StorageService _storage;
  final AuctionPolicy policy;
  final _uuid = const Uuid();

  /// Ponuda u zadnjih ovoliko vremena produljuje aukciju ("anti-sniping").
  static const extendWindow = Duration(minutes: 1);

  /// Ponuđena trajanja (2 minute služe za brzo testiranje demo verzije).
  static List<(String, Duration)> get durations => [
    (t('2 min (test)'), Duration(minutes: 2)),
    (t('1 sat'), Duration(hours: 1)),
    (t('24 sata'), Duration(hours: 24)),
    (t('3 dana'), Duration(days: 3)),
    (t('7 dana'), Duration(days: 7)),
  ];

  // ------------------------------------------------------------ objava

  Future<Auction> create({
    required String userId,
    required String deviceId,
    required double startPrice,
    required Duration duration,
    double? buyNowPrice,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final user = _storage.userById(userId);
    final device = _storage.deviceById(deviceId);
    if (user == null || device == null) {
      throw TradeException(t('Predmet ne postoji.'));
    }
    if (user.isGuest || user.seller == null) {
      throw TradeException(t('Za objavu ispuni podatke prodavatelja.'));
    }
    if (device.ownerId != userId) {
      throw TradeException(t('Na aukciju možeš staviti samo svoj predmet.'));
    }
    if (_storage.activeAuctionFor(deviceId) != null) {
      throw TradeException(t('Predmet je već na aukciji.'));
    }
    if (LiveService.isLocked(_storage, deviceId)) {
      throw TradeException(LiveService.lockedMessage);
    }
    if (device.isDigital) {
      throw TradeException(
        t(
          'Digitalni proizvodi se ne stavljaju na aukciju — prodaju se više puta na Kupi odmah.',
        ),
      );
    }
    if (startPrice <= 0) {
      throw TradeException(t('Početna cijena mora biti veća od 0.'));
    }
    if (duration <= Duration.zero) {
      throw TradeException(t('Odaberi trajanje aukcije.'));
    }
    if (buyNowPrice != null && buyNowPrice <= startPrice) {
      throw TradeException(
        t('Cijena "Kupi odmah" mora biti veća od početne cijene.'),
      );
    }
    // Pravila protiv masovnog objavljivanja (limit, naknada, pauza…).
    final reason = policy.blockReason(userId, device, now: at);
    if (reason != null) throw TradeException(reason);

    final fee = AuctionPolicy.listingFee(device);
    // Predmet iz Marketa ide na aukciju — objava u Marketu se uklanja.
    if (device.isListed) await _storage.putDevice(device.withListing(null));
    // Naknada za objavu plaća se karticom (pružatelj plaćanja) — bilježi
    // se kao transakcija, stanje se ne dira.
    final auction = Auction(
      id: _uuid.v4(),
      deviceId: deviceId,
      deviceName: '${device.name} ${device.model}',
      sellerId: userId,
      sellerLabel: user.handle,
      startPrice: roundCredits(startPrice),
      createdAt: at,
      endsAt: at.add(duration),
      listingFee: fee,
      buyNowPrice: buyNowPrice == null ? null : roundCredits(buyNowPrice),
    );
    await _storage.putAuction(auction);
    // Pratitelji trgovine saznaju za novu aukciju.
    await Inbox(_storage).toFollowers(
      userId,
      NotificationKind.followedAuction,
      args: [user.handle, device.name, auction.startPrice],
      targetId: auction.id,
      now: at,
    );
    // Objava je besplatna; zapis o naknadi samo ako je naknada postoji.
    if (fee > 0) {
      await _storage.putTransaction(
        LoopTransaction(
          id: _uuid.v4(),
          type: TransactionType.auctionFee,
          userId: userId,
          deviceId: device.id,
          deviceName: auction.deviceName,
          price: 0,
          fee: fee,
          amount: fee,
          buyerLabel: 'Subhasto',
          sellerId: userId,
          sellerLabel: user.handle,
          createdAt: at,
        ),
      );
    }
    await _storage.recordSnapshot(userId, now: at);
    return auction;
  }

  // ------------------------------------------------------------ ponude

  /// Ponuda [amount]. Uz [maxAmount] to je i **automatska ponuda**:
  /// aukcija licitira umjesto korisnika najmanjim korakom do tog iznosa.
  /// Blokira se samo trenutna vodeća ponuda, ne cijeli maksimum.
  ///
  /// Vodeći ponuđač ne licitira ponovno, ali smije povisiti svoj maksimum.
  Future<Auction> placeBid({
    required String userId,
    required String auctionId,
    required double amount,
    double? maxAmount,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    // Ponude su u zapisu aukcije: licitira se na svježi zapis, inače bi
    // zastarjela kopija izbrisala tuđu (višu) ponudu.
    await _storage.refreshAuction(auctionId);
    final a = _requireAuction(auctionId);
    final user = _storage.userById(userId);
    if (user == null) throw TradeException(t('Korisnik ne postoji.'));

    if (!a.isActive || a.isExpired(at)) {
      throw TradeException(t('Aukcija je završila.'));
    }
    if (a.sellerId == userId) {
      throw TradeException(t('Ne možeš licitirati na svoju aukciju.'));
    }
    // Gornja granica (kao za cijenu oglasa) — npr. ne milijarda eura.
    for (final v in [amount, ?maxAmount]) {
      if (!v.isFinite || v > TradeService.maxListPrice) {
        throw TradeException(
          t('Najveća ponuda je {0}.', [
            formatCredits(TradeService.maxListPrice),
          ]),
        );
      }
    }
    // Prodavatelj je blokirao ponuđača.
    if (_storage.userById(a.sellerId)?.blockedIds.contains(userId) ?? false) {
      throw TradeException(t('Ne možeš licitirati na ovu aukciju.'));
    }
    final leader = a.highestBid;
    if (leader?.userId == userId) {
      // Vodeći smije samo povisiti automatsku ponudu.
      final max = maxAmount == null ? null : roundCredits(maxAmount);
      if (max == null || max <= (a.autoMaxOf(userId) ?? leader!.amount)) {
        throw TradeException(
          t(
            'Već imaš najvišu ponudu. Ponuda je obvezujuća i ne može se povući ni promijeniti dok te netko ne nadmaši.',
          ),
        );
      }
      final updated = a.copyWith(autoMax: {...a.autoMax, userId: max});
      await _storage.putAuction(updated);
      return updated;
    }
    final bid = roundCredits(amount);
    if (bid < a.minNextBid) {
      throw TradeException(
        t('Najmanja ponuda je {0}.', [formatCredits(a.minNextBid)]),
      );
    }
    final max = maxAmount == null ? bid : roundCredits(maxAmount);
    if (max < bid) {
      throw TradeException(
        t('Automatska ponuda mora biti barem koliko i ponuda.'),
      );
    }
    // Pobjednik plaća karticom na kraju aukcije — ponude se ne ograničavaju
    // stanjem i ništa se ne blokira.
    final myCap = max;

    final bids = [...a.bids];
    final auto = {...a.autoMax}..remove(userId);
    String? outbidUser;
    var outbidByAuto = false;
    double price;
    String newLeader;

    if (leader == null) {
      price = bid;
      newLeader = userId;
      bids.add(
        Bid(userId: userId, userLabel: user.handle, amount: bid, time: at),
      );
    } else {
      final lCap = a.autoMaxOf(leader.userId) ?? leader.amount;
      if (myCap > lCap) {
        // Novi ponuđač vodi: cijena = korak iznad tuđeg maksimuma.
        final over = lCap + Auction.stepFor(lCap);
        final target = over < myCap ? over : myCap;
        price = roundCredits(bid > target ? bid : target);
        if (lCap > leader.amount) {
          bids.add(
            Bid(
              userId: leader.userId,
              userLabel: leader.userLabel,
              amount: lCap,
              time: at,
            ),
          );
        }
        bids.add(
          Bid(userId: userId, userLabel: user.handle, amount: price, time: at),
        );
        auto.remove(leader.userId);
        outbidUser = leader.userId;
        newLeader = userId;
      } else {
        // Automatska ponuda vodećeg je viša: on ostaje vodeći.
        bids.add(
          Bid(userId: userId, userLabel: user.handle, amount: myCap, time: at),
        );
        final over = myCap + Auction.stepFor(myCap);
        price = roundCredits(over < lCap ? over : lCap);
        bids.add(
          Bid(
            userId: leader.userId,
            userLabel: leader.userLabel,
            amount: price,
            time: at,
          ),
        );
        if (lCap <= price) auto.remove(leader.userId);
        outbidUser = userId;
        outbidByAuto = true;
        newLeader = leader.userId;
      }
    }

    if (newLeader == userId && max > price) auto[userId] = max;

    final remaining = a.endsAt.difference(at);
    final updated = a.copyWith(
      bids: bids,
      autoMax: auto,
      endsAt: remaining < extendWindow ? at.add(extendWindow) : null,
    );
    await _storage.putAuction(updated);
    final inbox = Inbox(_storage);
    if (outbidUser != null) {
      await inbox.send(
        outbidUser,
        outbidByAuto ? NotificationKind.outbidAuto : NotificationKind.outbid,
        args: [a.deviceName, price],
        targetId: a.id,
        now: at,
      );
    }
    await inbox.send(
      a.sellerId,
      NotificationKind.newBid,
      args: [a.deviceName, price],
      targetId: a.id,
      now: at,
    );
    return updated;
  }

  /// "Kupi odmah": kupac plaća [Auction.buyNowPrice] i odmah osvaja
  /// predmet; vodeća ponuda se vraća.
  Future<AuctionResult> buyNow({
    required String userId,
    required String auctionId,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final a = _requireAuction(auctionId);
    final user = _storage.userById(userId);
    if (user == null) throw TradeException(t('Korisnik ne postoji.'));
    if (!a.isActive || a.isExpired(at)) {
      throw TradeException(t('Aukcija je završila.'));
    }
    if (a.sellerId == userId) {
      throw TradeException(t('Ne možeš kupiti svoj predmet.'));
    }
    if (!a.canBuyNow) {
      throw TradeException(t('"Kupi odmah" više nije dostupno.'));
    }
    final price = a.buyNowPrice!;
    final updated = a.copyWith(
      bids: [
        ...a.bids,
        Bid(userId: userId, userLabel: user.handle, amount: price, time: at),
      ],
      autoMax: const {},
    );
    await _storage.putAuction(updated);
    return _settle(updated, at);
  }

  /// Uključuje/isključuje praćenje aukcije. Vraća `true` ako je prati.
  Future<bool> toggleWatch(String userId, String auctionId) async {
    final a = _requireAuction(auctionId);
    final list = [...a.watchers];
    final on = !list.remove(userId);
    if (on) list.add(userId);
    await _storage.putAuction(a.copyWith(watchers: list));
    return on;
  }

  /// Obavijest "završava za manje od 10 minuta" onima koji prate aukciju
  /// i onima koji su licitirali (jednom po aukciji).
  Future<int> notifyEndingSoon({DateTime? now}) async {
    final at = now ?? DateTime.now();
    var sent = 0;
    for (final a in _storage.auctions) {
      if (!a.isActive || a.endingNotified || a.isExpired(at)) continue;
      final left = a.endsAt.difference(at);
      // Kratke (testne) aukcije ne šalju podsjetnik.
      if (left > endingSoon || a.endsAt.difference(a.createdAt) <= endingSoon) {
        continue;
      }
      final inbox = Inbox(_storage);
      for (final id in {...a.watchers, for (final b in a.bids) b.userId}) {
        if (id == a.sellerId) continue;
        await inbox.send(
          id,
          NotificationKind.auctionEndingSoon,
          args: [a.deviceName, a.currentPrice],
          targetId: a.id,
          now: at,
        );
        sent++;
      }
      await _storage.putAuction(a.copyWith(endingNotified: true));
    }
    return sent;
  }

  /// Kada se šalje podsjetnik pred kraj aukcije.
  static const endingSoon = Duration(minutes: 10);

  // ---------------------------------------------------------- otkazivanje

  /// Prodavatelj smije otkazati samo aukciju bez ponuda.
  Future<void> cancelBySeller(String userId, String auctionId) async {
    final a = _requireAuction(auctionId);
    if (a.sellerId != userId) {
      throw TradeException(t('Samo prodavatelj može otkazati aukciju.'));
    }
    if (!a.isActive) throw TradeException(t('Aukcija je već završila.'));
    if (a.bids.isNotEmpty) {
      throw TradeException(
        t('Aukcija s ponudama ne može se otkazati — ponude su obvezujuće.'),
      );
    }
    await _storage.putAuction(a.copyWith(status: AuctionStatus.cancelled));
  }

  /// Admin može otkazati bilo koju aktivnu aukciju (ništa nije naplaćeno —
  /// pobjednik plaća tek na kraju).
  Future<void> cancelByAdmin(String auctionId) async {
    final a = _requireAuction(auctionId);
    if (!a.isActive) return;
    await _storage.putAuction(a.copyWith(status: AuctionStatus.cancelled));
  }

  /// Predmet se briše: otkaži njegovu aukciju (uz povrat ponude).
  Future<void> cancelForDevice(String deviceId) async {
    final a = _storage.activeAuctionFor(deviceId);
    if (a != null) await cancelByAdmin(a.id);
  }

  /// Korisnik se briše: otkaži njegove aukcije (uz povrat) i aukcije na
  /// kojima vodi (njegova blokirana ponuda nestaje s računom).
  Future<void> cancelForUser(String userId) async {
    for (final a in _storage.auctions.where((a) => a.isActive)) {
      if (a.sellerId == userId) {
        await cancelByAdmin(a.id);
      } else if (a.highestBid?.userId == userId) {
        await _storage.putAuction(a.copyWith(status: AuctionStatus.cancelled));
      }
    }
  }

  // ------------------------------------------------------------- završetak

  /// Zaključuje sve istekle aukcije. Poziva se periodički dok aplikacija radi
  /// (nema servera, pa se aukcije zaključuju kad se aplikacija pokrene).
  Future<List<AuctionResult>> settleExpired({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final results = <AuctionResult>[];
    for (final a in _storage.auctions) {
      if (!a.isActive || !a.isExpired(at)) continue;
      // Svježi zapis: zadnja ponuda (ili produljenje) mogla je stići s
      // drugog uređaja — pobjednik se određuje iz baze.
      await _storage.refreshAuction(a.id);
      final fresh = _storage.auctionById(a.id) ?? a;
      if (fresh.isActive && fresh.isExpired(at)) {
        results.add(await _settle(fresh, at));
      }
    }
    return results;
  }

  Future<AuctionResult> _settle(Auction a, DateTime at) async {
    final top = a.highestBid;
    if (top == null) {
      final done = a.copyWith(status: AuctionStatus.unsold);
      await _storage.putAuction(done);
      await Inbox(_storage).send(
        a.sellerId,
        NotificationKind.auctionUnsold,
        args: [a.deviceName],
        targetId: a.id,
        now: at,
      );
      return AuctionResult(done);
    }

    final device = _storage.deviceById(a.deviceId);
    final seller = _storage.userById(a.sellerId);
    final winner = _storage.userById(top.userId);
    if (device == null || seller == null || winner == null) {
      // Ne može se izvršiti (ništa nije naplaćeno).
      final done = a.copyWith(status: AuctionStatus.cancelled);
      await _storage.putAuction(done);
      return AuctionResult(done);
    }

    // Pobjednik plaća svoju ponudu; prodavatelju se odbija 10 % samo od
    // razlike iznad početne cijene.
    final fee = auctionCommission(top.amount, a.startPrice);
    final payout = auctionPayout(top.amount, a.startPrice);
    // Pobjednik plaća karticom (pružatelj plaćanja), prodavatelj dobiva
    // zaradu za isplatu.
    final done = a.copyWith(status: AuctionStatus.sold);
    // Jedan zapis za obje strane (vidi LoopTransaction.typeFor) — s ID-jem
    // aukcije i upisan samo jednom (atomski): ako dva uređaja istovremeno
    // zaključuju istu aukciju, prodaju i dostavu radi samo prvi.
    final sale = LoopTransaction(
      id: 'auction-${a.id}',
      type: TransactionType.sell,
      userId: seller.id,
      deviceId: device.id,
      deviceName: a.deviceName,
      price: top.amount,
      fee: fee,
      amount: payout,
      sellerId: seller.id,
      sellerLabel: seller.handle,
      buyerId: winner.id,
      buyerLabel: winner.handle,
      createdAt: at,
      isAuction: true,
    );
    final claimed = await _storage.claimTransaction(sale);
    if (!claimed) {
      await _storage.putAuction(done);
      return AuctionResult(done, winnerId: winner.id);
    }
    await _storage.putDevice(device.withOwner(winner.id));
    await Earnings(_storage).credit(sale);
    await _storage.putAuction(done);
    await _storage.recordSnapshot(seller.id, now: at);
    await _storage.recordSnapshot(winner.id, now: at);
    final inbox = Inbox(_storage);
    await inbox.send(
      winner.id,
      NotificationKind.auctionWon,
      args: [a.deviceName, top.amount],
      targetId: a.id,
      now: at,
    );
    await inbox.send(
      seller.id,
      NotificationKind.auctionSold,
      args: [a.deviceName, top.amount],
      targetId: a.id,
      now: at,
    );
    for (final loser in {
      for (final b in a.bids)
        if (b.userId != winner.id) b.userId,
    }) {
      await inbox.send(
        loser,
        NotificationKind.auctionLost,
        args: [a.deviceName],
        targetId: a.id,
        now: at,
      );
    }
    // Pobjednik bira način dostave u "Moje dostave".
    await DeliveryService(_storage).createPending(
      id: 'auction-${a.id}',
      userId: winner.id,
      deviceId: device.id,
      deviceName: a.deviceName,
      sellerId: seller.id,
      now: at,
    );
    return AuctionResult(done, winnerId: winner.id);
  }

  // --------------------------------------------------------------- pomoćno

  Auction _requireAuction(String id) {
    final a = _storage.auctionById(id);
    if (a == null) throw TradeException(t('Aukcija ne postoji.'));
    return a;
  }
}
