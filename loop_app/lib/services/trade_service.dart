import 'package:uuid/uuid.dart';

import '../models/app_user.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../models/price_offer.dart';
import '../utils/formatters.dart';
import 'bargain_service.dart';
import 'seed_data.dart';
import 'fee.dart';
import 'live_service.dart';
import 'storage_service.dart';
import '../l10n/tr.dart';
import '../models/app_notification.dart';
import 'inbox.dart';

/// Greška poslovne logike koja se prikazuje korisniku.
class TradeException implements Exception {
  const TradeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Poslovna pravila LICIT-a: dodavanje, prodaja, kupnja
/// i admin akcije. Radi direktno nad [StorageService].
class TradeService {
  TradeService(this._storage);

  final StorageService _storage;
  final _uuid = const Uuid();

  static const adminEmail = 'admin@loop.com';
  static const adminPassword = 'admin123';
  static const guestEmail = 'gost@loop.com';

  /// Novi računi počinju s 0 € (nema poklona pri registraciji).
  static const welcomeCredits = 0;

  /// Oznaka platforme kao druge strane u transakciji.
  static const marketLabel = 'LICIT Market';

  bool isAdminLogin(String email, String password) =>
      email.trim().toLowerCase() == adminEmail && password == adminPassword;

  // ------------------------------------------------------------- uređaji

  Future<Device> addDevice({
    required String userId,
    required String name,
    required String model,
    required DeviceCondition condition,
    required double price,
    required DeviceCategory category,
    List<String> imagePaths = const [],
    String description = '',
    bool listOnMarket = true,
    String? id,
    DigitalFile? file,
    int quantity = 1,
  }) async {
    final digital = category.section == ItemSection.digital;
    if (quantity < 1 || quantity > Device.maxQuantity) {
      throw TradeException(
        t('Količina mora biti između 1 i {0}.', ['${Device.maxQuantity}']),
      );
    }
    if (digital && file == null) {
      throw TradeException(
        t('Digitalni proizvod treba datoteku koju kupac preuzima.'),
      );
    }
    if (name.trim().isEmpty || model.trim().isEmpty) {
      throw TradeException(t('Naziv i model su obavezni.'));
    }
    if (price <= 0) {
      throw TradeException(t('Cijena mora biti veća od 0.'));
    }
    if (description.trim().length > Device.maxDescription) {
      throw TradeException(t('Opis može imati najviše 500 znakova.'));
    }
    _requireUser(userId);
    // Digitalni proizvod je uvijek "nov" i uvijek u Marketu.
    final list = listOnMarket || digital;
    final device = Device(
      id: id ?? _uuid.v4(),
      name: name.trim(),
      model: model.trim(),
      condition: digital ? DeviceCondition.brandNew : condition,
      price: roundCredits(price),
      category: category,
      ownerId: userId,
      createdAt: DateTime.now(),
      imagePaths: imagePaths,
      description: description.trim(),
      // Novi predmet odmah ide u Market (po svojoj cijeni), osim ako
      // korisnik to isključi.
      listPrice: list ? roundCredits(price) : null,
      listedAt: list ? DateTime.now() : null,
      marketChecked: true,
      file: file,
      quantity: digital ? 1 : quantity,
    );
    await _storage.putDevice(device);
    await _snapshot(userId);
    if (list) await _announceListing(device);
    return device;
  }

  /// INSTANT SELL: LICIT otkupljuje predmet po punoj vrijednosti.
  Future<LoopTransaction> sell({
    required String userId,
    required String deviceId,
  }) async {
    final user = _requireUser(userId);
    final device = _requireDevice(deviceId);
    if (device.ownerId != userId) {
      throw TradeException(t('Ovaj predmet nije među tvojim predmetima.'));
    }
    if (device.isDigital) {
      throw TradeException(
        t(
          'Digitalni proizvod se ne prodaje LICIT-u — kupci ga kupuju u Marketu.',
        ),
      );
    }
    if (_storage.activeAuctionFor(deviceId) != null) {
      throw TradeException(
        t('Predmet je na aukciji i ne može se prodati dok aukcija traje.'),
      );
    }
    if (LiveService.isLocked(_storage, deviceId)) {
      throw TradeException(LiveService.lockedMessage);
    }

    // Otkup je bez provizije.
    const fee = 0.0;
    final payout = roundCredits(device.price);

    await _storage.putDevice(device.withOwner(null));
    await _storage.putUser(
      user.copyWith(credits: roundCredits(user.credits + payout)),
    );

    final tx = LoopTransaction(
      id: _uuid.v4(),
      type: TransactionType.sell,
      userId: userId,
      deviceId: device.id,
      deviceName: '${device.name} ${device.model}',
      price: device.price,
      fee: fee,
      amount: payout,
      sellerId: userId,
      sellerLabel: user.handle,
      buyerId: null,
      buyerLabel: marketLabel,
      createdAt: DateTime.now(),
    );
    await _storage.putTransaction(tx);
    await _snapshot(userId);
    return tx;
  }

  /// INSTANT BUY (Kupi odmah): kupac plaća cijenu (bez naknade),
  /// uređaj prelazi u njegov portfolio. Predmet je od platforme ili ga je
  /// drugi korisnik objavio (prodavatelj dobiva cijenu − 5 % provizije).
  Future<LoopTransaction> buy({
    required String userId,
    required String deviceId,
    DateTime? now,
  }) async {
    final user = _requireUser(userId);
    final device = _requireDevice(deviceId);
    if (device.ownerId == userId) {
      throw TradeException(t('Ovaj predmet je već tvoj.'));
    }
    if (device.isDigital && hasPurchased(userId, deviceId)) {
      throw TradeException(
        t('Ovo si već kupio — preuzmi datoteku u "Moje digitalne kupnje".'),
      );
    }
    if (!device.isForSale) {
      throw TradeException(t('Predmet više nije dostupan.'));
    }
    final seller = device.isListed ? _storage.userById(device.ownerId!) : null;
    if (device.isListed &&
        (seller == null ||
            seller.pendingDeletion ||
            seller.blockedIds.contains(userId))) {
      throw TradeException(t('Predmet više nije dostupan.'));
    }
    if (device.isListed && LiveService.isLocked(_storage, deviceId)) {
      throw TradeException(t('Predmet više nije dostupan.'));
    }

    final at = now ?? DateTime.now();
    // Dogovorena cijena (prihvaćena ponuda) ima prednost pred cijenom oglasa.
    final bargain = BargainService(_storage).usable(userId, deviceId, at);
    final price = bargain?.agreedPrice ?? device.priceAt(at);
    final fee = feeFor(price);
    final total = buyTotal(price);
    // Kupac plaća karticom preko pružatelja plaćanja (u demo verziji se
    // plaćanje simulira) — aplikacija ne drži novac kupaca.

    // Digitalni proizvod ostaje prodavatelju (prodaje se više puta), a
    // kupac dobiva pravo preuzimanja (zapis kupnje). Kod predmeta s više
    // komada na zalihi kupac dobiva jedan komad, a oglas ostaje.
    var boughtId = device.id;
    if (device.hasStock && device.isListed) {
      final unit = device.unitFor(userId, _uuid.v4(), at);
      boughtId = unit.id;
      await _storage.putDevice(unit);
      await _storage.putDevice(device.withQuantity(device.quantity - 1));
    } else if (!device.isDigital) {
      await _storage.putDevice(device.withOwner(userId));
    }
    if (bargain != null) await BargainService(_storage).markUsed(bargain, at);

    final tx = LoopTransaction(
      id: _uuid.v4(),
      type: TransactionType.buy,
      userId: userId,
      deviceId: boughtId,
      deviceName: '${device.name} ${device.model}',
      price: price,
      fee: fee,
      amount: total,
      buyerId: userId,
      buyerLabel: user.handle,
      sellerId: seller?.id,
      sellerLabel: seller?.handle ?? marketLabel,
      createdAt: at,
    );
    await _storage.putTransaction(tx);

    if (seller != null) {
      // Prodavatelj dobiva cijenu umanjenu za proviziju (5 %).
      final payout = sellPayout(price);
      await _storage.putUser(
        seller.copyWith(credits: roundCredits(seller.credits + payout)),
      );
      await _storage.putTransaction(
        LoopTransaction(
          id: _uuid.v4(),
          type: TransactionType.sell,
          userId: seller.id,
          deviceId: device.id,
          deviceName: '${device.name} ${device.model}',
          price: price,
          fee: buyNowCommission(price),
          amount: payout,
          sellerId: seller.id,
          sellerLabel: seller.handle,
          buyerId: userId,
          buyerLabel: user.handle,
          createdAt: at,
        ),
      );
      await _snapshot(seller.id);
      final inbox = Inbox(_storage);
      await inbox.send(
        seller.id,
        NotificationKind.itemSold,
        args: [device.name, user.handle, payout],
        targetId: device.id,
        now: at,
      );
      if (!device.isDigital && !device.hasStock) {
        // Zadnji komad: oglas je rasprodan; otvorene ponude više ne vrijede.
        for (final o in _storage.bargains) {
          if (o.deviceId == device.id && (o.isOpen || o.usableAt(at))) {
            await _storage.putBargain(
              o.copyWith(status: BargainStatus.expired, updatedAt: at),
            );
          }
        }
        if (device.quantity > 1 || _wasStocked(device)) {
          await inbox.send(
            seller.id,
            NotificationKind.soldOut,
            args: [device.name],
            targetId: boughtId,
            now: at,
          );
        }
      }
    }
    await _snapshot(userId);
    return tx;
  }

  // ------------------------------------------------------- objava u Marketu

  /// Najviša cijena objave (zaštita od tipfelera).
  static const maxListPrice = 100000.0;

  /// Objavljuje vlastiti predmet u Marketu po [price] (ili mijenja cijenu).
  Future<Device> list({
    required String userId,
    required String deviceId,
    required double price,
    int? quantity,
  }) async {
    final device = _requireOwn(userId, deviceId);
    if (_storage.activeAuctionFor(deviceId) != null) {
      throw TradeException(
        t('Predmet je na aukciji i ne može se prodati dok aukcija traje.'),
      );
    }
    if (LiveService.isLocked(_storage, deviceId)) {
      throw TradeException(LiveService.lockedMessage);
    }
    if (price <= 0 || price > maxListPrice) {
      throw TradeException(
        t('Cijena mora biti između 1 i {0}.', [formatCredits(maxListPrice)]),
      );
    }
    if (quantity != null &&
        (quantity < 1 || quantity > Device.maxQuantity || device.isDigital)) {
      throw TradeException(
        t('Količina mora biti između 1 i {0}.', ['${Device.maxQuantity}']),
      );
    }
    final listed = device.withListing(roundCredits(price), quantity: quantity);
    await _storage.putDevice(listed);
    if (!device.isListed) await _announceListing(listed);
    // Pojeftinjenje: javi onima kojima je predmet na listi želja.
    final before = device.isListed ? device.askPrice : null;
    if (before != null && listed.askPrice < before) {
      final inbox = Inbox(_storage);
      for (final u in _storage.users) {
        if (u.id != userId && u.favorites.contains(device.id)) {
          await inbox.send(
            u.id,
            NotificationKind.priceDrop,
            args: [device.name, listed.shownPrice],
            targetId: device.id,
          );
        }
      }
    }
    return listed;
  }

  /// Uklanja vlastiti predmet iz Marketa (ostaje u portfoliju).
  Future<Device> unlist({
    required String userId,
    required String deviceId,
  }) async {
    final device = _requireOwn(userId, deviceId);
    final unlisted = device.withListing(null);
    await _storage.putDevice(unlisted);
    return unlisted;
  }

  /// Vlasnik trajno briše svoj predmet. Vraća putanje fotografija.
  Future<List<String>> deleteOwn({
    required String userId,
    required String deviceId,
  }) async {
    final device = _requireOwn(userId, deviceId);
    if (_storage.activeAuctionFor(deviceId) != null) {
      throw TradeException(
        t(
          'Predmet je na aukciji — prvo otkaži aukciju (moguće dok nema ponuda).',
        ),
      );
    }
    if (LiveService.isLocked(_storage, deviceId)) {
      throw TradeException(LiveService.lockedMessage);
    }
    if (device.isDigital && buyersOf(deviceId).isNotEmpty) {
      throw TradeException(
        t(
          'Ovaj proizvod su već kupili ({0}) — ne može se obrisati jer ga kupci preuzimaju. Ukloni ga iz Marketa.',
          [buyersOf(deviceId).length],
        ),
      );
    }
    await _storage.deleteDevice(deviceId);
    await _snapshot(userId);
    return device.imagePaths;
  }

  /// Jednokratno: predmeti iz portfolija koji još nisu prošli automatsku
  /// objavu idu u Market po svojoj cijeni (osim onih na aukciji).
  /// Vraća broj objavljenih predmeta.
  Future<int> autoListPortfolios({DateTime? now}) async {
    final at = now ?? DateTime.now();
    var listed = 0;
    for (final d in _storage.devices) {
      if (d.ownerId == null || d.marketChecked) continue;
      final owner = _storage.userById(d.ownerId!);
      final skip =
          owner == null ||
          owner.isGuest ||
          owner.pendingDeletion ||
          _storage.activeAuctionFor(d.id) != null ||
          LiveService.isLocked(_storage, d.id, now: at);
      if (skip || d.isListed) {
        await _storage.putDevice(
          d.withListing(d.listPrice, at: d.listedAt ?? at),
        );
        continue;
      }
      await _storage.putDevice(d.withListing(d.price, at: at));
      listed++;
    }
    return listed;
  }

  // --------------------------------------------------------------- popusti

  /// Trajanja popusta koja se nude u aplikaciji (`null` = trajno).
  static const discountDurations = <Duration?>[
    Duration(days: 1),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 30),
    null,
  ];

  /// Popust [percent] % na vlastiti objavljeni predmet, trajno ili za
  /// [duration]. 0 uklanja popust. Pratitelji i oni kojima je predmet na
  /// listi želja dobiju obavijest.
  Future<Device> setDiscount({
    required String userId,
    required String deviceId,
    required int percent,
    Duration? duration,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final device = _requireOwn(userId, deviceId);
    if (!device.isListed) {
      throw TradeException(t('Popust se može dati samo na oglas u Marketu.'));
    }
    if (percent < 0 || percent > Device.maxDiscount) {
      throw TradeException(
        t('Popust mora biti između 1 i {0}%.', ['${Device.maxDiscount}']),
      );
    }
    final updated = device.withDiscount(
      percent,
      duration == null ? null : at.add(duration),
    );
    await _storage.putDevice(updated);
    final wasActive = device.discountActiveAt(at);
    if (percent > 0 && (!wasActive || percent > device.discountPercent)) {
      final seller = _storage.userById(userId)!;
      final inbox = Inbox(_storage);
      final args = <Object>[
        seller.handle,
        '$percent',
        device.name,
        buyTotal(updated.priceAt(at)),
      ];
      await inbox.toFollowers(
        userId,
        NotificationKind.followedDiscount,
        args: args,
        targetId: deviceId,
        now: at,
      );
      for (final u in _storage.users) {
        if (u.id != userId &&
            !u.following.contains(userId) &&
            u.favorites.contains(deviceId)) {
          await inbox.send(
            u.id,
            NotificationKind.followedDiscount,
            args: args,
            targetId: deviceId,
            now: at,
          );
        }
      }
    }
    return updated;
  }

  /// Javlja pratiteljima da je prodavatelj objavio novi oglas.
  Future<void> _announceListing(Device d) async {
    final owner = d.ownerId == null ? null : _storage.userById(d.ownerId!);
    if (owner == null) return;
    await Inbox(_storage).toFollowers(
      owner.id,
      NotificationKind.followedNewItem,
      args: [owner.handle, d.name, d.shownPrice],
      targetId: d.id,
    );
  }

  /// Je li predmet prodavan u više komada (prije zadnjeg su prodani i
  /// drugi komadi istog oglasa).
  bool _wasStocked(Device d) =>
      _storage.transactions
          .where(
            (t) =>
                t.type == TransactionType.sell &&
                t.deviceId == d.id &&
                t.userId == d.ownerId,
          )
          .length >
      1;

  /// Cijena koju bi kupac [userId] sada platio (dogovorena ili oglasa).
  double priceFor(String userId, Device d, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return BargainService(_storage).usable(userId, d.id, at)?.agreedPrice ??
        d.priceAt(at);
  }

  /// Demo prodavatelji koji preuzimaju predmete bivšeg "LICIT Marketa".
  static const platformHeirs = [
    SeedData.anaUserId,
    SeedData.markoUserId,
    SeedData.testUserId,
  ];

  /// U aplikaciji postoje samo kupci i prodavatelji: predmeti bez vlasnika
  /// (stari LICIT Market) dodijele se demo prodavateljima i objave po svojoj
  /// cijeni. Raspodjela ovisi samo o ID-u predmeta, pa svi uređaji dođu do
  /// istog rezultata. Vraća broj dodijeljenih predmeta.
  Future<int> assignPlatformItems({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final heirs = [
      for (final id in platformHeirs)
        if (_storage.userById(id) case final u? when !u.pendingDeletion) u.id,
    ];
    if (heirs.isEmpty) return 0;
    var n = 0;
    for (final d in _storage.devices) {
      if (d.ownerId != null) continue;
      final owner =
          heirs[d.id.codeUnits.fold(0, (a, b) => a + b) % heirs.length];
      await _storage.putDevice(
        d.withOwner(owner).withListing(d.price, at: d.listedAt ?? at),
      );
      n++;
    }
    return n;
  }

  // ---------------------------------------------------- digitalni proizvodi

  /// Je li korisnik kupio digitalni proizvod (pravo preuzimanja).
  bool hasPurchased(String userId, String deviceId) =>
      _storage.transactions.any(
        (t) =>
            t.type == TransactionType.buy &&
            t.buyerId == userId &&
            t.deviceId == deviceId,
      );

  /// Kupci digitalnog proizvoda.
  Set<String> buyersOf(String deviceId) => {
    for (final t in _storage.transactions)
      if (t.type == TransactionType.buy &&
          t.deviceId == deviceId &&
          t.buyerId != null)
        t.buyerId!,
  };

  /// Smije li korisnik preuzeti datoteku: vlasnik ili kupac.
  bool canDownload(String userId, String deviceId) {
    final d = _storage.deviceById(deviceId);
    if (d == null || d.file == null) return false;
    return d.ownerId == userId || hasPurchased(userId, deviceId);
  }

  /// Vlasnik mijenja datoteku (npr. nova verzija modela). Vraća staru.
  Future<DigitalFile?> replaceFile(
    String userId,
    String deviceId,
    DigitalFile file,
  ) async {
    final d = _requireOwn(userId, deviceId);
    if (!d.isDigital) throw TradeException(t('Predmet nije digitalni.'));
    await _storage.putDevice(d.withFile(file));
    return d.file;
  }

  Device _requireOwn(String userId, String deviceId) {
    _requireUser(userId);
    final device = _requireDevice(deviceId);
    if (device.ownerId != userId) {
      throw TradeException(t('Ovaj predmet nije među tvojim predmetima.'));
    }
    return device;
  }

  /// Dodaje ili uklanja uređaj s liste želja. Vraća `true` ako je dodan.
  Future<bool> toggleFavorite(String userId, String deviceId) async {
    final user = _requireUser(userId);
    final favs = [...user.favorites];
    final added = !favs.remove(deviceId);
    if (added) favs.add(deviceId);
    await _storage.putUser(user.copyWith(favorites: favs));
    return added;
  }

  // -------------------------------------------------------------- isplata

  /// Isplata cijele zarade na IBAN iz podataka prodavatelja. U pravoj
  /// verziji isplatu radi pružatelj plaćanja (npr. Mangopay/Stripe).
  Future<LoopTransaction> payout({
    required String userId,
    DateTime? now,
  }) async {
    final user = _requireUser(userId);
    final seller = user.seller;
    if (seller == null) {
      throw TradeException(t('Za isplatu ispuni podatke prodavatelja (IBAN).'));
    }
    final amount = roundCredits(user.credits);
    if (amount <= 0) throw TradeException(t('Nemaš zarade za isplatu.'));
    final at = now ?? DateTime.now();
    await _storage.putUser(user.copyWith(credits: 0));
    final tx = LoopTransaction(
      id: _uuid.v4(),
      type: TransactionType.payout,
      userId: userId,
      deviceId: '',
      deviceName: t('Isplata na {0}', [seller.maskedIban]),
      price: amount,
      fee: 0,
      amount: amount,
      buyerLabel: '',
      sellerLabel: user.handle,
      createdAt: at,
    );
    await _storage.putTransaction(tx);
    await _snapshot(userId);
    return tx;
  }

  // ---------------------------------------------------------------- admin

  Future<void> addCredits(String userId, double amount) async {
    if (amount <= 0) {
      throw TradeException(t('Iznos mora biti veći od 0.'));
    }
    final user = _requireUser(userId);
    await _storage.putUser(
      user.copyWith(credits: roundCredits(user.credits + amount)),
    );
    await _snapshot(userId);
  }

  /// Briše korisnika; njegovi uređaji se vraćaju u Market.
  /// Transakcije ostaju radi povijesti.
  Future<void> deleteUser(String userId) async {
    for (final d in _storage.devices.where((d) => d.ownerId == userId)) {
      await _storage.putDevice(d.withOwner(null));
    }
    await _storage.deleteUser(userId);
    await _storage.deleteHistory(userId);
  }

  /// Briše predmet i vraća putanje njegovih fotografija (za brisanje datoteka).
  Future<List<String>> deleteDevice(String deviceId) async {
    final device = _storage.deviceById(deviceId);
    await _storage.deleteDevice(deviceId);
    final owner = device?.ownerId;
    if (owner != null && _storage.userById(owner) != null) {
      await _snapshot(owner);
    }
    return device?.imagePaths ?? const [];
  }

  // ------------------------------------------------------------- fotografije

  /// Postavlja fotografije predmeta. Smije samo vlasnik.
  Future<void> setImages(
    String userId,
    String deviceId,
    List<String> paths,
  ) async {
    final device = _requireDevice(deviceId);
    if (device.ownerId != userId) {
      throw TradeException(t('Fotografije može mijenjati samo vlasnik.'));
    }
    await _storage.putDevice(device.withImages(paths));
  }

  // ---------------------------------------------------------------- povijest

  Future<void> _snapshot(String userId) => _storage.recordSnapshot(userId);

  /// Korisnici iz starije verzije nemaju povijest — kreira prvu točku.
  Future<void> ensureHistory(String userId) async {
    if (_storage.historyOf(userId).isEmpty) await _snapshot(userId);
  }

  // -------------------------------------------------------------- pomoćno

  AppUser _requireUser(String id) {
    final user = _storage.userById(id);
    if (user == null) throw TradeException(t('Korisnik ne postoji.'));
    return user;
  }

  Device _requireDevice(String id) {
    final device = _storage.deviceById(id);
    if (device == null) throw TradeException(t('Predmet ne postoji.'));
    return device;
  }
}
