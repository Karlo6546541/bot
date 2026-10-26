import '../l10n/tr.dart';
import '../models/chat_message.dart';
import '../models/delivery.dart';
import 'boxnow/boxnow_demo.dart';
import 'chat_service.dart';

/// Službene poruke od Subhasta (PIN-ovi, upute za slanje). Grade se iz
/// pošiljki pa ih svaki korisnik vidi i kad poruku nije zapisao njegov
/// uređaj; ID-ovi su stalni pa se spremljena i izračunata ne udvostruče.
class SystemMessages {
  const SystemMessages._();

  /// Prodavač: pošalji paket (s PIN-om za predaju na paketomatu).
  static ChatMessage ship(Delivery d, String buyerLabel) {
    final m = d.method!;
    return ChatMessage(
      id: 'sys-ship-${d.id}',
      senderId: ChatService.systemId,
      receiverId: d.sellerId ?? '',
      deviceId: d.deviceId,
      createdAt: d.startedAt ?? d.createdAt,
      text: m == DeliveryMethod.parcelLocker
          ? t(
              '📦 Pošalji "{0}" kupcu {1}.\nBOX NOW pošiljka {2} · paketomat: {3}\nPIN za predaju: {4}\nNa bilo kojem BOX NOW paketomatu odaberi "Pošalji paket" i upiši PIN.',
              [
                d.deviceName,
                buyerLabel,
                BoxNowDemo.parcelId(d),
                d.destination ?? '',
                BoxNowDemo.dropOffPin(d),
              ],
            )
          : t(
              '📦 Pošalji "{0}" kupcu {1} ({2}). Kod pošiljke: {3} — otpremnica je u Moje → Otpremnice.',
              [d.deviceName, buyerLabel, m.label, d.trackingNumber ?? ''],
            ),
    );
  }

  /// Kupac: paket čeka u paketomatu (s PIN-om za preuzimanje).
  static ChatMessage pickup(Delivery d, {DateTime? at}) => ChatMessage(
    id: 'sys-pickup-${d.id}',
    senderId: ChatService.systemId,
    receiverId: d.buyerId,
    deviceId: d.deviceId,
    createdAt:
        d.stepAt(d.steps.indexOf(DeliveryStatus.inLocker)) ?? at ?? d.createdAt,
    text: t(
      '📬 "{0}" te čeka u paketomatu {1}.\nPIN za preuzimanje: {2}\nNa paketomatu odaberi "Preuzmi paket" i upiši PIN.',
      [d.deviceName, d.destination ?? '', BoxNowDemo.pickupPin(d)],
    ),
  );

  /// Uvodna poruka — razgovor postoji i prije prve pošiljke.
  static ChatMessage welcome(String userId, DateTime at) => ChatMessage(
    id: 'sys-welcome-$userId',
    senderId: ChatService.systemId,
    receiverId: userId,
    createdAt: at,
    read: true,
    text: t(
      '👋 Ovdje ti Subhasto šalje PIN-ove za paketomate i upute za slanje. Na ove poruke ne možeš odgovoriti.',
    ),
  );

  /// Sve službene poruke za [userId] iz pošiljki (najstarije prvo).
  /// Izračunate poruke su pročitane — o događaju već stiže obavijest.
  static List<ChatMessage> derive(
    String userId,
    DateTime joined,
    Iterable<Delivery> deliveries,
    String Function(String userId) labelOf,
    DateTime now,
  ) {
    final out = <ChatMessage>[welcome(userId, joined)];
    for (final d in deliveries) {
      final m = d.method;
      if (m == null || m == DeliveryMethod.digital || d.startedAt == null) {
        continue;
      }
      if (d.sellerId == userId) {
        out.add(ship(d, labelOf(d.buyerId)).markRead());
      }
      if (d.buyerId == userId &&
          d.autoConfirms &&
          d.stepIndex(now) >= d.steps.indexOf(DeliveryStatus.inLocker)) {
        out.add(pickup(d).markRead());
      }
    }
    return out;
  }
}
