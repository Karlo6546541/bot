import 'package:uuid/uuid.dart';

import '../models/app_user.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../utils/formatters.dart';
import 'fee.dart';
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

/// Poslovna pravila LOOP-a: dodavanje, prodaja, kupnja
/// i admin akcije. Radi direktno nad [StorageService].
class TradeService {
  TradeService(this._storage);

  final StorageService _storage;
  final _uuid = const Uuid();

  static const adminEmail = 'admin@loop.com';
  static const adminPassword = 'admin123';
  static const guestEmail = 'gost@loop.com';

  /// Početni krediti za novog korisnika (demo pogodnost).
  static const welcomeCredits = 500;

  /// Oznaka platforme kao druge strane u transakciji.
  static const marketLabel = 'LOOP Market';

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
  }) async {
    final digital = category.section == ItemSection.digital;
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
    );
    await _storage.putDevice(device);
    await _snapshot(userId);
    return device;
  }

  /// INSTANT SELL: uređaj ide u Market, korisnik dobiva cijena − 5% kredita.
  Future<LoopTransaction> sell({
    required String userId,
    required String deviceId,
  }) async {
    final user = _requireUser(userId);
    final device = _requireDevice(deviceId);
    if (device.ownerId != userId) {
      throw TradeException(t('Ovaj predmet nije u tvom portfoliju.'));
    }
    if (device.isDigital) {
      throw TradeException(
        t(
          'Digitalni proizvod se ne prodaje LOOP-u — kupci ga kupuju u Marketu.',
        ),
      );
    }
    if (_storage.activeAuctionFor(deviceId) != null) {
      throw TradeException(
        t('Predmet je na aukciji i ne može se prodati dok aukcija traje.'),
      );
    }

    final fee = feeFor(device.price);
    final payout = sellPayout(device.price);

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

  /// INSTANT BUY: provjera kredita, kupac plaća cijena + 5%,
  /// uređaj prelazi u njegov portfolio. Predmet je od platforme ili ga je
  /// drugi korisnik objavio u Marketu (tada prodavatelj dobiva cijena − 5%).
  Future<LoopTransaction> buy({
    required String userId,
    required String deviceId,
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

    final price = device.askPrice;
    final fee = feeFor(price);
    final total = buyTotal(price);
    if (user.credits < total) {
      throw TradeException(
        t('Nemaš dovoljno kredita. Potrebno: {0}, imaš: {1}.', [
          formatCredits(total),
          formatCredits(user.credits),
        ]),
      );
    }

    final now = DateTime.now();
    // Digitalni proizvod ostaje prodavatelju (prodaje se više puta), a
    // kupac dobiva pravo preuzimanja (zapis kupnje).
    if (!device.isDigital) {
      await _storage.putDevice(device.withOwner(userId));
    }
    await _storage.putUser(
      user.copyWith(credits: roundCredits(user.credits - total)),
    );

    final tx = LoopTransaction(
      id: _uuid.v4(),
      type: TransactionType.buy,
      userId: userId,
      deviceId: device.id,
      deviceName: '${device.name} ${device.model}',
      price: price,
      fee: fee,
      amount: total,
      buyerId: userId,
      buyerLabel: user.handle,
      sellerId: seller?.id,
      sellerLabel: seller?.handle ?? marketLabel,
      createdAt: now,
    );
    await _storage.putTransaction(tx);

    if (seller != null) {
      // Prodavatelj dobiva cijenu − 5% i vlastiti zapis u Aktivnosti.
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
          fee: fee,
          amount: payout,
          sellerId: seller.id,
          sellerLabel: seller.handle,
          buyerId: userId,
          buyerLabel: user.handle,
          createdAt: now,
        ),
      );
      await _snapshot(seller.id);
      await Inbox(_storage).send(
        seller.id,
        NotificationKind.itemSold,
        args: [device.name, user.handle, payout],
        targetId: device.id,
        now: now,
      );
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
  }) async {
    final device = _requireOwn(userId, deviceId);
    if (_storage.activeAuctionFor(deviceId) != null) {
      throw TradeException(
        t('Predmet je na aukciji i ne može se prodati dok aukcija traje.'),
      );
    }
    if (price <= 0 || price > maxListPrice) {
      throw TradeException(
        t('Cijena mora biti između 1 i {0}.', [formatCredits(maxListPrice)]),
      );
    }
    final listed = device.withListing(roundCredits(price));
    await _storage.putDevice(listed);
    // Pojeftinjenje: javi onima kojima je predmet na listi želja.
    final before = device.isListed ? device.askPrice : null;
    if (before != null && listed.askPrice < before) {
      final inbox = Inbox(_storage);
      for (final u in _storage.users) {
        if (u.id != userId && u.favorites.contains(device.id)) {
          await inbox.send(
            u.id,
            NotificationKind.priceDrop,
            args: [device.name, listed.askPrice],
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
          _storage.activeAuctionFor(d.id) != null;
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
      throw TradeException(t('Ovaj predmet nije u tvom portfoliju.'));
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
