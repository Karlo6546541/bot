import 'package:uuid/uuid.dart';

import '../models/app_user.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import 'fee.dart';
import 'storage_service.dart';

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
      throw const TradeException('Unesi ispravan e-mail.');
    }
    if (password.isEmpty) {
      throw const TradeException('Unesi lozinku.');
    }
    if (cleaned.toLowerCase() == adminEmail) {
      throw const TradeException('Za admin račun koristi "Admin prijava".');
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
  }) async {
    if (name.trim().isEmpty || model.trim().isEmpty) {
      throw const TradeException('Naziv i model su obavezni.');
    }
    if (price <= 0) {
      throw const TradeException('Cijena mora biti veća od 0.');
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
    );
    await _storage.putDevice(device);
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
      throw const TradeException('Ovaj uređaj nije u tvom portfoliju.');
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
      throw const TradeException('Ovaj uređaj je već tvoj.');
    }
    if (!device.isOnMarket) {
      throw const TradeException('Uređaj više nije dostupan.');
    }

    final fee = feeFor(device.price);
    final total = buyTotal(device.price);
    if (user.credits < total) {
      throw TradeException(
        'Nemaš dovoljno kredita. Potrebno: ${total.toStringAsFixed(2)}, '
        'imaš: ${user.credits.toStringAsFixed(2)}.',
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
      throw const TradeException('Iznos mora biti veći od 0.');
    }
    final user = _requireUser(userId);
    await _storage.putUser(
      user.copyWith(credits: roundCredits(user.credits + amount)),
    );
  }

  /// Briše korisnika; njegovi uređaji se vraćaju u Market.
  /// Transakcije ostaju radi povijesti.
  Future<void> deleteUser(String userId) async {
    for (final d in _storage.devices.where((d) => d.ownerId == userId)) {
      await _storage.putDevice(d.withOwner(null));
    }
    await _storage.deleteUser(userId);
  }

  Future<void> deleteDevice(String deviceId) => _storage.deleteDevice(deviceId);

  // -------------------------------------------------------------- pomoćno

  AppUser _requireUser(String id) {
    final user = _storage.userById(id);
    if (user == null) throw const TradeException('Korisnik ne postoji.');
    return user;
  }

  Device _requireDevice(String id) {
    final device = _storage.deviceById(id);
    if (device == null) throw const TradeException('Uređaj ne postoji.');
    return device;
  }
}
