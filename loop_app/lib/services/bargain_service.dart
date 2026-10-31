import 'package:uuid/uuid.dart';

import '../l10n/tr.dart';
import '../models/app_notification.dart';
import '../models/price_offer.dart';
import '../utils/formatters.dart';
import 'fee.dart';
import 'inbox.dart';
import 'storage_service.dart';
import 'trade_service.dart';

/// Cjenkanje: kupac nudi cijenu za objavljeni predmet, prodavatelj
/// prihvaća, odbija ili daje protuponudu. Prihvaćena cijena vrijedi
/// [PriceOffer.acceptedFor] i samo za tog kupca (vidi [TradeService.buy]).
class BargainService {
  BargainService(this._storage);

  final StorageService _storage;
  final _uuid = const Uuid();

  /// Kupac nudi [amount] za predmet [deviceId].
  Future<PriceOffer> make({
    required String buyerId,
    required String deviceId,
    required double amount,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final buyer = _storage.userById(buyerId);
    final device = _storage.deviceById(deviceId);
    if (buyer == null || buyer.isGuest) {
      throw TradeException(t('Za ponudu se prijavi.'));
    }
    if (device == null || !device.isListed) {
      throw TradeException(
        t('Cijena se može ponuditi samo za oglase korisnika.'),
      );
    }
    if (device.ownerId == buyerId) {
      throw TradeException(t('Ovo je tvoj oglas.'));
    }
    final seller = _storage.userById(device.ownerId!);
    if (seller == null ||
        seller.pendingDeletion ||
        seller.blockedIds.contains(buyerId) ||
        buyer.blockedIds.contains(seller.id)) {
      throw TradeException(t('Predmet više nije dostupan.'));
    }
    final ask = device.priceAt(at);
    final value = roundCredits(amount);
    final min = roundCredits(ask * PriceOffer.minPercent / 100);
    if (value >= ask) {
      throw TradeException(
        t('Ponuda mora biti niža od cijene ({0}) — inače samo kupi.', [
          formatCredits(buyTotal(ask)),
        ]),
      );
    }
    if (value < min) {
      throw TradeException(
        t('Najniža ponuda je {0} ({1}% cijene).', [
          formatCredits(buyTotal(min)),
          '${PriceOffer.minPercent}',
        ]),
      );
    }
    final existing = active(buyerId, deviceId, at);
    if (existing != null) {
      throw TradeException(
        existing.status == BargainStatus.accepted
            ? t('Ponuda je već prihvaćena — kupi po dogovorenoj cijeni.')
            : t('Već imaš otvorenu ponudu za ovaj predmet.'),
      );
    }
    final offer = PriceOffer(
      id: _uuid.v4(),
      deviceId: deviceId,
      deviceName: device.name,
      buyerId: buyerId,
      sellerId: seller.id,
      amount: value,
      listPrice: ask,
      createdAt: at,
      updatedAt: at,
    );
    await _storage.putBargain(offer);
    await Inbox(_storage).send(
      seller.id,
      NotificationKind.bargainNew,
      args: [buyer.handle, value, device.name],
      targetId: deviceId,
      now: at,
    );
    return offer;
  }

  /// Otvorena ili prihvaćena (još važeća) ponuda kupca za predmet.
  PriceOffer? active(String buyerId, String deviceId, DateTime now) {
    for (final o in _storage.bargains) {
      if (o.buyerId != buyerId || o.deviceId != deviceId) continue;
      if (o.usableAt(now) || (o.isOpen && !o.staleAt(now))) return o;
    }
    return null;
  }

  /// Prihvaćena ponuda koju kupac može iskoristiti pri kupnji.
  PriceOffer? usable(String buyerId, String deviceId, DateTime now) {
    for (final o in _storage.bargains) {
      if (o.buyerId == buyerId && o.deviceId == deviceId && o.usableAt(now)) {
        return o;
      }
    }
    return null;
  }

  PriceOffer _require(String id) {
    final o = _storage.bargainById(id);
    if (o == null) throw TradeException(t('Ponuda ne postoji.'));
    return o;
  }

  PriceOffer _requireOpen(String id, DateTime now) {
    final o = _require(id);
    if (!o.isOpen || o.staleAt(now)) {
      throw TradeException(t('Ponuda više nije otvorena.'));
    }
    return o;
  }

  /// Prodavatelj prihvaća ponudu kupca.
  Future<PriceOffer> accept(String sellerId, String id, {DateTime? now}) async {
    await _storage.refreshBargain(id);
    final at = now ?? DateTime.now();
    final o = _requireOpen(id, at);
    if (o.sellerId != sellerId || o.status != BargainStatus.pending) {
      throw TradeException(t('Ovu ponudu ne možeš prihvatiti.'));
    }
    final done = o.copyWith(
      status: BargainStatus.accepted,
      updatedAt: at,
      validUntil: at.add(PriceOffer.acceptedFor),
    );
    await _storage.putBargain(done);
    await Inbox(_storage).send(
      o.buyerId,
      NotificationKind.bargainAccepted,
      args: [_handle(sellerId), buyTotal(o.amount), o.deviceName],
      targetId: o.deviceId,
      now: at,
    );
    return done;
  }

  /// Prodavatelj daje protuponudu [amount] (između ponude i cijene).
  Future<PriceOffer> counter(
    String sellerId,
    String id,
    double amount, {
    DateTime? now,
  }) async {
    await _storage.refreshBargain(id);
    final at = now ?? DateTime.now();
    final o = _requireOpen(id, at);
    if (o.sellerId != sellerId || o.status != BargainStatus.pending) {
      throw TradeException(t('Na ovu ponudu ne možeš dati protuponudu.'));
    }
    final value = roundCredits(amount);
    if (value <= o.amount || value >= o.listPrice) {
      throw TradeException(
        t('Protuponuda mora biti između {0} i {1}.', [
          formatCredits(o.amount),
          formatCredits(o.listPrice),
        ]),
      );
    }
    final done = o.copyWith(
      status: BargainStatus.countered,
      counterAmount: value,
      updatedAt: at,
    );
    await _storage.putBargain(done);
    await Inbox(_storage).send(
      o.buyerId,
      NotificationKind.bargainCountered,
      args: [_handle(sellerId), buyTotal(value), o.deviceName],
      targetId: o.deviceId,
      now: at,
    );
    return done;
  }

  /// Kupac prihvaća protuponudu.
  Future<PriceOffer> acceptCounter(
    String buyerId,
    String id, {
    DateTime? now,
  }) async {
    await _storage.refreshBargain(id);
    final at = now ?? DateTime.now();
    final o = _requireOpen(id, at);
    if (o.buyerId != buyerId || o.status != BargainStatus.countered) {
      throw TradeException(t('Ovu protuponudu ne možeš prihvatiti.'));
    }
    final done = o.copyWith(
      status: BargainStatus.accepted,
      updatedAt: at,
      validUntil: at.add(PriceOffer.acceptedFor),
    );
    await _storage.putBargain(done);
    await Inbox(_storage).send(
      o.sellerId,
      NotificationKind.counterAccepted,
      args: [_handle(buyerId), o.agreedPrice, o.deviceName],
      targetId: o.deviceId,
      now: at,
    );
    return done;
  }

  /// Odbijanje: prodavatelj odbija ponudu ili kupac odbija protuponudu.
  Future<PriceOffer> decline(String userId, String id, {DateTime? now}) async {
    await _storage.refreshBargain(id);
    final at = now ?? DateTime.now();
    final o = _requireOpen(id, at);
    final bySeller = o.sellerId == userId && o.status == BargainStatus.pending;
    final byBuyer = o.buyerId == userId && o.status == BargainStatus.countered;
    if (!bySeller && !byBuyer) {
      throw TradeException(t('Ovu ponudu ne možeš odbiti.'));
    }
    final done = o.copyWith(status: BargainStatus.declined, updatedAt: at);
    await _storage.putBargain(done);
    await Inbox(_storage).send(
      bySeller ? o.buyerId : o.sellerId,
      NotificationKind.bargainDeclined,
      args: [_handle(userId), o.deviceName],
      targetId: o.deviceId,
      now: at,
    );
    return done;
  }

  /// Kupac povlači svoju otvorenu ponudu.
  Future<PriceOffer> cancel(String buyerId, String id, {DateTime? now}) async {
    await _storage.refreshBargain(id);
    final at = now ?? DateTime.now();
    final o = _require(id);
    if (o.buyerId != buyerId ||
        !(o.isOpen || o.status == BargainStatus.accepted)) {
      throw TradeException(t('Ovu ponudu ne možeš povući.'));
    }
    final done = o.copyWith(status: BargainStatus.cancelled, updatedAt: at);
    await _storage.putBargain(done);
    return done;
  }

  /// Kupnja po dogovorenoj cijeni iskoristila je ponudu.
  Future<void> markUsed(PriceOffer o, DateTime at) => _storage.putBargain(
    o.copyWith(status: BargainStatus.used, updatedAt: at),
  );

  String _handle(String userId) =>
      _storage.userById(userId)?.handle ?? t('Korisnik');
}
