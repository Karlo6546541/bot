import 'package:uuid/uuid.dart';

import '../l10n/tr.dart';
import '../models/app_notification.dart';
import '../models/loop_transaction.dart';
import '../models/swap_offer.dart';
import '../utils/formatters.dart';
import 'delivery_service.dart';
import 'fee.dart';
import 'inbox.dart';
import 'storage_service.dart';
import 'trade_service.dart';

/// Zamjena predmet-za-predmet (uz nadoplatu u kreditima).
///
/// Ponuditelj nudi svoj predmet (+ krediti) za predmet koji je drugi
/// korisnik objavio u Marketu. Kad vlasnik prihvati, predmeti mijenjaju
/// vlasnike, nadoplata prelazi vlasniku (− 5% fee), a oboje biraju
/// dostavu u "Moje dostave".
class SwapService {
  SwapService(this._storage);

  final StorageService _storage;
  final _uuid = const Uuid();

  Future<SwapOffer> offer({
    required String fromId,
    required String wantedDeviceId,
    required String offeredDeviceId,
    double extraCredits = 0,
    String message = '',
    DateTime? now,
  }) async {
    final from = _storage.userById(fromId);
    final wanted = _storage.deviceById(wantedDeviceId);
    final offered = _storage.deviceById(offeredDeviceId);
    if (from == null) throw TradeException(t('Korisnik ne postoji.'));
    if (wanted == null || !wanted.isListed || wanted.ownerId == fromId) {
      throw TradeException(
        t('Zamjena je moguća samo za tuđe predmete u Marketu.'),
      );
    }
    final owner = _storage.userById(wanted.ownerId!);
    if (owner == null ||
        owner.pendingDeletion ||
        owner.blockedIds.contains(fromId)) {
      throw TradeException(t('Predmet više nije dostupan.'));
    }
    if (offered == null || offered.ownerId != fromId) {
      throw TradeException(t('Ponuditi možeš samo svoj predmet.'));
    }
    if (_storage.activeAuctionFor(offeredDeviceId) != null) {
      throw TradeException(t('Predmet na aukciji ne možeš ponuditi.'));
    }
    final extra = roundCredits(extraCredits);
    if (extra < 0) throw TradeException(t('Nadoplata ne može biti negativna.'));
    if (extra > from.credits) {
      throw TradeException(
        t('Nemaš dovoljno kredita za nadoplatu ({0}).', [
          formatCredits(from.credits),
        ]),
      );
    }
    if (message.trim().length > SwapOffer.maxMessage) {
      throw TradeException(
        t('Poruka može imati najviše {0} znakova.', [SwapOffer.maxMessage]),
      );
    }
    if (_storage.offers.any(
      (o) =>
          o.isPending &&
          o.fromId == fromId &&
          o.wantedDeviceId == wantedDeviceId,
    )) {
      throw TradeException(
        t('Već imaš ponudu za ovaj predmet — pričekaj odgovor ili je povuci.'),
      );
    }
    final o = SwapOffer(
      id: _uuid.v4(),
      fromId: fromId,
      toId: owner.id,
      wantedDeviceId: wanted.id,
      wantedName: '${wanted.name} ${wanted.model}',
      offeredDeviceId: offered.id,
      offeredName: '${offered.name} ${offered.model}',
      extraCredits: extra,
      message: message.trim(),
      createdAt: now ?? DateTime.now(),
    );
    await _storage.putOffer(o);
    await Inbox(_storage).send(
      owner.id,
      NotificationKind.swapOffer,
      args: [from.handle, wanted.name],
      targetId: fromId,
      now: now,
    );
    return o;
  }

  /// Vlasnik prihvaća: predmeti i nadoplata mijenjaju vlasnike.
  Future<SwapOffer> accept(
    String userId,
    String offerId, {
    DateTime? now,
  }) async {
    final o = _require(offerId);
    if (o.toId != userId) {
      throw TradeException(t('Samo vlasnik predmeta može prihvatiti zamjenu.'));
    }
    if (!o.isPending) throw TradeException(t('Ponuda više nije aktivna.'));
    final at = now ?? DateTime.now();
    final from = _storage.userById(o.fromId);
    final to = _storage.userById(o.toId);
    final wanted = _storage.deviceById(o.wantedDeviceId);
    final offered = _storage.deviceById(o.offeredDeviceId);
    final stillValid =
        from != null &&
        to != null &&
        wanted?.ownerId == to.id &&
        offered?.ownerId == from.id &&
        _storage.activeAuctionFor(o.wantedDeviceId) == null &&
        _storage.activeAuctionFor(o.offeredDeviceId) == null;
    if (!stillValid) {
      await _storage.putOffer(o.withStatus(SwapStatus.failed, at));
      throw TradeException(
        t('Zamjena više nije moguća — jedan od predmeta nije dostupan.'),
      );
    }
    if (from.credits < o.extraCredits) {
      await _storage.putOffer(o.withStatus(SwapStatus.failed, at));
      throw TradeException(
        t('{0} više nema dovoljno kredita za nadoplatu.', [from.handle]),
      );
    }

    final fee = o.extraCredits > 0 ? feeFor(o.extraCredits) : 0.0;
    final payout = roundCredits(o.extraCredits - fee);
    await _storage.putDevice(wanted!.withOwner(from.id));
    await _storage.putDevice(offered!.withOwner(to.id));
    await _storage.putUser(
      from.copyWith(credits: roundCredits(from.credits - o.extraCredits)),
    );
    await _storage.putUser(
      to.copyWith(credits: roundCredits(to.credits + payout)),
    );

    final name = t('{0} ⇄ {1}', [o.wantedName, o.offeredName]);
    for (final (userId, amount, txFee) in [
      (from.id, o.extraCredits, 0.0),
      (to.id, payout, fee),
    ]) {
      await _storage.putTransaction(
        LoopTransaction(
          id: _uuid.v4(),
          type: TransactionType.swap,
          userId: userId,
          deviceId: wanted.id,
          deviceName: name,
          price: o.extraCredits,
          fee: txFee,
          amount: amount,
          buyerId: from.id,
          buyerLabel: from.handle,
          sellerId: to.id,
          sellerLabel: to.handle,
          createdAt: at,
        ),
      );
    }

    // Oboje biraju dostavu; nakon primitka mogu ocijeniti jedno drugo.
    final deliveries = DeliveryService(_storage);
    await deliveries.createPending(
      userId: from.id,
      deviceId: wanted.id,
      deviceName: o.wantedName,
      sellerId: to.id,
      fromAuction: false,
      now: at,
    );
    await deliveries.createPending(
      userId: to.id,
      deviceId: offered.id,
      deviceName: o.offeredName,
      sellerId: from.id,
      fromAuction: false,
      now: at,
    );

    final done = o.withStatus(SwapStatus.accepted, at);
    await _storage.putOffer(done);
    // Ostale ponude za ove predmete više ne vrijede.
    for (final other in _storage.offers.where((x) => x.isPending)) {
      final ids = {o.wantedDeviceId, o.offeredDeviceId};
      if (ids.contains(other.wantedDeviceId) ||
          ids.contains(other.offeredDeviceId)) {
        await _storage.putOffer(other.withStatus(SwapStatus.failed, at));
      }
    }
    await _storage.recordSnapshot(from.id, now: at);
    await _storage.recordSnapshot(to.id, now: at);
    await Inbox(_storage).send(
      from.id,
      NotificationKind.swapAccepted,
      args: [to.handle, wanted.name],
      targetId: to.id,
      now: at,
    );
    return done;
  }

  Future<void> decline(String userId, String offerId, {DateTime? now}) async {
    final o = _require(offerId);
    if (o.toId != userId) {
      throw TradeException(t('Samo vlasnik predmeta može odbiti zamjenu.'));
    }
    if (!o.isPending) return;
    await _storage.putOffer(
      o.withStatus(SwapStatus.declined, now ?? DateTime.now()),
    );
    await Inbox(_storage).send(
      o.fromId,
      NotificationKind.swapDeclined,
      args: [_storage.userById(userId)?.handle ?? '', o.wantedName],
      targetId: userId,
      now: now,
    );
  }

  Future<void> withdraw(String userId, String offerId, {DateTime? now}) async {
    final o = _require(offerId);
    if (o.fromId != userId) {
      throw TradeException(t('Samo ponuditelj može povući ponudu.'));
    }
    if (!o.isPending) return;
    await _storage.putOffer(
      o.withStatus(SwapStatus.cancelled, now ?? DateTime.now()),
    );
  }

  SwapOffer _require(String id) {
    final o = _storage.offerById(id);
    if (o == null) throw TradeException(t('Ponuda ne postoji.'));
    return o;
  }
}
