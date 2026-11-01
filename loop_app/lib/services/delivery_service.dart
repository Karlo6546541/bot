import 'dart:math';

import 'package:uuid/uuid.dart';

import '../models/country.dart';
import '../models/delivery.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../models/app_notification.dart';
import 'boxnow/boxnow.dart';
import 'boxnow/boxnow_demo.dart';
import 'system_messages.dart';
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
  final _choices = <String, Future<Delivery>>{};

  /// Dostupni načini dostave za predmet.
  static List<DeliveryMethod> methodsFor(Device d) {
    if (d.section == ItemSection.activities) {
      return const [DeliveryMethod.digital];
    }
    final size = ParcelSize.fromName(d.parcelSize);
    // Kurir na spremljenu adresu je zadan (kao na Whatnotu). Paketomat
    // prima samo male i srednje pakete, ekspres ne vozi glomazno.
    return [
      DeliveryMethod.courier,
      if (size.index <= ParcelSize.medium.index) DeliveryMethod.parcelLocker,
      DeliveryMethod.europe,
      if (size != ParcelSize.bulky) DeliveryMethod.express,
      DeliveryMethod.pickup,
    ];
  }

  /// Način dostave za dostavljača.
  static DeliveryMethod methodOf(Carrier c) => c.international
      ? DeliveryMethod.europe
      : switch (c.kind) {
          CarrierKind.locker => DeliveryMethod.parcelLocker,
          CarrierKind.express => DeliveryMethod.express,
          CarrierKind.courier || CarrierKind.post => DeliveryMethod.courier,
        };

  /// Cijena dostavljača za veličinu paketa (međunarodno doplata dvostruka).
  static double carrierCost(Carrier c, ParcelSize size) =>
      c.cost + size.extra * (c.international ? 2 : 1);

  /// Ponuda dostave prema državi prodavača ([from]) i kupca ([to]):
  /// u istoj državi lokalni dostavljači (GLS, DPD, pošta, paketomat…),
  /// inače međunarodno (cijena prema udaljenosti) — plus osobno preuzimanje.
  static List<DeliveryOption> optionsFor(
    Device d, {
    required String from,
    required String to,
  }) {
    if (d.section == ItemSection.activities) {
      return const [DeliveryOption(DeliveryMethod.digital)];
    }
    final size = ParcelSize.fromName(d.parcelSize);
    final src = countryOf(from);
    final dst = countryOf(to);
    final carriers = src.code == dst.code
        ? src.carriers
        : internationalCarriers(src, dst);
    bool fits(Carrier c) => switch (c.kind) {
      CarrierKind.locker => size.index <= ParcelSize.medium.index,
      CarrierKind.express => size != ParcelSize.bulky,
      _ => true,
    };
    final list =
        [
          for (final c in carriers)
            if (fits(c)) DeliveryOption(methodOf(c), carrier: c, to: dst),
        ]..sort(
          (a, b) => carrierCost(
            a.carrier!,
            size,
          ).compareTo(carrierCost(b.carrier!, size)),
        );
    // Kurir prvi (kao na Whatnotu), zatim ostalo po cijeni.
    final courier = list.indexWhere(
      (o) => o.carrier!.kind == CarrierKind.courier,
    );
    if (courier > 0) list.insert(0, list.removeAt(courier));
    return [
      ...list,
      if (src.code == dst.code) const DeliveryOption(DeliveryMethod.pickup),
    ];
  }

  /// Cijena opcije za veličinu paketa.
  static double optionCost(DeliveryOption o, ParcelSize size) =>
      o.carrier != null
      ? carrierCost(o.carrier!, size)
      : costFor(o.method, size);

  /// Cijena dostave za način i veličinu paketa (u EU doplata dvostruka).
  static double costFor(DeliveryMethod m, ParcelSize size, {String? country}) {
    if (m.cost == 0) return 0;
    if (m == DeliveryMethod.europe) {
      // Zona države (bez odabrane države — najniža, "od").
      final zone = country == null ? 1 : kEuCountries[country] ?? 3;
      return euZoneCost(zone) + size.extra * 2;
    }
    return m.cost + size.extra;
  }

  /// Provjera odredišta prije plaćanja.
  static String? validate(
    DeliveryMethod m,
    String? destination, {
    Carrier? carrier,
  }) {
    final dest = destination?.trim() ?? '';
    // Paketomat bez karte (Foxpost, InPost…): upisano mjesto.
    final network = LockerNetwork.ofCarrier(carrier);
    if (m.needsLocker && carrier != null && network == null) {
      return dest.length < 3 ? t('Odaberi paketomat.') : null;
    }
    // BOX NOW / GLS / DPD: paketomat te mreže (s karte ili popisa).
    if (m.needsLocker &&
        network != null &&
        BoxNowLocker.parse(dest)?.network != network &&
        !(network == LockerNetwork.boxNow && kDemoLockers.contains(dest))) {
      return t('Odaberi paketomat.');
    }
    if (m == DeliveryMethod.europe && euCountryOf(dest) == null) {
      return t('Odaberi državu EU za dostavu.');
    }
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

  static final _secure = Random.secure();

  /// Šesteroznamenkasti PIN.
  static String _pin() => _secure.nextInt(1000000).toString().padLeft(6, '0');

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
    Carrier? carrier,
  }) async {
    final d = Delivery(
      id: _uuid.v4(),
      deviceId: device.id,
      deviceName: '${device.name} ${device.model}',
      buyerId: userId,
      createdAt: now ?? DateTime.now(),
      sellerId: sellerId,
    );
    return _start(d, userId, method, destination, now: now, carrier: carrier);
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

  /// Koliko predmeta stane u jedan paket (profil dostave); 0 = bez
  /// ograničenja.
  static int packageCapacity(Device? device) => device?.shipping?.maxItems ?? 0;

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
    Carrier? carrier,
  }) async {
    final key = '$userId/${liveParcel(deliveryId) ?? deliveryId}';
    final pending = _choices[key];
    if (pending != null) {
      await pending;
      final result = _storage.deliveryById(deliveryId);
      if (result != null &&
          result.buyerId == userId &&
          !result.awaitingChoice) {
        return result;
      }
    }
    final task = _choose(
      userId: userId,
      deliveryId: deliveryId,
      method: method,
      destination: destination,
      now: now,
      carrier: carrier,
    );
    _choices[key] = task;
    try {
      return await task;
    } finally {
      if (identical(_choices[key], task)) _choices.remove(key);
    }
  }

  /// Prodavač bira način dostave i šalje (kao na Whatnotu): kupac ništa
  /// ne bira, dobiva broj za praćenje (i PIN kad paket stigne u
  /// paketomat). Za predmete iz istog livea vrijedi za cijeli paket.
  Future<Delivery> ship({
    required String sellerId,
    required String deliveryId,
    required DeliveryMethod method,
    String? destination,
    DateTime? now,
    Carrier? carrier,
  }) async {
    final d = _storage.deliveryById(deliveryId);
    if (d == null || d.sellerId != sellerId) {
      throw TradeException(t('Pošiljka ne postoji.'));
    }
    if (!d.awaitingChoice) return d;
    return _choose(
      userId: d.buyerId,
      deliveryId: deliveryId,
      method: method,
      destination: destination,
      now: now,
      carrier: carrier,
      bySeller: true,
    );
  }

  Future<Delivery> _choose({
    required String userId,
    required String deliveryId,
    required DeliveryMethod method,
    String? destination,
    DateTime? now,
    Carrier? carrier,
    bool bySeller = false,
  }) async {
    final d = _storage.deliveryById(deliveryId);
    if (d == null || d.buyerId != userId) {
      throw TradeException(t('Pošiljka ne postoji.'));
    }
    if (!d.awaitingChoice) {
      return d;
    }
    final parcel = liveParcel(d.id);
    if (parcel == null) {
      return _start(
        d,
        userId,
        method,
        destination,
        now: now,
        carrier: carrier,
        bySeller: bySeller,
      );
    }
    final same = [
      for (final x in _storage.deliveries)
        if (x.buyerId == userId && liveParcel(x.id) == parcel) x,
    ];
    // Jedan paket za predmete iz istog livea: plaća se prvi, ostali idu
    // besplatno s njim — dok ne prijeđu "do N predmeta u paketu" iz profila
    // dostave; tada kreće novi paket (opet se plaća).
    var packed = same.where((x) => x.method != null).length;
    Delivery? first;
    for (final x in [d, ...same.where((x) => x.id != d.id)]) {
      if (!x.awaitingChoice) continue;
      final cap = packageCapacity(_storage.deviceById(x.deviceId));
      final free = packed > 0 && (cap == 0 || packed % cap != 0);
      final started = await _start(
        x,
        userId,
        method,
        destination,
        now: now,
        free: free,
        carrier: carrier,
        bySeller: bySeller,
      );
      packed++;
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
    Carrier? carrier,
    bool bySeller = false,
  }) async {
    final at = now ?? DateTime.now();
    final error = validate(method, destination, carrier: carrier);
    if (error != null) throw TradeException(error);
    final user = _storage.userById(userId);
    if (user == null) throw TradeException(t('Korisnik ne postoji.'));
    final dest = destination?.trim();
    // Dostava se plaća karticom; zapamti adresu za sljedeći put (samo kad
    // bira sam kupac — prodavač ne mijenja kupčeve postavke).
    if (!bySeller) {
      await _storage.putUser(
        user.copyWith(
          address: method.needsAddress ? dest : null,
          // Zapamti odabir za sljedeću kupnju (osim digitalne dostave).
          lastDelivery: method == DeliveryMethod.digital
              ? null
              : '${method.name}|${dest ?? ''}${carrier == null ? '' : '|${carrier.id}'}',
        ),
      );
    }
    final size = ParcelSize.fromName(
      _storage.deviceById(d.deviceId)?.parcelSize,
    );
    final cost = free
        ? 0.0
        : carrier != null
        ? carrierCost(carrier, size)
        : costFor(method, size, country: euCountryOf(destination));
    final started = d.copyWith(
      method: method,
      destination: dest,
      cost: cost,
      trackingNumber: _trackingNumber(),
      startedAt: at,
      // BOX NOW: nasumični PIN-ovi (sigurni generator), ne iz broja pošiljke.
      dropOffPin: method == DeliveryMethod.parcelLocker ? _pin() : null,
      pickupPin: method == DeliveryMethod.parcelLocker ? _pin() : null,
      carrier: carrier?.name,
    );
    await _storage.putDelivery(started);
    // Prodavač je poslao: kupac dobiva broj za praćenje (a PIN paketomata
    // kad paket stigne u pretinac).
    if (bySeller && method != DeliveryMethod.digital) {
      await Inbox(_storage).send(
        d.buyerId,
        NotificationKind.parcelShipped,
        args: [
          _storage.userById(d.sellerId ?? '')?.handle ?? '',
          d.deviceName,
          started.serviceLabel,
          started.trackingNumber ?? '',
        ],
        targetId: d.id,
        now: at,
      );
    }
    // Prodavač dobiva kod za paketomat / etiketu (ime i adresa kupca).
    if (d.sellerId != null && method != DeliveryMethod.digital) {
      if (!bySeller) {
        await Inbox(_storage).send(
          d.sellerId,
          NotificationKind.shipReady,
          args: [user.handle, d.deviceName],
          targetId: d.id,
          now: at,
        );
      }
      // Službena poruka od Subhasta s uputama (i PIN-om za BOX NOW).
      await _storage.putMessage(SystemMessages.ship(started, user.handle));
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

  /// Prodavač bilježi da je predao paket dostavljaču. Rok je
  /// [Delivery.handOverDeadline] od odabira dostave; mjeri se u zdravlju računa.
  Future<Delivery> markHandedOver(
    String sellerId,
    String deliveryId, {
    DateTime? now,
  }) async {
    final d = _storage.deliveryById(deliveryId);
    if (d == null || d.sellerId != sellerId) {
      throw TradeException(t('Pošiljka ne postoji.'));
    }
    if (d.method == null || d.method == DeliveryMethod.digital) {
      throw TradeException(t('Za ovu pošiljku nema predaje paketa.'));
    }
    if (d.handedOverAt != null) return d;
    final updated = d.copyWith(handedOverAt: now ?? DateTime.now());
    await _storage.putDelivery(updated);
    return updated;
  }

  /// Paket stigao u paketomat: kupac dobiva PIN za preuzimanje (jednom).
  /// Pošiljke potvrđene na drugom uređaju javljaju se prodavaču.
  /// Vraća broj novih obavijesti.
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
      await _storage.putMessage(SystemMessages.pickup(d, at: at));
      n++;
    }
    return n;
  }

  /// Kupac na paketomatu upisuje PIN i preuzima paket (potvrda primitka).
  Future<void> pickUp(
    String userId,
    String deliveryId,
    String pin, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final d = _storage.deliveryById(deliveryId);
    if (d == null || d.buyerId != userId || !d.autoConfirms) {
      throw TradeException(t('Pošiljka ne postoji.'));
    }
    if (d.confirmedAt != null) {
      throw TradeException(t('Paket je već preuzet.'));
    }
    if (d.status(at) != DeliveryStatus.inLocker) {
      throw TradeException(t('Paket još nije u paketomatu.'));
    }
    if (pin.trim() != BoxNowDemo.pickupPin(d)) {
      throw TradeException(t('Pogrešan PIN — pretinac se nije otvorio.'));
    }
    await _storage.putDelivery(d.copyWith(confirmedAt: at));
    if (d.sellerId != null) {
      await Inbox(_storage).send(
        d.sellerId,
        NotificationKind.parcelPickedUp,
        args: [_storage.userById(d.buyerId)?.handle ?? '', d.deviceName],
        targetId: d.id,
        now: at,
      );
    }
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

/// Jedan izbor dostave: način + (neobavezno) dostavljač i država odredišta.
class DeliveryOption {
  const DeliveryOption(this.method, {this.carrier, this.to});
  final DeliveryMethod method;
  final Carrier? carrier;

  /// Država kupca (za međunarodnu dostavu dodaje se na adresu).
  final Country? to;

  String get id => carrier?.id ?? method.name;
  String get label => carrier?.name ?? method.label;
  String get subtitle => carrier?.subtitle ?? method.subtitle;
}
