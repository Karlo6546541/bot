import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/app_user.dart';
import '../models/auction.dart';
import '../models/delivery.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../models/portfolio_point.dart';
import 'seed_data.dart';

/// Lokalna pohrana na Hive-u. Svaki entitet je spremljen kao obična mapa
/// (ključ = ID), pa nisu potrebni generirani TypeAdapteri.
class StorageService {
  static const _usersBox = 'users';
  static const _devicesBox = 'devices';
  static const _transactionsBox = 'transactions';
  static const _sessionBox = 'session';
  static const _historyBox = 'history';
  static const _auctionsBox = 'auctions';
  static const _deliveriesBox = 'deliveries';

  /// Tablice koje se sinkroniziraju s online bazom (sesija ostaje lokalna).
  static const syncedTables = [
    _usersBox,
    _devicesBox,
    _transactionsBox,
    _historyBox,
    _auctionsBox,
    _deliveriesBox,
  ];

  /// Povećaj kad se seed proširi — postojeće instalacije tada dobiju
  /// nove demo predmete bez resetiranja (vidi [_migrateSeed]).
  static const _seedVersion = 4;
  static const _seedVersionKey = 'seedVersion';

  /// Najviše točaka povijesti po korisniku.
  static const _maxHistory = 500;

  static const _seededKey = 'seeded';
  static const _currentUserKey = 'currentUserId';
  static const _isAdminKey = 'isAdmin';
  static const _themeKey = 'themeMode';
  static const _langKey = 'lang';
  static const _howItWorksKey = 'howItWorksDismissed';

  late Box<Map> _users;
  late Box<Map> _devices;
  late Box<Map> _transactions;
  late Box _session;
  late Box<Map> _history;
  late Box<Map> _auctions;
  late Box<Map> _deliveries;

  /// Poziva se nakon svake lokalne promjene (za sinkronizaciju s online
  /// bazom). `data == null` znači brisanje.
  void Function(String table, String id, Map<String, dynamic>? data)?
  onLocalChange;

  Map<String, Box<Map>> get _tables => {
    _usersBox: _users,
    _devicesBox: _devices,
    _transactionsBox: _transactions,
    _historyBox: _history,
    _auctionsBox: _auctions,
    _deliveriesBox: _deliveries,
  };

  /// Svi zapisi prolaze ovuda kako bi ih sinkronizacija vidjela.
  Future<void> _write(
    String table,
    String id,
    Map<String, dynamic> data,
  ) async {
    await _tables[table]!.put(id, data);
    onLocalChange?.call(table, id, data);
  }

  Future<void> _remove(String table, String id) async {
    await _tables[table]!.delete(id);
    onLocalChange?.call(table, id, null);
  }

  /// Otvara boxove i puni demo podatke pri prvom pokretanju.
  /// [path] i [inMemory] koriste se u testovima; u aplikaciji Hive sam
  /// bira direktorij.
  Future<void> init({String? path, bool inMemory = false}) async {
    if (path != null) {
      Hive.init(path);
    } else if (!inMemory) {
      await Hive.initFlutter('loop');
    }
    // `bytes` otvara box samo u memoriji, bez pisanja na disk.
    final bytes = inMemory ? Uint8List(0) : null;
    _users = await Hive.openBox<Map>(_usersBox, bytes: bytes);
    _devices = await Hive.openBox<Map>(_devicesBox, bytes: bytes);
    _transactions = await Hive.openBox<Map>(_transactionsBox, bytes: bytes);
    _session = await Hive.openBox(_sessionBox, bytes: bytes);
    _history = await Hive.openBox<Map>(_historyBox, bytes: bytes);
    _auctions = await Hive.openBox<Map>(_auctionsBox, bytes: bytes);
    _deliveries = await Hive.openBox<Map>(_deliveriesBox, bytes: bytes);

    if (_session.get(_seededKey) != true) {
      await _seed();
    } else if ((_session.get(_seedVersionKey) as int? ?? 1) < _seedVersion) {
      await _migrateSeed();
    }
  }

  /// Dodaje demo predmete koji su nastali u novijim verzijama seeda.
  Future<void> _migrateSeed() async {
    final now = DateTime.now();
    // Novi demo korisnici (npr. prodavatelji na aukcijama).
    final newUsers = <String>{};
    for (final u in SeedData.users(now)) {
      if (!_users.containsKey(u.id)) {
        await _write(_usersBox, u.id, u.toMap());
        newUsers.add(u.id);
      }
    }
    for (final d in SeedData.devices(now)) {
      final owner = d.ownerId;
      // Predmeti iz Marketa, ili predmeti upravo dodanih demo korisnika.
      if (!_devices.containsKey(d.id) &&
          (owner == null || newUsers.contains(owner))) {
        await _write(_devicesBox, d.id, d.toMap());
      }
    }
    // Aukcije samo ako su i prodavatelj i predmet upravo dodani —
    // inače bi blokirani krediti ponuđača bili neusklađeni.
    for (final a in SeedData.auctions(now)) {
      if (!_auctions.containsKey(a.id) && newUsers.contains(a.sellerId)) {
        await _write(_auctionsBox, a.id, a.toMap());
      }
    }
    // Korisnici iz starije verzije dobivaju prvu točku povijesti.
    for (final u in users) {
      if (historyOf(u.id).isEmpty) await recordSnapshot(u.id, now: now);
    }
    await _session.put(_seedVersionKey, _seedVersion);
  }

  Future<void> _seed() async {
    final now = DateTime.now();
    for (final u in SeedData.users(now)) {
      await _write(_usersBox, u.id, u.toMap());
    }
    for (final d in SeedData.devices(now)) {
      await _write(_devicesBox, d.id, d.toMap());
    }
    for (final a in SeedData.auctions(now)) {
      await _write(_auctionsBox, a.id, a.toMap());
    }
    for (final entry in SeedData.history(now).entries) {
      await _write(_historyBox, entry.key, {
        'points': [for (final p in entry.value) p.toMap()],
      });
    }
    await _session.put(_seededKey, true);
    await _session.put(_seedVersionKey, _seedVersion);
  }

  /// Briše sve podatke (uključujući sesiju) i ponovno kreira demo podatke.
  Future<void> resetAll() async {
    await _users.clear();
    await _devices.clear();
    await _transactions.clear();
    // Tema i jezik su postavke uređaja, ne demo podaci — čuvamo ih.
    final theme = _session.get(_themeKey);
    final lang = _session.get(_langKey);
    await _session.clear();
    if (theme != null) await _session.put(_themeKey, theme);
    if (lang != null) await _session.put(_langKey, lang);
    await _history.clear();
    await _auctions.clear();
    await _deliveries.clear();
    await _seed();
  }

  // ---------------------------------------------------------------- čitanje

  List<AppUser> get users =>
      _users.values.map(AppUser.fromMap).toList(growable: false);

  List<Device> get devices =>
      _devices.values.map(Device.fromMap).toList(growable: false);

  List<LoopTransaction> get transactions =>
      _transactions.values.map(LoopTransaction.fromMap).toList(growable: false);

  AppUser? userById(String id) {
    final map = _users.get(id);
    return map == null ? null : AppUser.fromMap(map);
  }

  Device? deviceById(String id) {
    final map = _devices.get(id);
    return map == null ? null : Device.fromMap(map);
  }

  AppUser? userByEmail(String email) {
    final needle = email.trim().toLowerCase();
    for (final u in users) {
      if (u.email.toLowerCase() == needle) return u;
    }
    return null;
  }

  // ---------------------------------------------------------------- pisanje

  Future<void> putUser(AppUser user) =>
      _write(_usersBox, user.id, user.toMap());

  Future<void> putDevice(Device device) =>
      _write(_devicesBox, device.id, device.toMap());

  Future<void> putTransaction(LoopTransaction tx) =>
      _write(_transactionsBox, tx.id, tx.toMap());

  Future<void> deleteUser(String id) => _remove(_usersBox, id);

  Future<void> deleteDevice(String id) => _remove(_devicesBox, id);

  // --------------------------------------------------------------- povijest

  List<PortfolioPoint> historyOf(String userId) {
    final raw = _history.get(userId)?['points'] as List?;
    if (raw == null) return const [];
    return [for (final m in raw) PortfolioPoint.fromMap(m as Map)];
  }

  /// Dodaje točku samo ako se vrijednost promijenila od zadnje.
  Future<void> appendHistory(String userId, PortfolioPoint point) async {
    final points = [...historyOf(userId)];
    if (points.isNotEmpty &&
        points.last.credits == point.credits &&
        points.last.portfolio == point.portfolio) {
      return;
    }
    points.add(point);
    final trimmed = points.length > _maxHistory
        ? points.sublist(points.length - _maxHistory)
        : points;
    await _write(_historyBox, userId, {
      'points': [for (final p in trimmed) p.toMap()],
    });
  }

  Future<void> deleteHistory(String userId) => _remove(_historyBox, userId);

  // ---------------------------------------------------------------- aukcije

  List<Auction> get auctions =>
      _auctions.values.map(Auction.fromMap).toList(growable: false);

  Auction? auctionById(String id) {
    final map = _auctions.get(id);
    return map == null ? null : Auction.fromMap(map);
  }

  Future<void> putAuction(Auction a) => _write(_auctionsBox, a.id, a.toMap());

  /// Aktivna aukcija za predmet (najviše jedna).
  Auction? activeAuctionFor(String deviceId) {
    for (final a in auctions) {
      if (a.isActive && a.deviceId == deviceId) return a;
    }
    return null;
  }

  /// Krediti blokirani u vodećim ponudama korisnika.
  double heldCredits(String userId) => auctions
      .where((a) => a.isActive && a.highestBid?.userId == userId)
      .fold(0.0, (sum, a) => sum + a.highestBid!.amount);

  /// Bilježi trenutnu ukupnu vrijednost korisnika u povijest
  /// (raspoloživi + blokirani krediti, plus vrijednost predmeta).
  Future<void> recordSnapshot(String userId, {DateTime? now}) async {
    final user = userById(userId);
    if (user == null) return;
    final portfolio = devices
        .where((d) => d.ownerId == userId)
        .fold(0.0, (sum, d) => sum + d.price);
    await appendHistory(
      userId,
      PortfolioPoint(
        time: now ?? DateTime.now(),
        credits: ((user.credits + heldCredits(userId)) * 100).round() / 100,
        portfolio: (portfolio * 100).round() / 100,
      ),
    );
  }

  // ---------------------------------------------------------------- dostave

  List<Delivery> get deliveries =>
      _deliveries.values.map(Delivery.fromMap).toList(growable: false);

  Delivery? deliveryById(String id) {
    final map = _deliveries.get(id);
    return map == null ? null : Delivery.fromMap(map);
  }

  Future<void> putDelivery(Delivery d) =>
      _write(_deliveriesBox, d.id, d.toMap());

  // ---------------------------------------------------------- sinkronizacija

  /// Svi sinkronizirani zapisi: tablica → (id → podaci).
  Map<String, Map<String, Map<String, dynamic>>> exportAll() => {
    for (final t in syncedTables)
      t: {
        for (final e in _tables[t]!.toMap().entries)
          e.key.toString(): Map<String, dynamic>.from(e.value),
      },
  };

  bool get hasData => _users.isNotEmpty;

  /// Promjena stigla iz online baze — sprema se BEZ [onLocalChange]
  /// (inače bi se vratila natrag u bazu).
  Future<void> applyRemote(
    String table,
    String id,
    Map<String, dynamic>? data,
  ) async {
    final box = _tables[table];
    if (box == null) return;
    if (data == null) {
      await box.delete(id);
    } else {
      await box.put(id, data);
    }
  }

  /// Zamjenjuje sve lokalne podatke onima iz online baze.
  Future<void> replaceAllFromRemote(
    Map<String, Map<String, Map<String, dynamic>>> data,
  ) async {
    for (final t in syncedTables) {
      final box = _tables[t]!;
      await box.clear();
      await box.putAll(data[t] ?? const {});
    }
  }

  // ----------------------------------------------------------------- sesija

  String? get currentUserId => _session.get(_currentUserKey) as String?;

  bool get isAdmin => _session.get(_isAdminKey) == true;

  /// 'light' | 'dark' | 'system' (zadano: svijetla tema).
  String get themeMode => _session.get(_themeKey) as String? ?? 'light';

  Future<void> setThemeMode(String mode) => _session.put(_themeKey, mode);

  /// 'hr' | 'en' (zadano: hrvatski).
  String get lang => _session.get(_langKey) as String? ?? 'hr';

  Future<void> setLang(String lang) => _session.put(_langKey, lang);

  bool get howItWorksDismissed => _session.get(_howItWorksKey) == true;

  Future<void> dismissHowItWorks() => _session.put(_howItWorksKey, true);

  Future<void> saveSession({String? userId, bool isAdmin = false}) async {
    if (userId == null) {
      await _session.delete(_currentUserKey);
    } else {
      await _session.put(_currentUserKey, userId);
    }
    await _session.put(_isAdminKey, isAdmin);
  }
}
