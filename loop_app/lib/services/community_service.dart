import 'package:uuid/uuid.dart';

import '../l10n/tr.dart';
import '../models/app_notification.dart';
import '../models/report.dart';
import '../models/review.dart';
import 'inbox.dart';
import 'storage_service.dart';
import 'trade_service.dart';

/// Ocjene prodavatelja, prijave, blokiranje i čitanje obavijesti.
class CommunityService {
  CommunityService(this._storage);

  final StorageService _storage;
  final _uuid = const Uuid();

  // ------------------------------------------------------------- ocjene

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
      throw TradeException(t('LOOP Market se ne ocjenjuje.'));
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
