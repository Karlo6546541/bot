import 'package:uuid/uuid.dart';

import '../models/app_notification.dart';
import 'storage_service.dart';

/// Stvara obavijesti za korisnike (nadmašen na aukciji, prodan predmet,
/// nova ocjena…). Obavijesti se sinkroniziraju kao i ostali podaci, pa ih
/// primatelj vidi i na drugom uređaju.
class Inbox {
  Inbox(this._storage);

  final StorageService _storage;
  static const _uuid = Uuid();

  /// Najviše obavijesti po korisniku (starije se brišu).
  static const maxPerUser = 100;

  Future<void> send(
    String? userId,
    NotificationKind kind, {
    List<Object> args = const [],
    String? targetId,
    DateTime? now,
  }) async {
    final user = userId == null ? null : _storage.userById(userId);
    if (user == null) return;
    // Korisnik je isključio ovu vrstu obavijesti.
    final pref = NotificationPref.of(kind);
    if (pref != null && user.mutedNotifications.contains(pref.name)) return;
    await _storage.putNotification(
      AppNotification(
        id: _uuid.v4(),
        userId: user.id,
        kind: kind,
        args: args,
        targetId: targetId,
        createdAt: now ?? DateTime.now(),
      ),
    );
    final mine =
        _storage.notifications.where((n) => n.userId == user.id).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final old in mine.skip(maxPerUser)) {
      await _storage.deleteNotification(old.id);
    }
  }

  /// Obavijest svim pratiteljima prodavatelja [sellerId].
  Future<int> toFollowers(
    String sellerId,
    NotificationKind kind, {
    List<Object> args = const [],
    String? targetId,
    DateTime? now,
  }) async {
    var sent = 0;
    for (final u in _storage.users) {
      if (u.id == sellerId || !u.following.contains(sellerId)) continue;
      await send(u.id, kind, args: args, targetId: targetId, now: now);
      sent++;
    }
    return sent;
  }
}
