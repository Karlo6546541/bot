import 'package:uuid/uuid.dart';

import '../models/auction.dart';
import '../models/loop_transaction.dart';
import '../utils/formatters.dart';
import 'auction_policy.dart';
import 'delivery_service.dart';
import 'fee.dart';
import 'storage_service.dart';
import 'trade_service.dart';
import '../l10n/tr.dart';

/// Ishod završene aukcije (za obavijesti sudionicima).
class AuctionResult {
  const AuctionResult(this.auction, {this.winnerId});
  final Auction auction;
  final String? winnerId;
}

/// Pravila aukcija:
/// - ponude su obvezujuće i ne mogu se povući ni smanjiti;
/// - vodeći ponuđač ne može dati novu ponudu dok ga netko ne nadmaši;
/// - ponuda ne može biti veća od raspoloživih kredita;
/// - iznos vodeće ponude je blokiran (oduzet s kredita) i vraća se kad
///   ponuđača netko nadmaši ili se aukcija otkaže;
/// - ponuda u zadnjoj minuti produljuje aukciju na 1 minutu od ponude;
/// - na kraju pobjednik dobiva predmet, prodavatelj iznos − 5% fee-a.
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
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final user = _storage.userById(userId);
    final device = _storage.deviceById(deviceId);
    if (user == null || device == null) {
      throw TradeException(t('Predmet ne postoji.'));
    }
    if (device.ownerId != userId) {
      throw TradeException(t('Na aukciju možeš staviti samo svoj predmet.'));
    }
    if (_storage.activeAuctionFor(deviceId) != null) {
      throw TradeException(t('Predmet je već na aukciji.'));
    }
    if (startPrice <= 0) {
      throw TradeException(t('Početna cijena mora biti veća od 0.'));
    }
    if (duration <= Duration.zero) {
      throw TradeException(t('Odaberi trajanje aukcije.'));
    }
    // Pravila protiv masovnog objavljivanja (limit, naknada, pauza…).
    final reason = policy.blockReason(userId, device, now: at);
    if (reason != null) throw TradeException(reason);

    final fee = AuctionPolicy.listingFee(device);
    await _storage.putUser(
      user.copyWith(credits: roundCredits(user.credits - fee)),
    );
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
    );
    await _storage.putAuction(auction);
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
        buyerLabel: 'LOOP',
        sellerId: userId,
        sellerLabel: user.handle,
        createdAt: at,
      ),
    );
    await _storage.recordSnapshot(userId, now: at);
    return auction;
  }

  // ------------------------------------------------------------ ponude

  Future<Auction> placeBid({
    required String userId,
    required String auctionId,
    required double amount,
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
      throw TradeException(t('Ne možeš licitirati na svoju aukciju.'));
    }
    if (a.highestBid?.userId == userId) {
      throw TradeException(
        t(
          'Već imaš najvišu ponudu. Ponuda je obvezujuća i ne može se povući ni promijeniti dok te netko ne nadmaši.',
        ),
      );
    }
    final bid = roundCredits(amount);
    if (bid < a.minNextBid) {
      throw TradeException(
        t('Najmanja ponuda je {0}.', [formatCredits(a.minNextBid)]),
      );
    }
    if (bid > user.credits) {
      throw TradeException(
        t('Ponuda ne može biti veća od tvojih kredita ({0}).', [
          formatCredits(user.credits),
        ]),
      );
    }

    // Blokiraj iznos novom vodećem ponuđaču, vrati ga prethodnom.
    await _storage.putUser(
      user.copyWith(credits: roundCredits(user.credits - bid)),
    );
    final previous = a.highestBid;
    if (previous != null) await _refund(previous);

    final remaining = a.endsAt.difference(at);
    final updated = a.copyWith(
      bids: [
        ...a.bids,
        Bid(userId: userId, userLabel: user.handle, amount: bid, time: at),
      ],
      endsAt: remaining < extendWindow ? at.add(extendWindow) : null,
    );
    await _storage.putAuction(updated);
    return updated;
  }

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

  /// Admin može otkazati bilo koju aktivnu aukciju; vodeća ponuda se vraća.
  Future<void> cancelByAdmin(String auctionId) async {
    final a = _requireAuction(auctionId);
    if (!a.isActive) return;
    final top = a.highestBid;
    if (top != null) await _refund(top);
    await _storage.putAuction(a.copyWith(status: AuctionStatus.cancelled));
    if (top != null) await _storage.recordSnapshot(top.userId);
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
      if (a.isActive && a.isExpired(at)) results.add(await _settle(a, at));
    }
    return results;
  }

  Future<AuctionResult> _settle(Auction a, DateTime at) async {
    final top = a.highestBid;
    if (top == null) {
      final done = a.copyWith(status: AuctionStatus.unsold);
      await _storage.putAuction(done);
      return AuctionResult(done);
    }

    final device = _storage.deviceById(a.deviceId);
    final seller = _storage.userById(a.sellerId);
    final winner = _storage.userById(top.userId);
    if (device == null || seller == null || winner == null) {
      // Ne može se izvršiti — vrati blokirani iznos ako je moguće.
      if (winner != null) await _refund(top);
      final done = a.copyWith(status: AuctionStatus.cancelled);
      await _storage.putAuction(done);
      return AuctionResult(done);
    }

    final fee = feeFor(top.amount);
    final payout = sellPayout(top.amount);
    // Kupčev iznos je već blokiran (oduzet) — samo prenosimo predmet.
    await _storage.putDevice(device.withOwner(winner.id));
    await _storage.putUser(
      seller.copyWith(credits: roundCredits(seller.credits + payout)),
    );
    final done = a.copyWith(status: AuctionStatus.sold);
    await _storage.putAuction(done);

    // Jedan zapis za obje strane (vidi LoopTransaction.typeFor).
    await _storage.putTransaction(
      LoopTransaction(
        id: _uuid.v4(),
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
      ),
    );
    await _storage.recordSnapshot(seller.id, now: at);
    await _storage.recordSnapshot(winner.id, now: at);
    // Pobjednik bira način dostave u "Moje dostave".
    await DeliveryService(_storage).createPending(
      userId: winner.id,
      deviceId: device.id,
      deviceName: a.deviceName,
      now: at,
    );
    return AuctionResult(done, winnerId: winner.id);
  }

  // --------------------------------------------------------------- pomoćno

  Future<void> _refund(Bid bid) async {
    final u = _storage.userById(bid.userId);
    if (u == null) return;
    await _storage.putUser(
      u.copyWith(credits: roundCredits(u.credits + bid.amount)),
    );
  }

  Auction _requireAuction(String id) {
    final a = _storage.auctionById(id);
    if (a == null) throw TradeException(t('Aukcija ne postoji.'));
    return a;
  }
}
