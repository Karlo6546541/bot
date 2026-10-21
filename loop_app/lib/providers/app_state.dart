import 'package:flutter/material.dart' show ThemeMode;

import '../l10n/tr.dart';
import '../services/auth_backend.dart';
import '../models/app_user.dart';
import '../models/auction.dart';
import '../models/delivery.dart';
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
    this.auctions = const [],
    this.deliveries = const [],
    this.themeMode = ThemeMode.light,
    this.lang = AppLang.hr,
    this.pendingSignup,
    this.showHowItWorks = true,
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
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == storage.themeMode,
        orElse: () => ThemeMode.light,
      ),
      lang: AppLang.fromName(storage.lang),
      pendingSignup: storage.pendingAuth == null
          ? null
          : AuthIdentity.fromMap(storage.pendingAuth!),
      showHowItWorks: !storage.howItWorksDismissed,
      deliveries: [...storage.deliveries]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      auctions: [...storage.auctions]
        ..sort((a, b) => a.endsAt.compareTo(b.endsAt)),
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

  /// Odabrana tema (svijetla / tamna / prema sustavu).
  final ThemeMode themeMode;

  /// Jezik sučelja.
  final AppLang lang;

  /// Prijava koja čeka odabir korisničkog imena.
  final AuthIdentity? pendingSignup;

  /// Prikazati karticu "Kako LOOP radi" na početnoj.
  final bool showHowItWorks;

  /// Sve aukcije, sortirane po vremenu završetka.
  final List<Auction> auctions;

  /// Sve pošiljke, najnovije prvo.
  final List<Delivery> deliveries;

  List<Delivery> get myDeliveries => currentUserId == null
      ? const []
      : deliveries.where((d) => d.buyerId == currentUserId).toList();

  /// Pošiljke koje još nisu potvrđene (za prikaz "u tijeku").
  List<Delivery> get myOpenDeliveries =>
      myDeliveries.where((d) => d.confirmedAt == null).toList();

  List<Auction> get activeAuctions =>
      auctions.where((a) => a.isActive).toList();

  Auction? auctionById(String id) {
    for (final a in auctions) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Aktivna aukcija predmeta (predmet je tada zaključan za prodaju).
  Auction? activeAuctionFor(String deviceId) {
    for (final a in auctions) {
      if (a.isActive && a.deviceId == deviceId) return a;
    }
    return null;
  }

  /// Krediti blokirani u vodećim ponudama.
  double heldCreditsOf(String userId) => auctions
      .where((a) => a.isActive && a.highestBid?.userId == userId)
      .fold(0.0, (sum, a) => sum + a.highestBid!.amount);

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

  List<LoopTransaction> get myTransactions => currentUserId == null
      ? const []
      : transactions.where((t) => t.involves(currentUserId!)).toList();

  double portfolioValueOf(String userId) =>
      devicesOf(userId).fold(0, (sum, d) => sum + d.price);

  /// Ukupna vrijednost = krediti (uključujući blokirane u ponudama)
  /// + vrijednost portfolija.
  double totalValueOf(AppUser user) =>
      user.credits + heldCreditsOf(user.id) + portfolioValueOf(user.id);

  UserStatus statusOf(AppUser user) =>
      UserStatus.fromTotalValue(totalValueOf(user));

  String userLabel(String? userId) {
    if (userId == null) return 'LOOP Market';
    for (final u in users) {
      if (u.id == userId) return u.handle;
    }
    return 'obrisan korisnik';
  }

  /// Promet trgovanja (bez kupnje kredita).
  double get totalVolume => transactions
      .where((t) => t.type != TransactionType.topUp)
      .fold(0, (sum, t) => sum + t.price);

  double get totalFees => transactions.fold(0, (sum, t) => sum + t.fee);

  /// Ukupno prodano kredita, u eurima.
  double get totalTopUpEur => transactions
      .where((t) => t.type == TransactionType.topUp)
      .fold(0, (sum, t) => sum + t.price);
}
