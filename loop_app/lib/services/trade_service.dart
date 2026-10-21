import 'package:uuid/uuid.dart';

import '../models/app_user.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../utils/formatters.dart';
import 'fee.dart';
import 'storage_service.dart';
import '../l10n/tr.dart';

/// Greška poslovne logike koja se prikazuje korisniku.
class TradeException implements Exception {
  const TradeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Sva poslovna pravila LOOP-a: prijava, dodavanje, prodaja, kupnja
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

  // ------------------------------------------------------------- prijava

  bool isAdminLogin(String email, String password) =>
      email.trim().toLowerCase() == adminEmail && password == adminPassword;

  /// Demo prijava: bilo koji e-mail + lozinka. Ako korisnik ne postoji,
  /// automatski se kreira s [welcomeCredits].
  Future<AppUser> login(String email, String password) async {
    final cleaned = email.trim();
    if (cleaned.isEmpty || !cleaned.contains('@')) {
      throw TradeException(t('Unesi ispravan e-mail.'));
    }
    if (password.isEmpty) {
      throw TradeException(t('Unesi lozinku.'));
    }
    if (cleaned.toLowerCase() == adminEmail) {
      throw TradeException(t('Za admin račun koristi "Admin prijava".'));
    }
    final existing = _storage.userByEmail(cleaned);
    if (existing != null) return existing;

    final user = AppUser(
      id: _uuid.v4(),
      email: cleaned.toLowerCase(),
      name: cleaned.split('@').first,
      credits: welcomeCredits.toDouble(),
      createdAt: DateTime.now(),
    );
    await _storage.putUser(user);
    await _snapshot(user.id);
    return user;
  }

  /// Gost je jedan zajednički lokalni račun.
  Future<AppUser> loginAsGuest() async {
    final existing = _storage.userByEmail(guestEmail);
    if (existing != null) return existing;
    final guest = AppUser(
      id: 'user-guest',
      email: guestEmail,
      name: 'Gost',
      credits: welcomeCredits.toDouble(),
      isGuest: true,
      createdAt: DateTime.now(),
    );
    await _storage.putUser(guest);
    await _snapshot(guest.id);
    return guest;
  }

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
  }) async {
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
    final device = Device(
      id: _uuid.v4(),
      name: name.trim(),
      model: model.trim(),
      condition: condition,
      price: roundCredits(price),
      category: category,
      ownerId: userId,
      createdAt: DateTime.now(),
      imagePaths: imagePaths,
      description: description.trim(),
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
      sellerLabel: user.email,
      buyerId: null,
      buyerLabel: marketLabel,
      createdAt: DateTime.now(),
    );
    await _storage.putTransaction(tx);
    await _snapshot(userId);
    return tx;
  }

  /// INSTANT BUY: provjera kredita, kupac plaća cijena + 5%,
  /// uređaj prelazi u njegov portfolio.
  Future<LoopTransaction> buy({
    required String userId,
    required String deviceId,
  }) async {
    final user = _requireUser(userId);
    final device = _requireDevice(deviceId);
    if (device.ownerId == userId) {
      throw TradeException(t('Ovaj predmet je već tvoj.'));
    }
    if (!device.isOnMarket) {
      throw TradeException(t('Predmet više nije dostupan.'));
    }

    final fee = feeFor(device.price);
    final total = buyTotal(device.price);
    if (user.credits < total) {
      throw TradeException(
        t('Nemaš dovoljno kredita. Potrebno: {0}, imaš: {1}.', [
          formatCredits(total),
          formatCredits(user.credits),
        ]),
      );
    }

    await _storage.putDevice(device.withOwner(userId));
    await _storage.putUser(
      user.copyWith(credits: roundCredits(user.credits - total)),
    );

    final tx = LoopTransaction(
      id: _uuid.v4(),
      type: TransactionType.buy,
      userId: userId,
      deviceId: device.id,
      deviceName: '${device.name} ${device.model}',
      price: device.price,
      fee: fee,
      amount: total,
      buyerId: userId,
      buyerLabel: user.email,
      sellerId: null,
      sellerLabel: marketLabel,
      createdAt: DateTime.now(),
    );
    await _storage.putTransaction(tx);
    await _snapshot(userId);
    return tx;
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
