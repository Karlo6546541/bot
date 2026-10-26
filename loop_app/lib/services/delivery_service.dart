import 'dart:math';

import 'package:uuid/uuid.dart';

import '../models/delivery.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../models/app_notification.dart';
import 'boxnow/boxnow.dart';
import 'boxnow/boxnow_demo.dart';
import 'inbox.dart';
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
      // Kurir na spremljenu adresu je zadan (kao na Whatnotu).
      : const [
          DeliveryMethod.courier,
          DeliveryMethod.parcelLocker,
          DeliveryMethod.express,
          DeliveryMethod.pickup,
        ];

  /// Provjera odredišta prije plaćanja.
  static String? validate(DeliveryMethod m, String? destination) {
    final dest = destination?.trim() ?? '';
    if (m.needsAddress && dest.length < 8) {
      return t('Upiši adresu za dostavu (ulica, broj, mjesto).');
    }
    if (m.needsLocker &&
        !kDemoLockers.contains(dest) &&
        BoxNowLocker.parse(dest) == null) {
      return t('Odaberi paketomat.');
    }
    return null;
  }

  /// "SUBH-7KQ2M9XA"
  String _trackingNumber() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return 'SUBH-${List.generate(8, (_) => chars[_random.nextInt(chars.length)]).join()}';
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

  /// Pošiljka koja odmah kreće na spremljenu adresu (osvojeno u liveu,
  /// kao na Whatnotu). [free] — spojeno u paket s ranijim predmetom iz
  /// istog livea, pa se dostava ne plaća ponovno.
  Future<Delivery> createStarted({
    required String id,
    required String userId,
    required String deviceId,
    required String deviceName,
    required DeliveryMethod method,
    required String destination,
    String? sellerId,
    bool free = false,
    DateTime? now,
  }) async {
    final d = Delivery(
      id: id,
      deviceId: deviceId,
      deviceName: deviceName,
      buyerId: userId,
      createdAt: now ?? DateTime.now(),
      fromAuction: true,
      sellerId: sellerId,
    );
    return _start(d, userId, method, destination, now: now, free: free);
  }

  /// Predmeti osvojeni u istom liveu (isti paket): pošiljke `live-<id>-<n>`.
  static String? liveParcel(String deliveryId) {
    final m = RegExp(r'^(live-.+)-\d+$').firstMatch(deliveryId);
    return m?.group(1);
  }

  /// Pobjednik aukcije ili livea bira način dostave. Za predmete iz istog
  /// livea odabir vrijedi za cijeli paket: plaća se jednom, ostali idu
  /// besplatno s njim.
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
    final parcel = liveParcel(d.id);
    if (parcel == null) {
      return _start(d, userId, method, destination, now: now);
    }
    final same = [
      for (final x in _storage.deliveries)
        if (x.buyerId == userId && liveParcel(x.id) == parcel) x,
    ];
    // Već plaćena dostava za ovaj live → i ovaj predmet ide besplatno.
    var paid = same.any((x) => x.method != null && x.cost > 0);
    Delivery? first;
    for (final x in [d, ...same.where((x) => x.id != d.id)]) {
      if (!x.awaitingChoice) continue;
      final started = await _start(
        x,
        userId,
        method,
        destination,
        now: now,
        free: paid,
      );
      paid = paid || started.cost > 0;
      first ??= started;
    }
    return first!;
  }

  Future<Delivery> _start(
    Delivery d,
    String userId,
    DeliveryMethod method,
    String? destination, {
    DateTime? now,
    bool free = false,
  }) async {
    final at = now ?? DateTime.now();
    final error = validate(method, destination);
    if (error != null) throw TradeException(error);
    final user = _storage.userById(userId);
    if (user == null) throw TradeException(t('Korisnik ne postoji.'));
    // Dostava se plaća karticom; zapamti adresu za sljedeći put.
    final dest = destination?.trim();
    await _storage.putUser(
      user.copyWith(
        address: method.needsAddress ? dest : null,
        // Zapamti odabir za sljedeću kupnju (osim digitalne dostave).
        lastDelivery: method == DeliveryMethod.digital
            ? null
            : '${method.name}|${dest ?? ''}',
      ),
    );
    final cost = free ? 0.0 : method.cost;
    final started = d.copyWith(
      method: method,
      destination: dest,
      cost: cost,
      trackingNumber: _trackingNumber(),
      startedAt: at,
    );
    await _storage.putDelivery(started);
    // Prodavač dobiva kod za paketomat / etiketu (ime i adresa kupca).
    if (d.sellerId != null && method != DeliveryMethod.digital) {
      await Inbox(_storage).send(
        d.sellerId,
        NotificationKind.shipReady,
        args: [user.handle, d.deviceName],
        targetId: d.id,
        now: at,
      );
    }
    if (cost > 0) {
      await _storage.putTransaction(
        LoopTransaction(
          id: _uuid.v4(),
          type: TransactionType.delivery,
          userId: userId,
          deviceId: d.deviceId,
          deviceName: '${d.deviceName} · ${method.label}',
          price: 0,
          fee: 0,
          amount: cost,
          buyerId: userId,
          buyerLabel: user.handle,
          sellerLabel: 'Subhasto dostava',
          createdAt: at,
        ),
      );
      await _storage.recordSnapshot(userId, now: at);
    }
    return started;
  }

  /// Paketomat javlja preuzimanje: pošiljke koje je kupac preuzeo sami se
  /// potvrđuju (bez gumba "Potvrdi primitak"), a prodavač dobiva obavijest.
  /// Vraća broj potvrđenih.
  Future<int> autoConfirmPickups(String userId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    var n = 0;
    // Paket stigao u paketomat → kupac dobiva PIN za preuzimanje (jednom).
    for (final d in _storage.deliveries) {
      if (!d.autoConfirms ||
          d.buyerId != userId ||
          d.confirmedAt != null ||
          d.status(at) != DeliveryStatus.inLocker) {
        continue;
      }
      final sent = _storage.notifications.any(
        (x) =>
            x.userId == userId &&
            x.kind == NotificationKind.parcelArrived &&
            x.targetId == d.id,
      );
      if (sent) continue;
      await Inbox(_storage).send(
        userId,
        NotificationKind.parcelArrived,
        args: [d.deviceName, d.destination ?? '', BoxNowDemo.pickupPin(d)],
        targetId: d.id,
        now: at,
      );
    }
    for (final d in _storage.deliveries) {
      if (!d.autoConfirms ||
          d.confirmedAt != null ||
          (d.buyerId != userId && d.sellerId != userId) ||
          !d.isDelivered(at)) {
        continue;
      }
      final picked = d.stepAt(d.steps.length - 1) ?? at;
      await _storage.putDelivery(d.copyWith(confirmedAt: picked));
      if (d.sellerId != null) {
        await Inbox(_storage).send(
          d.sellerId,
          NotificationKind.parcelPickedUp,
          args: [_storage.userById(d.buyerId)?.handle ?? '', d.deviceName],
          targetId: d.id,
          now: at,
        );
      }
      n++;
    }
    return n;
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
