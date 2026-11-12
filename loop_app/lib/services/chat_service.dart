import 'package:uuid/uuid.dart';

import '../l10n/tr.dart';
import '../models/app_notification.dart';
import '../models/chat_message.dart';
import 'inbox.dart';
import 'storage_service.dart';
import 'trade_service.dart';

/// Poruke između korisnika (npr. pitanje o predmetu prije kupnje).
class ChatService {
  ChatService(this._storage);

  final StorageService _storage;
  final _uuid = const Uuid();

  /// Pošiljatelj službenih poruka (PIN-ovi, upute za slanje) — razgovor
  /// je zaključan na vrhu Poruka i ne može se odgovoriti.
  static const systemId = 'subhasto';

  Future<ChatMessage> send({
    required String senderId,
    required String receiverId,
    required String text,
    String? deviceId,
    DateTime? now,
  }) async {
    final body = text.trim();
    if (body.isEmpty) throw TradeException(t('Napiši poruku.'));
    if (body.length > ChatMessage.maxLength) {
      throw TradeException(
        t('Poruka može imati najviše {0} znakova.', [ChatMessage.maxLength]),
      );
    }
    if (senderId == receiverId) {
      throw TradeException(t('Ne možeš slati poruke sam sebi.'));
    }
    final sender = _storage.userById(senderId);
    final receiver = _storage.userById(receiverId);
    if (sender == null || receiver == null || receiver.pendingDeletion) {
      throw TradeException(t('Korisnik ne postoji.'));
    }
    if (receiver.blockedIds.contains(senderId) ||
        sender.blockedIds.contains(receiverId)) {
      throw TradeException(t('Ne možeš poslati poruku ovom korisniku.'));
    }
    final at = now ?? DateTime.now();
    final m = ChatMessage(
      id: _uuid.v4(),
      senderId: senderId,
      receiverId: receiverId,
      text: body,
      deviceId: deviceId,
      createdAt: at,
    );
    await _storage.putMessage(m);
    // Jedna obavijest dok primatelj ne pročita — bez spama za svaku poruku.
    final waiting = _storage.notifications.any(
      (n) =>
          n.userId == receiverId &&
          !n.read &&
          n.kind == NotificationKind.newMessage &&
          n.targetId == senderId,
    );
    if (!waiting) {
      await Inbox(_storage).send(
        receiverId,
        NotificationKind.newMessage,
        args: [
          sender.handle,
          body.length > 60 ? '${body.substring(0, 60)}…' : body,
        ],
        targetId: senderId,
        now: at,
      );
    }
    return m;
  }

  /// Označava poruke od [otherId] kao pročitane (i njihovu obavijest).
  Future<void> markRead(String userId, String otherId) async {
    for (final m in _storage.messages) {
      if (m.receiverId == userId && m.senderId == otherId && !m.read) {
        await _storage.putMessage(m.markRead());
      }
    }
    for (final n in _storage.notifications) {
      if (n.userId == userId &&
          !n.read &&
          n.kind == NotificationKind.newMessage &&
          n.targetId == otherId) {
        await _storage.putNotification(n.markRead());
      }
    }
  }
}
