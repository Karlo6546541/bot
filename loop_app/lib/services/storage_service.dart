import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/app_user.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import 'seed_data.dart';

/// Lokalna pohrana na Hive-u. Svaki entitet je spremljen kao obična mapa
/// (ključ = ID), pa nisu potrebni generirani TypeAdapteri.
class StorageService {
  static const _usersBox = 'users';
  static const _devicesBox = 'devices';
  static const _transactionsBox = 'transactions';
  static const _sessionBox = 'session';

  static const _seededKey = 'seeded';
  static const _currentUserKey = 'currentUserId';
  static const _isAdminKey = 'isAdmin';

  late Box<Map> _users;
  late Box<Map> _devices;
  late Box<Map> _transactions;
  late Box _session;

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

    if (_session.get(_seededKey) != true) {
      await _seed();
    }
  }

  Future<void> _seed() async {
    final now = DateTime.now();
    for (final u in SeedData.users(now)) {
      await _users.put(u.id, u.toMap());
    }
    for (final d in SeedData.devices(now)) {
      await _devices.put(d.id, d.toMap());
    }
    await _session.put(_seededKey, true);
  }

  /// Briše sve podatke (uključujući sesiju) i ponovno kreira demo podatke.
  Future<void> resetAll() async {
    await _users.clear();
    await _devices.clear();
    await _transactions.clear();
    await _session.clear();
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

  Future<void> putUser(AppUser user) => _users.put(user.id, user.toMap());

  Future<void> putDevice(Device device) =>
      _devices.put(device.id, device.toMap());

  Future<void> putTransaction(LoopTransaction tx) =>
      _transactions.put(tx.id, tx.toMap());

  Future<void> deleteUser(String id) => _users.delete(id);

  Future<void> deleteDevice(String id) => _devices.delete(id);

  // ----------------------------------------------------------------- sesija

  String? get currentUserId => _session.get(_currentUserKey) as String?;

  bool get isAdmin => _session.get(_isAdminKey) == true;

  Future<void> saveSession({String? userId, bool isAdmin = false}) async {
    if (userId == null) {
      await _session.delete(_currentUserKey);
    } else {
      await _session.put(_currentUserKey, userId);
    }
    await _session.put(_isAdminKey, isAdmin);
  }
}
