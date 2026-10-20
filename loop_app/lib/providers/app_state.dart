import '../models/app_user.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../models/portfolio_point.dart';
import '../models/user_status.dart';
import '../services/storage_service.dart';

/// Nepromjenjiva snimka svih podataka. Nakon svake akcije kreira se nova
/// snimka iz pohrane, pa se cijeli UI osvježava odmah.
class AppState {
  const AppState({
    required this.users,
    required this.devices,
    required this.transactions,
    required this.currentUserId,
    required this.isAdmin,
    this.myHistory = const [],
  });

  factory AppState.fromStorage(StorageService storage) {
    final txs = [...storage.transactions]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // najnovije prvo
    final devices = [...storage.devices]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final users = [...storage.users]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return AppState(
      users: users,
      devices: devices,
      transactions: txs,
      currentUserId: storage.currentUserId,
      isAdmin: storage.isAdmin,
      myHistory: storage.currentUserId == null
          ? const []
          : storage.historyOf(storage.currentUserId!),
    );
  }

  final List<AppUser> users;
  final List<Device> devices;
  final List<LoopTransaction> transactions;
  final String? currentUserId;
  final bool isAdmin;

  /// Povijest vrijednosti trenutnog korisnika (najstarije prvo).
  final List<PortfolioPoint> myHistory;

  AppUser? get currentUser {
    if (currentUserId == null) return null;
    for (final u in users) {
      if (u.id == currentUserId) return u;
    }
    return null; // korisnik je možda obrisan u admin panelu
  }

  bool get isLoggedIn => isAdmin || currentUser != null;

  List<Device> devicesOf(String userId) =>
      devices.where((d) => d.ownerId == userId).toList();

  List<Device> get myDevices =>
      currentUserId == null ? const [] : devicesOf(currentUserId!);

  /// Market = svi uređaji koji nisu u vlasništvu trenutnog korisnika
  /// i trenutno su na prodaju (vlasnik je platforma).
  List<Device> get marketDevices =>
      devices.where((d) => d.isOnMarket && d.ownerId != currentUserId).toList();

  bool isFavorite(String deviceId) =>
      currentUser?.favorites.contains(deviceId) ?? false;

  Device? deviceById(String id) {
    for (final d in devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Broj uređaja po kategoriji (samo kategorije koje imaju uređaje).
  static Map<DeviceCategory, int> countByCategory(Iterable<Device> devices) {
    final counts = <DeviceCategory, int>{};
    for (final d in devices) {
      counts[d.category] = (counts[d.category] ?? 0) + 1;
    }
    return counts;
  }

  /// Vrijednost uređaja po kategoriji.
  static Map<ItemSection, double> valueBySection(Iterable<Device> devices) {
    final values = <ItemSection, double>{};
    for (final d in devices) {
      values[d.section] = (values[d.section] ?? 0) + d.price;
    }
    return values;
  }

  static Map<DeviceCategory, double> valueByCategory(Iterable<Device> devices) {
    final values = <DeviceCategory, double>{};
    for (final d in devices) {
      values[d.category] = (values[d.category] ?? 0) + d.price;
    }
    return values;
  }

  List<LoopTransaction> get myTransactions =>
      transactions.where((t) => t.userId == currentUserId).toList();

  double portfolioValueOf(String userId) =>
      devicesOf(userId).fold(0, (sum, d) => sum + d.price);

  /// Ukupna vrijednost = krediti + vrijednost portfolija.
  double totalValueOf(AppUser user) => user.credits + portfolioValueOf(user.id);

  UserStatus statusOf(AppUser user) =>
      UserStatus.fromTotalValue(totalValueOf(user));

  String userLabel(String? userId) {
    if (userId == null) return 'LOOP Market';
    for (final u in users) {
      if (u.id == userId) return u.email;
    }
    return 'obrisan korisnik';
  }

  double get totalVolume => transactions.fold(0, (sum, t) => sum + t.price);

  double get totalFees => transactions.fold(0, (sum, t) => sum + t.fee);
}
