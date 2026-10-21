import 'package:flutter/material.dart' show ThemeMode;

import '../l10n/tr.dart';
import '../services/auth_backend.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/report.dart';
import '../models/review.dart';
import '../models/swap_offer.dart';
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
    this.reviews = const [],
    this.notifications = const [],
    this.reports = const [],
    this.messages = const [],
    this.offers = const [],
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
      reviews: [...storage.reviews]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      notifications: [...storage.notifications]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      reports: [...storage.reports]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      messages: [...storage.messages]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      offers: [...storage.offers]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
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

  /// Ocjene prodavatelja, najnovije prvo.
  final List<Review> reviews;

  /// Sve obavijesti (najnovije prvo) — prikazuju se samo vlastite.
  final List<AppNotification> notifications;

  /// Prijave (za admina), najnovije prvo.
  final List<Report> reports;

  /// Poruke, najstarije prvo.
  final List<ChatMessage> messages;

  /// Ponude zamjene, najnovije prvo.
  final List<SwapOffer> offers;

  List<Review> reviewsOf(String userId) =>
      reviews.where((r) => r.sellerId == userId).toList();

  Rating ratingOf(String userId) => Rating.of(reviewsOf(userId));

  List<AppNotification> get myNotifications => currentUserId == null
      ? const []
      : notifications.where((n) => n.userId == currentUserId).toList();

  int get unreadNotifications => myNotifications.where((n) => !n.read).length;

  List<Report> get openReports => reports.where((r) => r.isOpen).toList();

  /// Razgovori trenutnog korisnika: sugovornik, zadnja poruka, nepročitano.
  List<Conversation> get conversations {
    final me = currentUserId;
    if (me == null) return const [];
    final byOther = <String, List<ChatMessage>>{};
    for (final m in messages) {
      if (m.senderId == me || m.receiverId == me) {
        (byOther[m.otherThan(me)] ??= []).add(m);
      }
    }
    final list = [
      for (final e in byOther.entries)
        Conversation(
          otherId: e.key,
          last: e.value.last,
          unread: e.value.where((m) => m.receiverId == me && !m.read).length,
        ),
    ]..sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));
    return list;
  }

  int get unreadMessages => conversations.fold(0, (s, c) => s + c.unread);

  /// Poruke s jednim korisnikom (najstarije prvo).
  List<ChatMessage> chatWith(String otherId) {
    final me = currentUserId;
    if (me == null) return const [];
    final id = ChatMessage.conversationOf(me, otherId);
    return messages.where((m) => m.conversationId == id).toList();
  }

  /// Ponude zamjene u kojima sudjeluje trenutni korisnik.
  List<SwapOffer> get myOffers => currentUserId == null
      ? const []
      : offers
            .where((o) => o.fromId == currentUserId || o.toId == currentUserId)
            .toList();

  /// Ponude koje čekaju MOJ odgovor.
  List<SwapOffer> get incomingOffers =>
      myOffers.where((o) => o.isPending && o.toId == currentUserId).toList();

  /// Je li trenutni korisnik kupio digitalni proizvod.
  bool hasPurchased(String deviceId) =>
      currentUserId != null &&
      transactions.any(
        (t) =>
            t.type == TransactionType.buy &&
            t.buyerId == currentUserId &&
            t.deviceId == deviceId,
      );

  /// Broj kupaca digitalnog proizvoda.
  int buyersCount(String deviceId) => {
    for (final t in transactions)
      if (t.type == TransactionType.buy && t.deviceId == deviceId) t.buyerId,
  }.length;

  /// Moje digitalne kupnje (predmeti koji još postoje), najnovije prvo.
  List<Device> get myDigitalPurchases {
    final me = currentUserId;
    if (me == null) return const [];
    final ids = <String>[];
    for (final t in transactions) {
      if (t.type == TransactionType.buy &&
          t.buyerId == me &&
          !ids.contains(t.deviceId)) {
        ids.add(t.deviceId);
      }
    }
    return [
      for (final id in ids)
        if (deviceById(id) case final d? when d.isDigital) d,
    ];
  }

  bool isBlocked(String userId) =>
      currentUser?.blockedIds.contains(userId) ?? false;

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

  /// Market = predmeti platforme + predmeti koje su drugi korisnici
  /// objavili (bez blokiranih i računa koji se brišu).
  List<Device> get marketDevices {
    final hidden = <String>{
      ...?currentUser?.blockedIds,
      for (final u in users)
        if (u.pendingDeletion) u.id,
    };
    return devices
        .where(
          (d) =>
              d.isForSale &&
              d.ownerId != currentUserId &&
              !hidden.contains(d.ownerId),
        )
        .toList();
  }

  /// Moji predmeti koje sam objavio u Marketu.
  List<Device> get myListings => myDevices.where((d) => d.isListed).toList();

  /// Predmeti koje je korisnik objavio u Marketu.
  List<Device> listingsOf(String userId) =>
      devicesOf(userId).where((d) => d.isListed).toList();

  AppUser? userById(String? id) {
    if (id == null) return null;
    for (final u in users) {
      if (u.id == id) return u;
    }
    return null;
  }

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

  /// Vrijednost fizičkih predmeta (digitalni proizvod se prodaje više puta
  /// pa se ne računa u vrijednost portfolija).
  double portfolioValueOf(String userId) => devicesOf(
    userId,
  ).where((d) => !d.isDigital).fold(0, (sum, d) => sum + d.price);

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

/// Razgovor s jednim korisnikom (za popis poruka).
class Conversation {
  const Conversation({
    required this.otherId,
    required this.last,
    required this.unread,
  });
  final String otherId;
  final ChatMessage last;
  final int unread;
}
