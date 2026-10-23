import 'package:uuid/uuid.dart';

import '../l10n/tr.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/loop_transaction.dart';
import '../models/report.dart';
import '../models/review.dart';
import 'fee.dart';
import 'inbox.dart';
import 'storage_service.dart';
import 'trade_service.dart';

/// Ocjene prodavatelja, prijave, blokiranje i čitanje obavijesti.
class CommunityService {
  CommunityService(this._storage);

  final StorageService _storage;
  final _uuid = const Uuid();

  // ------------------------------------------------------------- ocjene

  /// Ocjena trgovine s profila (1–5 zvjezdica). Svaki korisnik ima jednu
  /// ocjenu po trgovini — nova ocjena zamjenjuje staru.
  Future<Review> rateShop({
    required String raterId,
    required String sellerId,
    required int stars,
    String comment = '',
    DateTime? now,
  }) async {
    final rater = _storage.userById(raterId);
    final seller = _storage.userById(sellerId);
    if (rater == null || rater.isGuest) {
      throw TradeException(t('Za ocjenu se prijavi.'));
    }
    if (seller == null) throw TradeException(t('Korisnik ne postoji.'));
    if (raterId == sellerId) {
      throw TradeException(t('Ne možeš ocijeniti svoju trgovinu.'));
    }
    if (stars < 1 || stars > 5) {
      throw TradeException(t('Odaberi od 1 do 5 zvjezdica.'));
    }
    final text = comment.trim();
    if (text.length > Review.maxComment) {
      throw TradeException(
        t('Komentar može imati najviše {0} znakova.', [Review.maxComment]),
      );
    }
    final review = Review(
      id: 'shop-$raterId-$sellerId',
      sellerId: sellerId,
      buyerId: raterId,
      buyerLabel: rater.handle,
      deliveryId: '',
      deviceName: '',
      stars: stars,
      comment: text,
      createdAt: now ?? DateTime.now(),
      // Kupio je od ove trgovine → "Provjerena kupnja" (Omnibus).
      verifiedFlag: _storage.transactions.any(
        (t) => t.buyerId == raterId && t.sellerId == sellerId,
      ),
    );
    final first = _storage.reviews.every((r) => r.id != review.id);
    await _storage.putReview(review);
    if (first) {
      await Inbox(_storage).send(
        sellerId,
        NotificationKind.newReview,
        args: [rater.handle, '${'★' * stars}${'☆' * (5 - stars)}'],
        targetId: sellerId,
        now: now,
      );
    }
    return review;
  }

  /// Kupac ocjenjuje prodavatelja nakon što je potvrdio primitak.
  Future<Review> review({
    required String buyerId,
    required String deliveryId,
    required int stars,
    String comment = '',
    DateTime? now,
  }) async {
    final d = _storage.deliveryById(deliveryId);
    final buyer = _storage.userById(buyerId);
    if (d == null || buyer == null || d.buyerId != buyerId) {
      throw TradeException(t('Pošiljka ne postoji.'));
    }
    if (d.sellerId == null) {
      throw TradeException(t('LICIT Market se ne ocjenjuje.'));
    }
    if (d.confirmedAt == null) {
      throw TradeException(t('Ocijeniti možeš nakon potvrde primitka.'));
    }
    if (d.reviewed) throw TradeException(t('Već si ocijenio ovu kupnju.'));
    if (stars < 1 || stars > 5) {
      throw TradeException(t('Odaberi od 1 do 5 zvjezdica.'));
    }
    final text = comment.trim();
    if (text.length > Review.maxComment) {
      throw TradeException(
        t('Komentar može imati najviše {0} znakova.', [Review.maxComment]),
      );
    }
    final review = Review(
      id: _uuid.v4(),
      sellerId: d.sellerId!,
      buyerId: buyerId,
      buyerLabel: buyer.handle,
      deliveryId: d.id,
      deviceName: d.deviceName,
      stars: stars,
      comment: text,
      createdAt: now ?? DateTime.now(),
    );
    await _storage.putReview(review);
    await _storage.putDelivery(d.copyWith(reviewed: true));
    await Inbox(_storage).send(
      d.sellerId,
      NotificationKind.newReview,
      args: [buyer.handle, '${'★' * stars}${'☆' * (5 - stars)}'],
      targetId: d.sellerId,
      now: now,
    );
    return review;
  }

  // ------------------------------------------------------------ prijave

  Future<Report> report({
    required String reporterId,
    required String targetType,
    required String targetId,
    required ReportReason reason,
    String note = '',
    DateTime? now,
  }) async {
    final reporter = _storage.userById(reporterId);
    if (reporter == null) throw TradeException(t('Korisnik ne postoji.'));
    final String label;
    if (targetType == 'device') {
      final d = _storage.deviceById(targetId);
      if (d == null) throw TradeException(t('Predmet ne postoji.'));
      if (d.ownerId == reporterId) {
        throw TradeException(t('Ne možeš prijaviti vlastiti oglas.'));
      }
      label = '${d.name} ${d.model}';
    } else {
      final u = _storage.userById(targetId);
      if (u == null) throw TradeException(t('Korisnik ne postoji.'));
      if (u.id == reporterId) {
        throw TradeException(t('Ne možeš prijaviti sam sebe.'));
      }
      label = u.handle;
    }
    if (note.trim().length > Report.maxNote) {
      throw TradeException(
        t('Opis može imati najviše {0} znakova.', [Report.maxNote]),
      );
    }
    if (_storage.reports.any(
      (r) => r.isOpen && r.reporterId == reporterId && r.targetId == targetId,
    )) {
      throw TradeException(t('Ovo si već prijavio — admin će pregledati.'));
    }
    final r = Report(
      id: _uuid.v4(),
      reporterId: reporterId,
      reporterLabel: reporter.handle,
      targetType: targetType,
      targetId: targetId,
      targetLabel: label,
      reason: reason,
      note: note.trim(),
      createdAt: now ?? DateTime.now(),
    );
    await _storage.putReport(r);
    return r;
  }

  /// Obrazloženje odluke (DSA čl. 17): vlasniku uklonjenog oglasa javlja
  /// razlog i mogućnost žalbe. Zove se prije brisanja predmeta.
  Future<void> notifyRemoval(String reportId, {DateTime? now}) async {
    final r = _storage.reports.where((r) => r.id == reportId).firstOrNull;
    if (r == null || !r.isDevice) return;
    final owner = _storage.deviceById(r.targetId)?.ownerId;
    if (owner == null) return;
    await Inbox(_storage).send(
      owner,
      NotificationKind.contentRemoved,
      args: [r.targetLabel, r.reason.label],
      targetId: r.id,
      now: now,
    );
  }

  /// Žalba na odluku o uklanjanju (DSA čl. 20) — ide adminu kao prijava
  /// vrste 'appeal'.
  Future<Report> appeal({
    required String userId,
    required String reportId,
    required String text,
    DateTime? now,
  }) async {
    final user = _storage.userById(userId);
    if (user == null) throw TradeException(t('Korisnik ne postoji.'));
    final original = _storage.reports
        .where((r) => r.id == reportId)
        .firstOrNull;
    if (original == null) throw TradeException(t('Odluka ne postoji.'));
    final body = text.trim();
    if (body.length < 10) {
      throw TradeException(t('Napiši ukratko zašto se ne slažeš.'));
    }
    if (body.length > Report.maxNote) {
      throw TradeException(
        t('Opis može imati najviše {0} znakova.', [Report.maxNote]),
      );
    }
    if (_storage.reports.any(
      (r) => r.isAppeal && r.targetId == reportId && r.reporterId == userId,
    )) {
      throw TradeException(t('Žalbu si već poslao — javit ćemo ti odluku.'));
    }
    final r = Report(
      id: _uuid.v4(),
      reporterId: userId,
      reporterLabel: user.handle,
      targetType: 'appeal',
      targetId: reportId,
      targetLabel: t('Žalba: {0}', [original.targetLabel]),
      reason: ReportReason.other,
      note: body,
      createdAt: now ?? DateTime.now(),
    );
    await _storage.putReport(r);
    return r;
  }

  /// Admin zatvara prijavu (riješeno / odbačeno) i javlja prijavitelju.
  Future<void> closeReport(
    String reportId,
    ReportStatus status, {
    DateTime? now,
  }) async {
    final r = _storage.reports.where((r) => r.id == reportId).firstOrNull;
    if (r == null || !r.isOpen) return;
    await _storage.putReport(r.close(status, now ?? DateTime.now()));
    if (status == ReportStatus.resolved) {
      await Inbox(
        _storage,
      ).send(r.reporterId, NotificationKind.reportResolved, now: now);
    }
  }

  // ---------------------------------------------------------- blokiranje

  /// Blokira ili odblokira korisnika. Vraća `true` ako je sada blokiran.
  Future<bool> toggleBlock(String userId, String otherId) async {
    if (userId == otherId) {
      throw TradeException(t('Ne možeš blokirati sam sebe.'));
    }
    final user = _storage.userById(userId);
    if (user == null) throw TradeException(t('Korisnik ne postoji.'));
    final list = [...user.blockedIds];
    final blocked = !list.remove(otherId);
    if (blocked) list.add(otherId);
    await _storage.putUser(user.copyWith(blockedIds: list));
    return blocked;
  }

  // ------------------------------------------------------------ praćenje

  /// Prati ili prestaje pratiti prodavatelja. Vraća `true` ako ga sada prati.
  Future<bool> toggleFollow(String userId, String sellerId) async {
    if (userId == sellerId) {
      throw TradeException(t('Ne možeš pratiti sam sebe.'));
    }
    final user = _storage.userById(userId);
    final seller = _storage.userById(sellerId);
    if (user == null || seller == null) {
      throw TradeException(t('Korisnik ne postoji.'));
    }
    final list = [...user.following];
    final followed = !list.remove(sellerId);
    if (followed) list.add(sellerId);
    await _storage.putUser(user.copyWith(following: list));
    if (followed) {
      await Inbox(_storage).send(
        sellerId,
        NotificationKind.newFollower,
        args: [user.handle],
        targetId: userId,
      );
    }
    return followed;
  }

  /// Broj pratitelja korisnika.
  int followersOf(String userId) =>
      _storage.users.where((u) => u.following.contains(userId)).length;

  // ----------------------------------------------------------- isticanje

  /// Cijena isticanja računa za jedan tjedan.
  static const promotionWeekly = 4.99;
  static const maxPromotionWeeks = 4;

  /// Plaća isticanje računa na [weeks] tjedana: oglasi se prikazuju prvi
  /// (oznaka "Istaknuto"), a račun je istaknut i na početnoj. Produljuje
  /// postojeće isticanje.
  Future<AppUser> promote(String userId, int weeks, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final user = _storage.userById(userId);
    if (user == null || user.isGuest) {
      throw TradeException(t('Za isticanje se prijavi.'));
    }
    if (weeks < 1 || weeks > maxPromotionWeeks) {
      throw TradeException(
        t('Isticanje se plaća za 1 do {0} tjedna.', ['$maxPromotionWeeks']),
      );
    }
    final cost = roundCredits(promotionWeekly * weeks);
    // Isticanje se plaća karticom (bilježi se kao transakcija).
    final from = user.promotedAt(at) ? user.promotedUntil! : at;
    final updated = user.copyWith(
      promotedUntil: from.add(Duration(days: 7 * weeks)),
    );
    await _storage.putUser(updated);
    await _storage.putTransaction(
      LoopTransaction(
        id: _uuid.v4(),
        type: TransactionType.promotion,
        userId: userId,
        deviceId: '',
        deviceName: t('Isticanje računa · {0} tj.', ['$weeks']),
        price: cost,
        fee: 0,
        amount: cost,
        buyerId: userId,
        buyerLabel: user.handle,
        sellerLabel: 'LICIT',
        createdAt: at,
      ),
    );
    await _storage.recordSnapshot(userId, now: at);
    return updated;
  }

  // ----------------------------------------------------------- obavijesti

  Future<void> markRead(String userId, {String? notificationId}) async {
    for (final n in _storage.notifications) {
      if (n.userId == userId &&
          !n.read &&
          (notificationId == null || n.id == notificationId)) {
        await _storage.putNotification(n.markRead());
      }
    }
  }
}
