import 'package:flutter/material.dart' show ThemeMode;

import '../l10n/tr.dart';
import '../services/auth_backend.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/report.dart';
import '../models/review.dart';
import '../models/price_offer.dart';
import '../models/story.dart';
import '../models/swap_offer.dart';
import '../models/auction.dart';
import '../models/delivery.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../models/portfolio_point.dart';
import '../models/user_status.dart';
import '../services/seed_data.dart';
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
    this.bargains = const [],
    this.searchHistory = const [],
    this.views = const {},
    this.stories = const [],
    this.seenStories = const {},
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
      bargains: [...storage.bargains]
        ..sort(
          (a, b) => (b.updatedAt ?? b.createdAt).compareTo(
            a.updatedAt ?? a.createdAt,
          ),
        ),
      searchHistory: storage.searchHistory,
      views: storage.views,
      stories: [
        ...storage.stories,
        ...SeedData.dailyStories(storage.devices, DateTime.now()),
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      seenStories: storage.seenStories,
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

  /// Ponude cijena (cjenkanje), najnovije prvo.
  final List<PriceOffer> bargains;

  /// Nedavne pretrage na ovom uređaju (najnovije prvo).
  final List<String> searchHistory;

  /// Broj prikaza po objavi (predmetu).
  final Map<String, int> views;

  /// Sve priče (najstarije prvo) i one koje sam pogledao na ovom uređaju.
  final List<Story> stories;
  final Set<String> seenStories;

  /// Aktivne priče grupirane po trgovini: prvo moje, zatim nepogledane
  /// (praćene trgovine prve), na kraju pogledane.
  List<StoryGroup> get storyGroups {
    final now = DateTime.now();
    final byUser = <String, List<Story>>{};
    for (final s in stories) {
      if (!s.activeAt(now)) continue;
      final u = userById(s.userId);
      if (u == null || u.pendingDeletion || isBlocked(u.id)) continue;
      (byUser[s.userId] ??= []).add(s);
    }
    final groups = [
      for (final e in byUser.entries)
        StoryGroup(
          userById(e.key)!,
          e.value,
          seen: e.value.every((s) => seenStories.contains(s.id)),
        ),
    ];
    int rank(StoryGroup g) => g.user.id == currentUserId
        ? 0
        : !g.seen && isFollowing(g.user.id)
        ? 1
        : !g.seen
        ? 2
        : 3;
    groups.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0
          ? r
          : b.stories.last.createdAt.compareTo(a.stories.last.createdAt);
    });
    return groups;
  }

  /// Aktivne priče korisnika (za prsten oko profilne slike).
  StoryGroup? storiesOf(String userId) {
    for (final g in storyGroups) {
      if (g.user.id == userId) return g;
    }
    return null;
  }

  int viewsOf(String deviceId) => views[deviceId] ?? 0;

  /// "Lajkovi" objave = koliko korisnika ima predmet u favoritima.
  int likesOf(String deviceId) =>
      users.where((u) => u.favorites.contains(deviceId)).length;

  /// Pratitelji korisnika (najnoviji računi prvi).
  List<AppUser> followersListOf(String userId) => users
      .where((u) => u.following.contains(userId) && !u.pendingDeletion)
      .toList()
      .reversed
      .toList();

  /// Računi koje korisnik prati.
  List<AppUser> followingListOf(String userId) {
    final ids = userById(userId)?.following ?? const [];
    return [
      for (final id in ids.reversed)
        if (userById(id) case final u? when !u.pendingDeletion) u,
    ];
  }

  /// Prodaje korisnika drugim korisnicima (najnovije prvo).
  List<LoopTransaction> salesOf(String userId) => transactions
      .where(
        (t) =>
            t.type == TransactionType.sell &&
            (t.sellerId ?? t.userId) == userId &&
            t.buyerId != null &&
            t.buyerId != userId,
      )
      .toList();

  /// Svi računi koji imaju trgovinu (barem jedan oglas), bez mene i
  /// blokiranih.
  List<AppUser> get shops {
    final owners = <String>{
      for (final d in marketDevices)
        if (d.ownerId != null) d.ownerId!,
    };
    return users.where((u) => owners.contains(u.id)).toList();
  }

  /// Moja ocjena trgovine (ako sam je ocijenio).
  Review? myShopReviewOf(String sellerId) {
    for (final r in reviews) {
      if (r.sellerId == sellerId &&
          r.buyerId == currentUserId &&
          r.deliveryId.isEmpty) {
        return r;
      }
    }
    return null;
  }

  /// Ponude cijena u kojima sudjeluje trenutni korisnik.
  List<PriceOffer> get myBargains => currentUserId == null
      ? const []
      : bargains
            .where(
              (o) => o.buyerId == currentUserId || o.sellerId == currentUserId,
            )
            .toList();

  /// Ponude cijena koje čekaju MOJ odgovor (kao prodavatelj ili kupac
  /// s protuponudom).
  List<PriceOffer> get bargainsToAnswer {
    final now = DateTime.now();
    return myBargains
        .where(
          (o) =>
              !o.staleAt(now) &&
              ((o.status == BargainStatus.pending &&
                      o.sellerId == currentUserId) ||
                  (o.status == BargainStatus.countered &&
                      o.buyerId == currentUserId)),
        )
        .toList();
  }

  /// Moja otvorena ili prihvaćena ponuda za predmet (kao kupac).
  PriceOffer? myBargainFor(String deviceId) {
    final now = DateTime.now();
    for (final o in bargains) {
      if (o.buyerId == currentUserId &&
          o.deviceId == deviceId &&
          (o.usableAt(now) || (o.isOpen && !o.staleAt(now)))) {
        return o;
      }
    }
    return null;
  }

  /// Cijena koju bih sada platio za predmet (dogovorena ili oglasa).
  double priceForMe(Device d) {
    final o = myBargainFor(d.id);
    return o != null && o.usableAt(DateTime.now()) ? o.agreedPrice : d.askPrice;
  }

  /// Broj pratitelja korisnika.
  int followersOf(String userId) =>
      users.where((u) => u.following.contains(userId)).length;

  bool isFollowing(String userId) =>
      currentUser?.following.contains(userId) ?? false;

  /// Prodavatelj predmeta ima plaćeno isticanje.
  bool isPromotedItem(Device d) => userById(d.ownerId)?.isPromoted ?? false;

  /// Ljestvica prodavatelja po prodaji drugim korisnicima u zadnjih
  /// [days] dana (`null` = ukupno): broj prodaja i promet.
  List<SellerStats> leaderboard({int? days, int limit = 20}) {
    final since = days == null
        ? null
        : DateTime.now().subtract(Duration(days: days));
    final stats = <String, SellerStats>{};
    for (final t in transactions) {
      if (t.type != TransactionType.sell) continue;
      final seller = t.sellerId ?? t.userId;
      // Samo prodaje drugim korisnicima (ne LOOP-u).
      if (t.buyerId == null || t.buyerId == seller) continue;
      if (since != null && t.createdAt.isBefore(since)) continue;
      final user = userById(seller);
      if (user == null || user.pendingDeletion) continue;
      final s = stats[seller] ?? SellerStats(user);
      stats[seller] = s.add(t.price);
    }
    final list = stats.values.toList()
      ..sort((a, b) {
        final c = b.sales.compareTo(a.sales);
        return c != 0 ? c : b.revenue.compareTo(a.revenue);
      });
    return list.take(limit).toList();
  }

  /// Broj prodaja korisnika (drugim korisnicima).
  int salesCountOf(String userId) => transactions
      .where(
        (t) =>
            t.type == TransactionType.sell &&
            (t.sellerId ?? t.userId) == userId &&
            t.buyerId != null &&
            t.buyerId != userId,
      )
      .length;

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
    // Kupljeni digitalni proizvod je u mom portfoliju, ne u Marketu.
    final bought = <String>{
      if (currentUserId != null)
        for (final t in transactions)
          if (t.type == TransactionType.buy && t.buyerId == currentUserId)
            t.deviceId,
    };
    return devices
        .where(
          (d) =>
              d.isForSale &&
              d.ownerId != currentUserId &&
              !hidden.contains(d.ownerId) &&
              !(d.isDigital && bought.contains(d.id)),
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

  /// Promet trgovanja (bez uplata i isticanja).
  double get totalVolume => transactions
      .where(
        (t) =>
            t.type != TransactionType.topUp &&
            t.type != TransactionType.promotion,
      )
      .fold(0, (sum, t) => sum + t.price);

  double get totalFees => transactions.fold(0, (sum, t) => sum + t.fee);

  /// Ukupno uplaćeno, u eurima.
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

/// Statistika prodavatelja za ljestvicu.
class SellerStats {
  const SellerStats(this.user, {this.sales = 0, this.revenue = 0});
  final AppUser user;
  final int sales;
  final double revenue;

  SellerStats add(double price) =>
      SellerStats(user, sales: sales + 1, revenue: revenue + price);
}

/// Priče jedne trgovine.
class StoryGroup {
  const StoryGroup(this.user, this.stories, {this.seen = false});
  final AppUser user;

  /// Najstarije prvo (redoslijed gledanja).
  final List<Story> stories;
  final bool seen;
}
