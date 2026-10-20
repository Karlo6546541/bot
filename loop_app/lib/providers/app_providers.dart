import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../services/storage_service.dart';
import '../services/trade_service.dart';
import 'app_state.dart';

/// Inicijalizirani [StorageService] — postavlja se u `main()` preko override-a.
final storageProvider = Provider<StorageService>(
  (ref) => throw UnimplementedError('storageProvider mora biti overridean'),
);

final tradeServiceProvider = Provider<TradeService>(
  (ref) => TradeService(ref.watch(storageProvider)),
);

/// Glavni provider aplikacije: drži [AppState] i izlaže sve akcije.
final appProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppController extends Notifier<AppState> {
  StorageService get _storage => ref.read(storageProvider);
  TradeService get _trade => ref.read(tradeServiceProvider);

  @override
  AppState build() => AppState.fromStorage(ref.watch(storageProvider));

  /// Ponovno učitava stanje iz pohrane nakon svake promjene.
  void _refresh() => state = AppState.fromStorage(_storage);

  // ------------------------------------------------------------- sesija

  Future<void> login(String email, String password) async {
    final user = await _trade.login(email, password);
    await _storage.saveSession(userId: user.id);
    _refresh();
  }

  Future<void> loginAsGuest() async {
    final user = await _trade.loginAsGuest();
    await _storage.saveSession(userId: user.id);
    _refresh();
  }

  Future<void> adminLogin(String email, String password) async {
    if (!_trade.isAdminLogin(email, password)) {
      throw const TradeException('Pogrešni admin podaci.');
    }
    await _storage.saveSession(isAdmin: true);
    _refresh();
  }

  Future<void> logout() async {
    await _storage.saveSession();
    _refresh();
  }

  Future<void> resetDemoData() async {
    await _storage.resetAll();
    _refresh();
  }

  // ------------------------------------------------------------ trgovanje

  Future<Device> addDevice({
    required String name,
    required String model,
    required DeviceCondition condition,
    required double price,
    required DeviceCategory category,
  }) async {
    final device = await _trade.addDevice(
      userId: _requireUserId(),
      name: name,
      model: model,
      condition: condition,
      price: price,
      category: category,
    );
    _refresh();
    return device;
  }

  Future<LoopTransaction> sell(String deviceId) async {
    final tx = await _trade.sell(userId: _requireUserId(), deviceId: deviceId);
    _refresh();
    return tx;
  }

  Future<LoopTransaction> buy(String deviceId) async {
    final tx = await _trade.buy(userId: _requireUserId(), deviceId: deviceId);
    _refresh();
    return tx;
  }

  Future<bool> toggleFavorite(String deviceId) async {
    final added = await _trade.toggleFavorite(_requireUserId(), deviceId);
    _refresh();
    return added;
  }

  // ---------------------------------------------------------------- admin

  Future<void> addCredits(String userId, double amount) async {
    await _trade.addCredits(userId, amount);
    _refresh();
  }

  Future<void> deleteUser(String userId) async {
    await _trade.deleteUser(userId);
    _refresh();
  }

  Future<void> deleteDevice(String deviceId) async {
    await _trade.deleteDevice(deviceId);
    _refresh();
  }

  String _requireUserId() {
    final id = state.currentUser?.id;
    if (id == null) throw const TradeException('Nisi prijavljen.');
    return id;
  }
}
