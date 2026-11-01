import '../l10n/tr.dart';
import '../models/app_notification.dart';
import '../models/delivery.dart';
import '../models/loop_transaction.dart';
import '../utils/formatters.dart';
import 'fee.dart';
import 'inbox.dart';
import 'storage_service.dart';
import 'trade_service.dart';

/// Povrati i sporovi (kao Whatnot "Get help with this purchase"):
///
/// 1. Kupac prijavi problem (prije potvrde primitka; od trgovca i 14 dana
///    nakon primitka). Prodavateljeva zarada od te prodaje se zadržava.
/// 2. Prodavatelj u 72 sata prihvati povrat ili ga odbije. Bez odgovora
///    novac se automatski vraća kupcu.
/// 3. Odbijen zahtjev odlučuje Subhasto (admin): povrat ili odbijanje.
///
/// Povrat: kupcu se vraća cijena predmeta i plaćena dostava (na karticu),
/// prodavatelju se odbija zarada od prodaje, a predmet se vraća prodavatelju.
class DisputeService {
  DisputeService(this._storage);

  final StorageService _storage;

  /// Povrat od trgovca vrijedi ovoliko dana od primitka.
  static const businessReturnDays = 14;

  /// Zapis prodaje za pošiljku (zarada prodavatelja).
  LoopTransaction? saleOf(Delivery d) => _storage.transactions
      .where(
        (x) =>
            x.type == TransactionType.sell &&
            x.deviceId == d.deviceId &&
            x.buyerId == d.buyerId &&
            (x.sellerId ?? x.userId) == d.sellerId,
      )
      .firstOrNull;

  /// Smije li kupac prijaviti problem za ovu pošiljku.
  bool canOpen(Delivery d, {DateTime? now}) {
    final at = now ?? DateTime.now();
    if (d.dispute != null || d.sellerId == null) return false;
    if (d.method == null || d.method == DeliveryMethod.digital) return false;
    if (d.confirmedAt == null) return true;
    final business =
        _storage.userById(d.sellerId!)?.seller?.isBusiness ?? false;
    return business &&
        at.difference(d.confirmedAt!).inDays < businessReturnDays;
  }

  /// Zarada prodavatelja zadržana zbog sporova u tijeku.
  double heldFor(String sellerId) {
    var held = 0.0;
    for (final d in _storage.deliveries) {
      if (d.sellerId != sellerId || !(d.dispute?.active ?? false)) continue;
      held += saleOf(d)?.amount ?? 0;
    }
    return roundCredits(held);
  }

  /// Kupac prijavljuje problem.
  Future<Delivery> open(
    String buyerId,
    String deliveryId,
    DisputeReason reason,
    String note, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final d = _storage.deliveryById(deliveryId);
    if (d == null || d.buyerId != buyerId) {
      throw TradeException(t('Pošiljka ne postoji.'));
    }
    if (!canOpen(d, now: at)) {
      throw TradeException(
        t('Za ovu kupnju više nije moguće prijaviti problem.'),
      );
    }
    final text = note.trim();
    if (text.length > DeliveryDispute.maxNote) {
      throw TradeException(
        t('Opis može imati najviše {0} znakova.', [
          '${DeliveryDispute.maxNote}',
        ]),
      );
    }
    final updated = d.copyWith(
      dispute: DeliveryDispute(reason: reason, openedAt: at, note: text),
    );
    await _storage.putDelivery(updated);
    final buyer = _storage.userById(buyerId);
    await Inbox(_storage).send(
      d.sellerId,
      NotificationKind.disputeOpened,
      args: [buyer?.handle ?? '', d.deviceName, reason.label],
      targetId: d.id,
      now: at,
    );
    return updated;
  }

  /// Prodavatelj prihvaća (povrat) ili odbija zahtjev (odlučuje Subhasto).
  Future<Delivery> respond(
    String sellerId,
    String deliveryId, {
    required bool accept,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final d = _storage.deliveryById(deliveryId);
    if (d == null || d.sellerId != sellerId) {
      throw TradeException(t('Pošiljka ne postoji.'));
    }
    final dispute = d.dispute;
    if (dispute == null || dispute.status != DisputeStatus.open) {
      throw TradeException(t('Zahtjev je već riješen.'));
    }
    if (accept) return _refund(d, at);
    final updated = d.copyWith(
      dispute: dispute.resolve(DisputeStatus.review, at),
    );
    await _storage.putDelivery(updated);
    await Inbox(_storage).send(
      d.buyerId,
      NotificationKind.disputeReview,
      args: [d.deviceName],
      targetId: d.id,
      now: at,
    );
    return updated;
  }

  /// Odluka Subhasta za odbijeni zahtjev.
  Future<Delivery> decide(
    String deliveryId, {
    required bool refund,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final d = _storage.deliveryById(deliveryId);
    final dispute = d?.dispute;
    if (d == null || dispute == null || !dispute.active) {
      throw TradeException(t('Zahtjev je već riješen.'));
    }
    if (refund) return _refund(d, at);
    final updated = d.copyWith(
      dispute: dispute.resolve(DisputeStatus.rejected, at),
    );
    await _storage.putDelivery(updated);
    for (final user in [d.buyerId, d.sellerId]) {
      await Inbox(_storage).send(
        user,
        NotificationKind.disputeRejected,
        args: [d.deviceName],
        targetId: d.id,
        now: at,
      );
    }
    return updated;
  }

  /// Zahtjevi bez odgovora prodavatelja nakon 72 h: novac se vraća kupcu.
  /// Vraća broj riješenih.
  Future<int> expire({DateTime? now}) async {
    final at = now ?? DateTime.now();
    var n = 0;
    for (final d in [..._storage.deliveries]) {
      final dispute = d.dispute;
      if (dispute == null || dispute.status != DisputeStatus.open) continue;
      if (at.isBefore(dispute.respondBy)) continue;
      await _refund(d, at);
      n++;
    }
    return n;
  }

  Future<Delivery> _refund(Delivery d, DateTime at) async {
    final sale = saleOf(d);
    final amount = roundCredits((sale?.price ?? 0) + d.cost);
    final updated = d.copyWith(
      dispute: d.dispute!.resolve(DisputeStatus.refunded, at, refund: amount),
    );
    await _storage.putDelivery(updated);
    // Prodavatelju se odbija zarada od te prodaje.
    final sellerId = d.sellerId;
    if (sale != null && sellerId != null) {
      await _storage.refreshUser(sellerId);
      final seller = _storage.userById(sellerId);
      if (seller != null) {
        await _storage.putUser(
          seller.copyWith(credits: roundCredits(seller.credits - sale.amount)),
        );
      }
      await _storage.putTransaction(
        LoopTransaction(
          id: 'refund-s-${d.id}',
          type: TransactionType.refund,
          userId: sellerId,
          deviceId: d.deviceId,
          deviceName: t('Povrat · {0}', [d.deviceName]),
          price: sale.price,
          fee: 0,
          amount: sale.amount,
          buyerId: d.buyerId,
          sellerId: sellerId,
          buyerLabel: _storage.userById(d.buyerId)?.handle ?? '',
          sellerLabel: seller?.handle ?? '',
          createdAt: at,
        ),
      );
    }
    // Kupcu se novac vraća na karticu (zapis u njegovim transakcijama).
    await _storage.putTransaction(
      LoopTransaction(
        id: 'refund-b-${d.id}',
        type: TransactionType.refund,
        userId: d.buyerId,
        deviceId: d.deviceId,
        deviceName: t('Povrat · {0}', [d.deviceName]),
        price: amount,
        fee: 0,
        amount: amount,
        buyerId: d.buyerId,
        sellerId: sellerId,
        buyerLabel: _storage.userById(d.buyerId)?.handle ?? '',
        sellerLabel: sellerId == null
            ? ''
            : _storage.userById(sellerId)?.handle ?? '',
        createdAt: at,
      ),
    );
    // Predmet se vraća prodavatelju (kupac ga šalje natrag).
    final device = _storage.deviceById(d.deviceId);
    if (device != null && sellerId != null && device.ownerId == d.buyerId) {
      await _storage.putDevice(device.withOwner(sellerId));
    }
    for (final user in [d.buyerId, sellerId]) {
      await Inbox(_storage).send(
        user,
        NotificationKind.disputeRefunded,
        args: [d.deviceName, formatCredits(amount)],
        targetId: d.id,
        now: at,
      );
    }
    return updated;
  }
}
