import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../models/auction.dart';
import '../services/auction_service.dart';
import '../services/credit_shop.dart';
import '../services/delivery_service.dart';
import '../services/fee.dart';
import '../models/delivery.dart';
import '../services/image_store.dart';
import '../utils/formatters.dart';
import '../widgets/loop_snackbar.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/trade_service.dart';
import 'app_state.dart';

/// Inicijalizirani [StorageService] — postavlja se u `main()` preko override-a.
final storageProvider = Provider<StorageService>(
  (ref) => throw UnimplementedError('storageProvider mora biti overridean'),
);

/// Spremište fotografija (u testovima se ne koristi).
final imageStoreProvider = Provider<ImageStore>(
  // S online bazom slike idu u Supabase Storage (vide ih svi testeri).
  (ref) => ImageStore(
    client: ref.watch(syncProvider) != null ? Supabase.instance.client : null,
  ),
);

/// Sinkronizacija s online bazom (`null` = lokalni način rada).
final syncProvider = Provider<SyncService?>((ref) => null);

final tradeServiceProvider = Provider<TradeService>(
  (ref) => TradeService(ref.watch(storageProvider)),
);

final deliveryServiceProvider = Provider<DeliveryService>(
  (ref) => DeliveryService(ref.watch(storageProvider)),
);

final creditShopProvider = Provider<CreditShop>(
  (ref) => CreditShop(ref.watch(storageProvider)),
);

final auctionServiceProvider = Provider<AuctionService>(
  (ref) => AuctionService(ref.watch(storageProvider)),
);

/// Koliko često se osvježavaju odbrojavanja i zaključuju istekle aukcije.
/// U testovima je `null` (bez periodičkih timera).
final tickIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 1),
);

/// Odabrani tab glavnog okvira — u provideru, da preživi promjenu teme
/// (koja ponovno gradi cijelo sučelje).
final homeTabProvider = NotifierProvider<HomeTab, int>(HomeTab.new);

class HomeTab extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

/// Glavni provider aplikacije: drži [AppState] i izlaže sve akcije.
final appProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

/// Najviše fotografija po predmetu.
const maxImages = 4;

class AppController extends Notifier<AppState> {
  StorageService get _storage => ref.read(storageProvider);
  TradeService get _trade => ref.read(tradeServiceProvider);
  AuctionService get _auctions => ref.read(auctionServiceProvider);

  @override
  AppState build() {
    // Tuđe promjene iz online baze → osvježi prikaz (grupirano, jer ih
    // može stići više odjednom).
    final sync = ref.watch(syncProvider);
    if (sync != null) {
      sync.onRemoteChange = () {
        _remoteRefresh?.cancel();
        _remoteRefresh = Timer(const Duration(milliseconds: 150), () {
          if (ref.mounted) _refresh();
        });
      };
      ref.onDispose(() => _remoteRefresh?.cancel());
    }
    return AppState.fromStorage(ref.watch(storageProvider));
  }

  Timer? _remoteRefresh;

  /// Ponovno učitava stanje iz pohrane nakon svake promjene.
  void _refresh() => state = AppState.fromStorage(_storage);

  // ------------------------------------------------------------- sesija

  Future<void> login(String email, String password) async {
    final user = await _trade.login(email, password);
    await _trade.ensureHistory(user.id);
    await _storage.saveSession(userId: user.id);
    _refresh();
  }

  Future<void> loginAsGuest() async {
    final user = await _trade.loginAsGuest();
    await _trade.ensureHistory(user.id);
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
    ref.read(homeTabProvider.notifier).select(0);
    await _storage.saveSession();
    _refresh();
  }

  Future<void> resetDemoData() async {
    await _storage.resetAll();
    await ref.read(syncProvider)?.resetRemote();
    await ref.read(imageStoreProvider).clearAll();
    _refresh();
  }

  // ------------------------------------------------------------ trgovanje

  Future<Device> addDevice({
    required String name,
    required String model,
    required DeviceCondition condition,
    required double price,
    required DeviceCategory category,
    List<String> imagePaths = const [],
    String description = '',
  }) async {
    final device = await _trade.addDevice(
      userId: _requireUserId(),
      name: name,
      model: model,
      condition: condition,
      price: price,
      category: category,
      imagePaths: imagePaths,
      description: description,
    );
    _refresh();
    return device;
  }

  Future<LoopTransaction> sell(String deviceId) async {
    final tx = await _trade.sell(userId: _requireUserId(), deviceId: deviceId);
    _refresh();
    return tx;
  }

  /// Kupnja iz Marketa s odabranom dostavom. Najprije se provjeri da
  /// krediti pokrivaju predmet + fee + dostavu, pa tek onda kupuje.
  Future<LoopTransaction> buy(
    String deviceId, {
    DeliveryMethod method = DeliveryMethod.pickup,
    String? destination,
  }) async {
    final userId = _requireUserId();
    final device = state.deviceById(deviceId);
    final user = state.currentUser!;
    if (device == null) throw const TradeException('Predmet ne postoji.');
    final error = DeliveryService.validate(method, destination);
    if (error != null) throw TradeException(error);
    final total = buyTotal(device.price) + method.cost;
    if (user.credits < total) {
      throw TradeException(
        'Nemaš dovoljno kredita: treba ${formatCredits(total)} '
        '(s feejem i dostavom), imaš ${formatCredits(user.credits)}.',
      );
    }
    final tx = await _trade.buy(userId: userId, deviceId: deviceId);
    await ref
        .read(deliveryServiceProvider)
        .createForPurchase(
          userId: userId,
          device: device,
          method: method,
          destination: destination,
        );
    _refresh();
    return tx;
  }

  /// Pobjednik aukcije bira način dostave.
  Future<void> chooseDelivery(
    String deliveryId,
    DeliveryMethod method,
    String? destination,
  ) async {
    await ref
        .read(deliveryServiceProvider)
        .choose(
          userId: _requireUserId(),
          deliveryId: deliveryId,
          method: method,
          destination: destination,
        );
    _refresh();
  }

  Future<void> confirmReceipt(String deliveryId) async {
    await ref
        .read(deliveryServiceProvider)
        .confirmReceipt(_requireUserId(), deliveryId);
    _refresh();
  }

  Future<bool> toggleFavorite(String deviceId) async {
    final added = await _trade.toggleFavorite(_requireUserId(), deviceId);
    _refresh();
    return added;
  }

  /// Otvara galeriju/kameru i dodaje fotografije vlastitom predmetu.
  /// Vraća broj dodanih fotografija.
  Future<int> addImages(String deviceId, {bool camera = false}) async {
    final device = state.deviceById(deviceId);
    if (device == null) throw const TradeException('Predmet ne postoji.');
    final free = maxImages - device.imagePaths.length;
    if (free <= 0) {
      throw const TradeException('Najviše $maxImages fotografije po predmetu.');
    }
    final paths = await ref
        .read(imageStoreProvider)
        .pick(camera: camera, limit: free);
    if (paths.isEmpty) return 0;
    await _trade.setImages(_requireUserId(), deviceId, [
      ...device.imagePaths,
      ...paths,
    ]);
    _refresh();
    return paths.length;
  }

  Future<void> removeImage(String deviceId, String path) async {
    final device = state.deviceById(deviceId);
    if (device == null) return;
    await _trade.setImages(
      _requireUserId(),
      deviceId,
      device.imagePaths.where((p) => p != path).toList(),
    );
    await ref.read(imageStoreProvider).delete([path]);
    _refresh();
  }

  // -------------------------------------------------------- kupnja kredita

  /// Simulirana kupnja kredita (demo: ništa se ne naplaćuje).
  Future<LoopTransaction> buyCredits(int credits, PaymentMethod method) async {
    final tx = await ref
        .read(creditShopProvider)
        .purchase(userId: _requireUserId(), credits: credits, method: method);
    _refresh();
    return tx;
  }

  // ------------------------------------------------------------- postavke

  Future<void> setThemeMode(ThemeMode mode) async {
    await _storage.setThemeMode(mode.name);
    _refresh();
  }

  Future<void> dismissHowItWorks() async {
    await _storage.dismissHowItWorks();
    _refresh();
  }

  // -------------------------------------------------------------- aukcije

  Future<Auction> createAuction({
    required String deviceId,
    required double startPrice,
    required Duration duration,
  }) async {
    final a = await _auctions.create(
      userId: _requireUserId(),
      deviceId: deviceId,
      startPrice: startPrice,
      duration: duration,
    );
    _refresh();
    return a;
  }

  Future<void> placeBid(String auctionId, double amount) async {
    await _auctions.placeBid(
      userId: _requireUserId(),
      auctionId: auctionId,
      amount: amount,
    );
    _refresh();
  }

  Future<void> cancelAuction(String auctionId) async {
    await _auctions.cancelBySeller(_requireUserId(), auctionId);
    _refresh();
  }

  Future<void> adminCancelAuction(String auctionId) async {
    await _auctions.cancelByAdmin(auctionId);
    _refresh();
  }

  bool _settling = false;

  /// Zaključuje istekle aukcije i javlja ishod prijavljenom korisniku.
  Future<void> settleExpiredAuctions() async {
    final now = DateTime.now();
    if (_settling || !state.activeAuctions.any((a) => a.isExpired(now))) {
      return;
    }
    _settling = true;
    try {
      final results = await _auctions.settleExpired(now: now);
      _refresh();
      final me = state.currentUserId;
      for (final r in results) {
        final a = r.auction;
        final price = formatCredits(a.highestBid?.amount ?? 0);
        if (r.winnerId != null && r.winnerId == me) {
          showLoopSnackBar('🏆 Osvojio si aukciju: ${a.deviceName} za $price');
        } else if (a.sellerId == me) {
          showLoopSnackBar(
            r.winnerId != null
                ? 'Tvoja aukcija je završila: ${a.deviceName} prodano za $price'
                : 'Aukcija za ${a.deviceName} je završila bez ponuda',
          );
        } else if (me != null && a.bids.any((b) => b.userId == me)) {
          showLoopSnackBar(
            'Aukcija ${a.deviceName} je završila — nisi pobijedio',
          );
        }
      }
    } finally {
      _settling = false;
    }
  }

  // ---------------------------------------------------------------- admin

  Future<void> addCredits(String userId, double amount) async {
    await _trade.addCredits(userId, amount);
    _refresh();
  }

  Future<void> deleteUser(String userId) async {
    await _auctions.cancelForUser(userId);
    await _trade.deleteUser(userId);
    _refresh();
  }

  Future<void> deleteDevice(String deviceId) async {
    await _auctions.cancelForDevice(deviceId);
    final images = await _trade.deleteDevice(deviceId);
    await ref.read(imageStoreProvider).delete(images);
    _refresh();
  }

  String _requireUserId() {
    final id = state.currentUser?.id;
    if (id == null) throw const TradeException('Nisi prijavljen.');
    return id;
  }
}
