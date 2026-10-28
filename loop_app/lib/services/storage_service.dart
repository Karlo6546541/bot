import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/report.dart';
import '../models/review.dart';
import '../models/price_offer.dart';
import '../models/live_show.dart';
import '../models/story.dart';
import '../models/swap_offer.dart';
import '../models/auction.dart';
import '../models/delivery.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../models/portfolio_point.dart';
import 'seed_data.dart';
import 'feed_preferences.dart';
import 'username_rules.dart';

/// Lokalna pohrana na Hive-u. Svaki entitet je spremljen kao obična mapa
/// (ključ = ID), pa nisu potrebni generirani TypeAdapteri.
/// Atomski upis nije moguć: online baza postoji, ali veza ne radi.
class OfflineClaimException implements Exception {
  const OfflineClaimException();
}

class StorageService {
  static const _usersBox = 'users';
  static const _devicesBox = 'devices';
  static const _transactionsBox = 'transactions';
  static const _sessionBox = 'session';
  static const _historyBox = 'history';
  static const _auctionsBox = 'auctions';
  static const _deliveriesBox = 'deliveries';

  static const _reviewsBox = 'reviews';
  static const _notificationsBox = 'notifications';
  static const _reportsBox = 'reports';
  static const _messagesBox = 'messages';
  static const _offersBox = 'offers';
  static const _bargainsBox = 'bargains';

  /// Priče trgovina (24 h).
  static const _storiesBox = 'stories';

  /// Podaci prodavatelja (OIB, IBAN…) — odvojeno od javnog profila; online
  /// ih vidi samo vlasnik (vidi supabase/schema.sql, loop_sellers).
  static const _sellersBox = 'sellers';

  /// Live aukcije (emisije) i njihovi događaji (ponude, chat, ulasci).
  static const _liveShowsBox = 'live_shows';
  static const _liveEventsBox = 'live_events';
  static const _seenStoriesKey = 'seenStories';

  /// Broj prikaza objava (oglasa): id predmeta → {count}.
  static const _viewsBox = 'views';

  /// Sadržaj digitalnih datoteka u lokalnom načinu (web) — NE sinkronizira
  /// se (online datoteke su u Supabase Storageu).
  static const _filesBox = 'files';

  /// Lokalne lozinke (sažeci) — NE sinkronizira se.
  static const _credentialsBox = 'credentials';

  /// Tablice koje se sinkroniziraju s online bazom (sesija ostaje lokalna).
  static const syncedTables = [
    _usersBox,
    _devicesBox,
    _transactionsBox,
    _historyBox,
    _auctionsBox,
    _deliveriesBox,
    _reviewsBox,
    _notificationsBox,
    _reportsBox,
    _messagesBox,
    _offersBox,
    _bargainsBox,
    _viewsBox,
    _storiesBox,
    _sellersBox,
    _liveShowsBox,
    _liveEventsBox,
  ];

  /// Povećaj kad se seed proširi — postojeće instalacije tada dobiju
  /// nove demo predmete bez resetiranja (vidi [_migrateSeed]).
  static const _seedVersion = 6;
  static const _seedVersionKey = 'seedVersion';

  /// Najviše točaka povijesti po korisniku.
  static const _maxHistory = 500;

  static const _seededKey = 'seeded';
  static const _currentUserKey = 'currentUserId';
  static const _isAdminKey = 'isAdmin';
  static const _themeKey = 'themeMode';
  static const _langKey = 'lang';
  static const _howItWorksKey = 'howItWorksDismissed';
  static const _pendingAuthKey = 'pendingAuth';
  static const _searchHistoryKey = 'searchHistory';

  /// Promjene koje još nisu poslane u online bazu ("tablica/id") — čuvaju
  /// se i nakon osvježavanja stranice.
  static const _pendingSyncKey = 'pendingSync';
  static const maxSearchHistory = 10;

  late Box<Map> _users;
  late Box<Map> _devices;
  late Box<Map> _transactions;
  late Box _session;
  late Box<Map> _history;
  late Box<Map> _auctions;
  late Box<Map> _deliveries;
  late Box<Map> _credentials;
  late Box _files;
  late Box<Map> _reviews;
  late Box<Map> _notifications;
  late Box<Map> _reports;
  late Box<Map> _messages;
  late Box<Map> _offers;
  late Box<Map> _bargains;
  late Box<Map> _views;
  late Box<Map> _stories;
  late Box<Map> _sellers;
  late Box<Map> _liveShows;
  late Box<Map> _liveEvents;

  // The table key is authoritative; older remote payloads may omit `id`.
  static Map<String, dynamic> _rowData(String table, String id, Map data) =>
      table == _historyBox || table == _sellersBox || table == _viewsBox
      ? Map<String, dynamic>.from(data)
      : {...Map<String, dynamic>.from(data), 'id': id};

  Future<void> _repairRecordIds() async {
    for (final entry in _tables.entries) {
      if (entry.key == _historyBox ||
          entry.key == _sellersBox ||
          entry.key == _viewsBox) {
        continue;
      }
      for (final key in entry.value.keys.toList()) {
        if (key is! String) continue;
        final raw = entry.value.get(key);
        if (raw != null && raw['id'] != key) {
          await entry.value.put(key, _rowData(entry.key, key, raw));
        }
      }
    }
  }

  /// Poziva se nakon svake lokalne promjene (za sinkronizaciju s online
  /// bazom). `data == null` znači brisanje.
  void Function(String table, String id, Map<String, dynamic>? data)?
  onLocalChange;

  /// Online "zauzimanje" zapisa (postavlja sinkronizacija dok je veza
  /// aktivna). Bez njega vrijedi samo lokalna provjera.
  /// Vraća `true` (upisano u bazu), `false` (već postoji) ili `null`
  /// (nema veze — upis ide kroz običnu sinkronizaciju).
  Future<bool?> Function(String table, String id, Map<String, dynamic> data)?
  remoteClaim;

  /// Upiše transakciju [tx] samo ako takva još ne postoji — lokalno i u
  /// online bazi. Tako se isti komad ne proda dvaput, a aukcija ne
  /// zaključi dvaput (dva uređaja istovremeno).
  ///
  /// [strict]: bez veze s bazom (ili ako upis ne uspije) baca
  /// [OfflineClaimException] umjesto lokalnog upisa — za kupnju, gdje bi
  /// lokalni upis kasnije mogao prepisati tuđu kupnju istog komada.
  Future<bool> claimTransaction(
    LoopTransaction tx, {
    bool strict = false,
  }) async {
    if (_transactions.containsKey(tx.id)) return false;
    final data = tx.toMap();
    bool? claimed;
    try {
      claimed = await remoteClaim?.call(_transactionsBox, tx.id, data);
    } on OfflineClaimException {
      if (strict) rethrow;
    }
    if (claimed == false) return false;
    if (claimed == true) {
      // Već je u bazi — samo lokalno (bez ponovnog slanja).
      await _transactions.put(tx.id, data);
    } else {
      await _write(_transactionsBox, tx.id, data);
    }
    return true;
  }

  Map<String, Box<Map>> get _tables => {
    _usersBox: _users,
    _devicesBox: _devices,
    _transactionsBox: _transactions,
    _historyBox: _history,
    _auctionsBox: _auctions,
    _deliveriesBox: _deliveries,
    _reviewsBox: _reviews,
    _notificationsBox: _notifications,
    _reportsBox: _reports,
    _messagesBox: _messages,
    _offersBox: _offers,
    _bargainsBox: _bargains,
    _viewsBox: _views,
    _storiesBox: _stories,
    _sellersBox: _sellers,
    _liveShowsBox: _liveShows,
    _liveEventsBox: _liveEvents,
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
  /// bira direktorij. [seed] = false (online baza): bez demo podataka —
  /// podaci dolaze samo iz baze, pa se stari demo nikad ne vraća u nju.
  Future<void> init({
    String? path,
    bool inMemory = false,
    bool seed = true,
  }) async {
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
    _credentials = await Hive.openBox<Map>(_credentialsBox, bytes: bytes);
    _files = await Hive.openBox(_filesBox, bytes: bytes);
    _reviews = await Hive.openBox<Map>(_reviewsBox, bytes: bytes);
    _notifications = await Hive.openBox<Map>(_notificationsBox, bytes: bytes);
    _reports = await Hive.openBox<Map>(_reportsBox, bytes: bytes);
    _messages = await Hive.openBox<Map>(_messagesBox, bytes: bytes);
    _offers = await Hive.openBox<Map>(_offersBox, bytes: bytes);
    _bargains = await Hive.openBox<Map>(_bargainsBox, bytes: bytes);
    _views = await Hive.openBox<Map>(_viewsBox, bytes: bytes);
    _stories = await Hive.openBox<Map>(_storiesBox, bytes: bytes);
    _sellers = await Hive.openBox<Map>(_sellersBox, bytes: bytes);
    _liveShows = await Hive.openBox<Map>(_liveShowsBox, bytes: bytes);
    _liveEvents = await Hive.openBox<Map>(_liveEventsBox, bytes: bytes);

    await _repairRecordIds();
    if (!seed) return;
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
        await _writeUser(u);
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
    await ensureAccounts();
    await _seedFiles();
    await _session.put(_seedVersionKey, _seedVersion);
  }

  /// Datoteke demo digitalnih proizvoda (lokalno spremište).
  Future<void> _seedFiles() async {
    for (final e in SeedData.files().entries) {
      if (fileBytes(e.key) == null) await putFileBytes(e.key, e.value);
    }
  }

  Future<void> _seed() async {
    final now = DateTime.now();
    for (final u in SeedData.users(now)) {
      await _writeUser(u);
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
    await ensureAccounts();
    await _seedFiles();
    await _session.put(_seededKey, true);
    await _session.put(_seedVersionKey, _seedVersion);
  }

  /// Demo računi dobivaju lozinku "demo", a svi računi bez korisničkog
  /// imena (iz starijih verzija) dobivaju slobodno ime iz e-maila.
  Future<void> ensureAccounts() async {
    for (final u in SeedData.users(DateTime.now())) {
      if (_users.containsKey(u.id) && credentialFor(u.email) == null) {
        await putCredential(u.email, SeedData.demoCredential(u.id));
      }
    }
    for (final u in users) {
      if (u.username.isEmpty && !u.isGuest) {
        final others = users.where((o) => o.id != u.id);
        final name = UsernameRules.firstFree(
          u.email.isNotEmpty ? u.email : u.name,
          others,
        );
        await putUser(u.copyWith(username: name));
      }
    }
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
    await _credentials.clear();
    await _files.clear();
    for (final b in [
      _reviews,
      _notifications,
      _reports,
      _messages,
      _offers,
      _bargains,
      _views,
      _stories,
    ]) {
      await b.clear();
    }
    await _seed();
  }

  // ---------------------------------------------------------------- čitanje

  List<AppUser> get users =>
      _users.values.map(_readUser).toList(growable: false);

  /// Profil + privatni podaci prodavatelja (iz zasebne tablice).
  AppUser _readUser(Map<dynamic, dynamic> raw) {
    final seller = _sellers.get(raw['id']);
    return AppUser.fromMap(seller == null ? raw : {...raw, 'seller': seller});
  }

  /// Javni profil bez podataka prodavatelja; oni idu u [_sellersBox].
  Future<void> _writeUser(AppUser u) async {
    final map = u.toMap();
    final seller = map.remove('seller');
    await _write(_usersBox, u.id, map);
    if (seller is Map<String, dynamic>) {
      await _write(_sellersBox, u.id, seller);
    }
  }

  List<Device> get devices =>
      _devices.values.map(Device.fromMap).toList(growable: false);

  List<LoopTransaction> get transactions =>
      _transactions.values.map(LoopTransaction.fromMap).toList(growable: false);

  AppUser? userById(String id) {
    final map = _users.get(id);
    return map == null ? null : _readUser(map);
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

  AppUser? userByUsername(String username) {
    final needle = UsernameRules.normalize(username);
    for (final u in users) {
      if (u.username.toLowerCase() == needle) return u;
    }
    return null;
  }

  // ------------------------------------------------- lokalne datoteke

  Uint8List? fileBytes(String key) {
    final v = _files.get(key);
    return v is Uint8List
        ? v
        : (v is List ? Uint8List.fromList(v.cast<int>()) : null);
  }

  Future<void> putFileBytes(String key, Uint8List bytes) =>
      _files.put(key, bytes);

  Future<void> deleteFileBytes(String key) => _files.delete(key);

  // ---------------------------------------------------------- lozinke

  Map<String, dynamic>? credentialFor(String email) {
    final m = _credentials.get(email.trim().toLowerCase());
    return m == null ? null : Map<String, dynamic>.from(m);
  }

  Future<void> putCredential(String email, Map<String, dynamic> data) =>
      _credentials.put(email.trim().toLowerCase(), data);

  Future<void> deleteCredential(String email) =>
      _credentials.delete(email.trim().toLowerCase());

  // ---------------------------------------------------------------- pisanje

  Future<void> putUser(AppUser user) => _writeUser(user);

  Future<void> putDevice(Device device) =>
      _write(_devicesBox, device.id, device.toMap());

  Future<void> putTransaction(LoopTransaction tx) =>
      _write(_transactionsBox, tx.id, tx.toMap());

  Future<void> deleteUser(String id) async {
    await _remove(_usersBox, id);
    if (_sellers.containsKey(id)) await _remove(_sellersBox, id);
  }

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

  /// Bilježi trenutnu ukupnu vrijednost korisnika u povijest
  /// (raspoloživi + blokirani krediti, plus vrijednost predmeta).
  Future<void> recordSnapshot(String userId, {DateTime? now}) async {
    final user = userById(userId);
    if (user == null) return;
    final portfolio = devices
        .where((d) => d.ownerId == userId && !d.isDigital)
        .fold(0.0, (sum, d) => sum + d.price);
    await appendHistory(
      userId,
      PortfolioPoint(
        time: now ?? DateTime.now(),
        credits: (user.credits * 100).round() / 100,
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

  // ------------------------------------------------- ocjene, obavijesti…

  List<Review> get reviews =>
      _reviews.values.map(Review.fromMap).toList(growable: false);

  Future<void> putReview(Review r) => _write(_reviewsBox, r.id, r.toMap());

  List<AppNotification> get notifications => _notifications.values
      .map(AppNotification.fromMap)
      .toList(growable: false);

  Future<void> putNotification(AppNotification n) =>
      _write(_notificationsBox, n.id, n.toMap());

  Future<void> deleteNotification(String id) => _remove(_notificationsBox, id);

  List<Report> get reports =>
      _reports.values.map(Report.fromMap).toList(growable: false);

  Future<void> putReport(Report r) => _write(_reportsBox, r.id, r.toMap());

  List<ChatMessage> get messages =>
      _messages.values.map(ChatMessage.fromMap).toList(growable: false);

  Future<void> putMessage(ChatMessage m) =>
      _write(_messagesBox, m.id, m.toMap());

  Future<void> deleteMessage(String id) => _remove(_messagesBox, id);

  List<SwapOffer> get offers =>
      _offers.values.map(SwapOffer.fromMap).toList(growable: false);

  SwapOffer? offerById(String id) {
    final m = _offers.get(id);
    return m == null ? null : SwapOffer.fromMap(m);
  }

  Future<void> putOffer(SwapOffer o) => _write(_offersBox, o.id, o.toMap());

  /// Nedavne pretrage (lokalno, najnovije prvo).
  List<String> get searchHistory =>
      (_session.get(_searchHistoryKey) as List?)?.cast<String>() ?? const [];

  Future<void> addSearch(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    final list = [
      q,
      ...searchHistory.where((x) => x.toLowerCase() != q.toLowerCase()),
    ].take(maxSearchHistory).toList();
    await _session.put(_searchHistoryKey, list);
  }

  Future<void> removeSearch(String query) async => _session.put(
    _searchHistoryKey,
    searchHistory.where((x) => x != query).toList(),
  );

  Future<void> clearSearchHistory() => _session.delete(_searchHistoryKey);

  List<Story> get stories =>
      _stories.values.map(Story.fromMap).toList(growable: false);

  Future<void> putStory(Story s) => _write(_storiesBox, s.id, s.toMap());

  List<LiveShow> get liveShows =>
      _liveShows.values.map(LiveShow.fromMap).toList(growable: false);

  LiveShow? liveShowById(String id) {
    final m = _liveShows.get(id);
    return m == null ? null : LiveShow.fromMap(m);
  }

  List<LiveEvent> get liveEvents =>
      _liveEvents.values.map(LiveEvent.fromMap).toList(growable: false);

  List<LiveEvent> liveEventsOf(String showId) => [
    for (final m in _liveEvents.values)
      if (m['showId'] == showId) LiveEvent.fromMap(m),
  ];

  Future<void> putLiveShow(LiveShow s) =>
      _write(_liveShowsBox, s.id, s.toMap());

  Future<void> putLiveEvent(LiveEvent e) =>
      _write(_liveEventsBox, e.id, e.toMap());

  Future<void> deleteLiveEvent(String id) => _remove(_liveEventsBox, id);

  Future<void> deleteStory(String id) => _remove(_storiesBox, id);

  /// Priče koje je korisnik ovog uređaja već pogledao.
  Set<String> get seenStories =>
      ((_session.get(_seenStoriesKey) as List?)?.cast<String>() ?? const [])
          .toSet();

  Future<void> markStorySeen(String id) async {
    final seen = (_session.get(_seenStoriesKey) as List?)?.cast<String>() ?? [];
    if (seen.contains(id)) return;
    final list = [...seen, id];
    await _session.put(
      _seenStoriesKey,
      list.length > 300 ? list.sublist(list.length - 300) : list,
    );
  }

  /// Prikazi po predmetu.
  Map<String, int> get views => {
    for (final e in _views.toMap().entries)
      e.key.toString(): ((e.value['count'] as num?) ?? 0).toInt(),
  };

  int viewsOf(String deviceId) =>
      ((_views.get(deviceId)?['count'] as num?) ?? 0).toInt();

  Future<void> addView(String deviceId) => _write(_viewsBox, deviceId, {
    'id': deviceId,
    'count': viewsOf(deviceId) + 1,
  });

  List<PriceOffer> get bargains =>
      _bargains.values.map(PriceOffer.fromMap).toList(growable: false);

  PriceOffer? bargainById(String id) {
    final m = _bargains.get(id);
    return m == null ? null : PriceOffer.fromMap(m);
  }

  Future<void> putBargain(PriceOffer o) =>
      _write(_bargainsBox, o.id, o.toMap());

  // ---------------------------------------------------------- sinkronizacija

  /// Svi sinkronizirani zapisi: tablica → (id → podaci).
  List<String> get pendingSync =>
      (_session.get(_pendingSyncKey) as List?)?.cast<String>() ?? const [];

  Future<void> setPendingSync(Iterable<String> keys) =>
      _session.put(_pendingSyncKey, keys.toList());

  /// Trenutni lokalni zapis (`null` ako ne postoji).
  Map<String, dynamic>? rawRow(String table, String id) {
    final v = _tables[table]?.get(id);
    return v == null ? null : Map<String, dynamic>.from(v);
  }

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
      await box.put(id, _rowData(table, id, data));
    }
  }

  /// Zamjenjuje sve lokalne podatke onima iz online baze.
  Future<void> replaceAllFromRemote(
    Map<String, Map<String, Map<String, dynamic>>> data,
  ) async {
    // Samo tablice koje postoje online (ostale ostaju lokalne).
    for (final t in syncedTables.where(data.containsKey)) {
      final box = _tables[t]!;
      await box.clear();
      await box.putAll({
        for (final entry in data[t]!.entries)
          entry.key: _rowData(t, entry.key, entry.value),
      });
    }
  }

  // ----------------------------------------------------------------- sesija

  bool get isOpen => _session.isOpen;

  String? get currentUserId => _session.get(_currentUserKey) as String?;

  bool get isAdmin => _session.get(_isAdminKey) == true;

  /// 'light' | 'dark' | 'system' (zadano: svijetla tema).
  String get themeMode => _session.get(_themeKey) as String? ?? 'light';

  Future<void> setThemeMode(String mode) => _session.put(_themeKey, mode);

  /// Kategorije nedavno otvorenih oglasa (najnovije zadnje, najviše 30) —
  /// signal za "Za tebe". Samo na ovom uređaju.
  List<String> get recentCategories =>
      (_session.get('recentCategories:${currentUserId ?? 'guest'}') as List?)
          ?.cast<String>() ??
      const [];

  Future<void> addRecentCategories(Iterable<String> names) {
    final list = [...recentCategories, ...names];
    return _session.put(
      'recentCategories:${currentUserId ?? 'guest'}',
      list.length > 30 ? list.sublist(list.length - 30) : list,
    );
  }

  FeedPreferences feedPreferences(String? userId) => FeedPreferences.fromMap(
    _session.get('feedPreferences:${userId ?? 'guest'}') as Map?,
  );

  Future<void> saveFeedPreferences(String? userId, FeedPreferences value) =>
      _session.put('feedPreferences:${userId ?? 'guest'}', value.toMap());

  /// Država odabrana pri registraciji (dok se račun ne prijavi).
  String? get pendingCountry => _session.get('pendingCountry') as String?;

  Future<void> setPendingCountry(String? code) => code == null
      ? _session.delete('pendingCountry')
      : _session.put('pendingCountry', code);

  /// Zvuk u liveu utišan (vibracija ostaje).
  bool get liveMuted => _session.get('liveMuted') == true;

  Future<void> setLiveMuted(bool muted) => _session.put('liveMuted', muted);

  /// 'hr' | 'en' (zadano: hrvatski).
  String get lang => _session.get(_langKey) as String? ?? 'hr';

  Future<void> setLang(String lang) => _session.put(_langKey, lang);

  /// Prijava čeka odabir korisničkog imena (npr. prva Google prijava).
  Map<dynamic, dynamic>? get pendingAuth =>
      _session.get(_pendingAuthKey) as Map?;

  Future<void> setPendingAuth(Map<String, dynamic>? data) => data == null
      ? _session.delete(_pendingAuthKey)
      : _session.put(_pendingAuthKey, data);

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
