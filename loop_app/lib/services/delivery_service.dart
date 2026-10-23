import 'dart:math';

import 'package:uuid/uuid.dart';

import '../models/delivery.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import 'storage_service.dart';
import 'trade_service.dart';
import '../l10n/tr.dart';

/// Dostava kupljenih predmeta (simulirana).
///
/// - Kupnja u Marketu: način dostave bira se prije plaćanja, a cijena
///   dostave se plaća zajedno s predmetom.
/// - Osvojena aukcija: pošiljka čeka da pobjednik odabere način dostave.
/// - Aktivnosti (ulaznice, radionice…) imaju samo digitalnu dostavu.
/// - Status se računa iz vremena (vidi [Delivery.progress]).
class DeliveryService {
  DeliveryService(this._storage);

  final StorageService _storage;
  final _uuid = const Uuid();
  final _random = Random();

  /// Dostupni načini dostave za predmet.
  static List<DeliveryMethod> methodsFor(Device d) =>
      d.section == ItemSection.activities
      ? const [DeliveryMethod.digital]
      : const [
          DeliveryMethod.pickup,
          DeliveryMethod.parcelLocker,
          DeliveryMethod.courier,
          DeliveryMethod.express,
        ];

  /// Provjera odredišta prije plaćanja.
  static String? validate(DeliveryMethod m, String? destination) {
    final dest = destination?.trim() ?? '';
    if (m.needsAddress && dest.length < 8) {
      return t('Upiši adresu za dostavu (ulica, broj, mjesto).');
    }
    if (m.needsLocker && !kDemoLockers.contains(dest)) {
      return t('Odaberi paketomat.');
    }
    return null;
  }

  /// "LOOP-7KQ2M9XA"
  String _trackingNumber() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return 'LOOP-${List.generate(8, (_) => chars[_random.nextInt(chars.length)]).join()}';
  }

  /// Pošiljka za kupnju u Marketu. Poziva se NAKON uspješne kupnje
  /// (dostupnost kredita za dostavu provjerava se prije kupnje).
  Future<Delivery> createForPurchase({
    required String userId,
    required Device device,
    required DeliveryMethod method,
    String? destination,
    String? sellerId,
    DateTime? now,
  }) async {
    final d = Delivery(
      id: _uuid.v4(),
      deviceId: device.id,
      deviceName: '${device.name} ${device.model}',
      buyerId: userId,
      createdAt: now ?? DateTime.now(),
      sellerId: sellerId,
    );
    return _start(d, userId, method, destination, now: now);
  }

  /// Pošiljka koja čeka odabir (osvojena aukcija).
  Future<Delivery> createPending({
    String? id,
    required String userId,
    required String deviceId,
    required String deviceName,
    String? sellerId,
    bool fromAuction = true,
    DateTime? now,
  }) async {
    final d = Delivery(
      id: id ?? _uuid.v4(),
      deviceId: deviceId,
      deviceName: deviceName,
      buyerId: userId,
      createdAt: now ?? DateTime.now(),
      fromAuction: fromAuction,
      sellerId: sellerId,
    );
    await _storage.putDelivery(d);
    return d;
  }

  /// Pobjednik aukcije bira način dostave.
  Future<Delivery> choose({
    required String userId,
    required String deliveryId,
    required DeliveryMethod method,
    String? destination,
    DateTime? now,
  }) async {
    final d = _storage.deliveryById(deliveryId);
    if (d == null || d.buyerId != userId) {
      throw TradeException(t('Pošiljka ne postoji.'));
    }
    if (!d.awaitingChoice) {
      throw TradeException(t('Dostava je već odabrana.'));
    }
    return _start(d, userId, method, destination, now: now);
  }

  Future<Delivery> _start(
    Delivery d,
    String userId,
    DeliveryMethod method,
    String? destination, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final error = validate(method, destination);
    if (error != null) throw TradeException(error);
    final user = _storage.userById(userId);
    if (user == null) throw TradeException(t('Korisnik ne postoji.'));
    // Dostava se plaća karticom; zapamti adresu za sljedeći put.
    final dest = destination?.trim();
    await _storage.putUser(
      user.copyWith(address: method.needsAddress ? dest : null),
    );
    final started = d.copyWith(
      method: method,
      destination: dest,
      cost: method.cost,
      trackingNumber: _trackingNumber(),
      startedAt: at,
    );
    await _storage.putDelivery(started);
    if (method.cost > 0) {
      await _storage.putTransaction(
        LoopTransaction(
          id: _uuid.v4(),
          type: TransactionType.delivery,
          userId: userId,
          deviceId: d.deviceId,
          deviceName: '${d.deviceName} · ${method.label}',
          price: 0,
          fee: 0,
          amount: method.cost,
          buyerId: userId,
          buyerLabel: user.handle,
          sellerLabel: 'LOOP dostava',
          createdAt: at,
        ),
      );
      await _storage.recordSnapshot(userId, now: at);
    }
    return started;
  }

  /// Kupac potvrđuje primitak (moguće tek kad je pošiljka isporučena).
  Future<void> confirmReceipt(
    String userId,
    String deliveryId, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final d = _storage.deliveryById(deliveryId);
    if (d == null || d.buyerId != userId) {
      throw TradeException(t('Pošiljka ne postoji.'));
    }
    if (!d.isDelivered(at)) {
      throw TradeException(t('Pošiljka još nije stigla.'));
    }
    await _storage.putDelivery(d.copyWith(confirmedAt: at));
  }
}
