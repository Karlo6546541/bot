import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../models/auction.dart';
import '../services/account_service.dart';
import '../services/auction_service.dart';
import '../services/auth_backend.dart';
import '../services/chat_service.dart';
import '../services/community_service.dart';
import '../services/swap_service.dart';
import '../models/report.dart';
import '../services/credit_shop.dart';
import '../services/delivery_service.dart';
import '../services/fee.dart';
import '../models/delivery.dart';
import '../services/file_store.dart';
import '../services/image_store.dart';
import '../utils/formatters.dart';
import '../widgets/loop_snackbar.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/trade_service.dart';
import 'package:uuid/uuid.dart';
import '../services/file_saver/file_saver.dart';
import 'app_state.dart';
import '../l10n/tr.dart';

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

/// Datoteke digitalnih proizvoda (online: privatni Supabase bucket).
final fileStoreProvider = Provider<FileStore>(
  (ref) => FileStore(
    ref.watch(storageProvider),
    client: ref.watch(syncProvider) != null ? Supabase.instance.client : null,
  ),
);

/// Sinkronizacija s online bazom (`null` = lokalni način rada).
final syncProvider = Provider<SyncService?>((ref) => null);

/// Prijava: lokalno, ili Supabase Auth kad je online baza postavljena
/// (override u `main()`).
final authBackendProvider = Provider<AuthBackend>(
  (ref) => LocalAuthBackend(ref.watch(storageProvider)),
);

final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(
    ref.watch(storageProvider),
    ref.watch(authBackendProvider),
  ),
);

/// Korisnik je otvorio link za novu lozinku (Supabase) — prikaži obrazac.
final passwordRecoveryProvider = NotifierProvider<PasswordRecovery, bool>(
  PasswordRecovery.new,
);

class PasswordRecovery extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final communityServiceProvider = Provider<CommunityService>(
  (ref) => CommunityService(ref.watch(storageProvider)),
);

final chatServiceProvider = Provider<ChatService>(
  (ref) => ChatService(ref.watch(storageProvider)),
);

final swapServiceProvider = Provider<SwapService>(
  (ref) => SwapService(ref.watch(storageProvider)),
);

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
  AccountService get _accounts => ref.read(accountServiceProvider);
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
          if (!ref.mounted) return;
          _refresh();
          unawaited(_autoListPortfolios());
        });
      };
      ref.onDispose(() => _remoteRefresh?.cancel());
    }
    // Prijave koje ne pokreće aplikacija: povratak s Google prijave,
    // link iz e-maila (potvrda, nova lozinka), istek sesije.
    final sub = ref.watch(authBackendProvider).events.listen(_onAuthEvent);
    ref.onDispose(sub.cancel);
    // Računi kojima je istekao rok za predomišljanje brišu se trajno.
    Future.microtask(_purgeDeletedAccounts);
    Future.microtask(_autoListPortfolios);
    return AppState.fromStorage(ref.watch(storageProvider));
  }

  Timer? _remoteRefresh;

  /// Ponovno učitava stanje iz pohrane nakon svake promjene.
  void _refresh() => state = AppState.fromStorage(_storage);

  // ------------------------------------------------------------- sesija

  /// Prijava e-mailom (ili lokalno korisničkim imenom) i lozinkom.
  Future<SignInResult> login(String identifier, String password) async =>
      _apply(await _accounts.login(identifier, password));

  Future<SignInResult> register({
    required String email,
    required String password,
    required String username,
    String referral = '',
  }) async => _apply(
    await _accounts.register(
      email: email,
      password: password,
      username: username,
      referral: referral,
    ),
  );

  Future<void> signInWithGoogle() =>
      ref.read(authBackendProvider).signInWithGoogle();

  /// Korisnik je odabrao korisničko ime za novu prijavu (npr. Google).
  Future<void> chooseUsername(String username) async {
    final identity = _accounts.pendingIdentity;
    if (identity == null) throw TradeException(t('Prijava je istekla.'));
    final user = await _accounts.createProfile(identity, username);
    await _apply(SignedIn(user));
  }

  Future<void> cancelPendingSignup() async {
    await _accounts.cancelPending();
    await ref.read(authBackendProvider).signOut();
    _refresh();
  }

  Future<SignInResult> _apply(SignInResult result) async {
    if (result is SignedIn) {
      await _trade.ensureHistory(result.user.id);
      await _storage.saveSession(userId: result.user.id);
      if (result.restored) {
        showLoopSnackBar(t('Dobro došao natrag! Brisanje računa je otkazano.'));
      }
    }
    _refresh();
    unawaited(_autoListPortfolios());
    return result;
  }

  Future<void> _onAuthEvent(AuthEvent event) async {
    if (!ref.mounted) return;
    switch (event) {
      case AuthSignedIn(:final identity):
        // Već prijavljen s postojećim profilom — ništa za napraviti.
        if (state.isAdmin || state.currentUser?.id == identity.uid) return;
        try {
          await _apply(await _accounts.completeSignIn(identity));
        } on TradeException catch (e) {
          showLoopSnackBar(e.message, error: true);
        }
      case AuthPasswordRecovery():
        ref.read(passwordRecoveryProvider.notifier).set(true);
      case AuthSignedOut():
        final user = state.currentUser;
        if (user != null && !user.isGuest) {
          await _storage.saveSession();
          _refresh();
        }
    }
  }

  Future<void> loginAsGuest() async {
    final user = await _accounts.loginAsGuest();
    await _storage.saveSession(userId: user.id);
    _refresh();
  }

  Future<void> adminLogin(String email, String password) async {
    if (!_trade.isAdminLogin(email, password)) {
      throw TradeException(t('Pogrešni admin podaci.'));
    }
    await _storage.saveSession(isAdmin: true);
    _refresh();
  }

  Future<void> logout() async {
    ref.read(homeTabProvider.notifier).select(0);
    final wasGuest = state.currentUser?.isGuest ?? true;
    await _storage.saveSession();
    _refresh();
    if (!wasGuest) {
      try {
        await ref.read(authBackendProvider).signOut();
      } catch (_) {
        // Odjava lokalno uspijeva i bez mreže.
      }
    }
  }

  // ------------------------------------------------------------- račun

  Future<void> requestPasswordReset(String email) =>
      _accounts.requestPasswordReset(email);

  Future<void> resetPasswordLocally(String email, String newPassword) =>
      _accounts.resetPasswordLocally(email, newPassword);

  /// Nova lozinka nakon linka iz e-maila (online).
  Future<void> setRecoveredPassword(String newPassword) async {
    await _accounts.changePassword(email: '', newPassword: newPassword);
    ref.read(passwordRecoveryProvider.notifier).set(false);
  }

  Future<void> changePassword(String oldPassword, String newPassword) =>
      _accounts.changePassword(
        email: _currentEmail,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );

  /// E-mail trenutnog korisnika (online ga daje Supabase Auth).
  String get _currentEmail {
    final user = state.currentUser;
    if (user == null) return '';
    if (user.email.isNotEmpty) return user.email;
    return ref.read(authBackendProvider).isOnline
        ? Supabase.instance.client.auth.currentUser?.email ?? ''
        : '';
  }

  String get currentEmail => _currentEmail;

  Future<void> changeUsername(String username) async {
    await _accounts.changeUsername(_requireUserId(), username);
    _refresh();
  }

  Future<void> updateProfile({
    required String name,
    required String bio,
    required String city,
  }) async {
    await _accounts.updateProfile(
      _requireUserId(),
      name: name,
      bio: bio,
      city: city,
    );
    _refresh();
  }

  /// Nova profilna fotografija iz galerije/kamere (`false` = odustao).
  Future<bool> pickAvatar({bool camera = false}) async {
    final id = _requireUserId();
    final paths = await ref
        .read(imageStoreProvider)
        .pick(camera: camera, limit: 1);
    if (paths.isEmpty) return false;
    final old = await _accounts.setAvatar(id, paths.first);
    if (old != null) await ref.read(imageStoreProvider).delete([old]);
    _refresh();
    return true;
  }

  Future<void> removeAvatar() async {
    final old = await _accounts.setAvatar(_requireUserId(), null);
    if (old != null) await ref.read(imageStoreProvider).delete([old]);
    _refresh();
  }

  // ----------------------------------------------- zajednica i obavijesti

  CommunityService get _community => ref.read(communityServiceProvider);

  Future<void> reviewSeller(
    String deliveryId,
    int stars,
    String comment,
  ) async {
    await _community.review(
      buyerId: _requireUserId(),
      deliveryId: deliveryId,
      stars: stars,
      comment: comment,
    );
    _refresh();
  }

  Future<void> report({
    required String targetType,
    required String targetId,
    required ReportReason reason,
    String note = '',
  }) async {
    await _community.report(
      reporterId: _requireUserId(),
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      note: note,
    );
    _refresh();
  }

  /// Vraća `true` ako je korisnik sada blokiran.
  Future<bool> toggleBlock(String otherId) async {
    final blocked = await _community.toggleBlock(_requireUserId(), otherId);
    _refresh();
    return blocked;
  }

  Future<void> markNotificationsRead({String? id}) async {
    final user = state.currentUser;
    if (user == null) return;
    await _community.markRead(user.id, notificationId: id);
    _refresh();
  }

  /// Admin: zatvori prijavu.
  Future<void> closeReport(String reportId, ReportStatus status) async {
    await _community.closeReport(reportId, status);
    _refresh();
  }

  // --------------------------------------------------- poruke i zamjene

  Future<void> sendMessage(String toId, String text, {String? deviceId}) async {
    await ref
        .read(chatServiceProvider)
        .send(
          senderId: _requireUserId(),
          receiverId: toId,
          text: text,
          deviceId: deviceId,
        );
    _refresh();
  }

  Future<void> markChatRead(String otherId) async {
    final me = state.currentUser;
    if (me == null || me.isGuest) return;
    final hasUnread = state
        .chatWith(otherId)
        .any((m) => m.receiverId == me.id && !m.read);
    if (!hasUnread) return;
    await ref.read(chatServiceProvider).markRead(me.id, otherId);
    _refresh();
  }

  Future<void> offerSwap({
    required String wantedDeviceId,
    required String offeredDeviceId,
    double extraCredits = 0,
    String message = '',
  }) async {
    await ref
        .read(swapServiceProvider)
        .offer(
          fromId: _requireUserId(),
          wantedDeviceId: wantedDeviceId,
          offeredDeviceId: offeredDeviceId,
          extraCredits: extraCredits,
          message: message,
        );
    _refresh();
  }

  Future<void> acceptSwap(String offerId) async {
    try {
      await ref.read(swapServiceProvider).accept(_requireUserId(), offerId);
    } finally {
      _refresh();
    }
  }

  Future<void> declineSwap(String offerId) async {
    await ref.read(swapServiceProvider).decline(_requireUserId(), offerId);
    _refresh();
  }

  Future<void> withdrawSwap(String offerId) async {
    await ref.read(swapServiceProvider).withdraw(_requireUserId(), offerId);
    _refresh();
  }

  // ------------------------------------------------------- brisanje računa

  List<String> get deletionBlockers {
    final id = state.currentUser?.id;
    return id == null ? const [] : _accounts.deletionBlockers(id);
  }

  /// Aukcije bez ponuda se otkazuju (s ponudama blokiraju brisanje).
  Future<void> _cancelOpenAuctions(String userId) async {
    for (final a in state.activeAuctions) {
      if (a.sellerId == userId && a.bids.isEmpty) {
        await _auctions.cancelBySeller(userId, a.id);
      }
    }
  }

  /// Zakaži brisanje (7 dana za predomišljanje) i odjavi se.
  Future<void> requestAccountDeletion(String confirmUsername) async {
    final id = _requireUserId();
    final blockers = _accounts.deletionBlockers(id);
    if (blockers.isNotEmpty) throw TradeException(blockers.join('\n'));
    final user = state.currentUser!;
    if (confirmUsername.trim().replaceFirst('@', '').toLowerCase() !=
        user.username) {
      throw TradeException(
        t('Za potvrdu upiši svoje korisničko ime: {0}', [user.handle]),
      );
    }
    await _cancelOpenAuctions(id);
    await _accounts.requestDeletion(id, confirmUsername: confirmUsername);
    await logout();
  }

  /// Odmah i trajno.
  Future<void> deleteAccountNow(String confirmUsername) async {
    final id = _requireUserId();
    final email = _currentEmail;
    final blockers = _accounts.deletionBlockers(id);
    if (blockers.isNotEmpty) throw TradeException(blockers.join('\n'));
    if (confirmUsername.trim().replaceFirst('@', '').toLowerCase() !=
        state.currentUser!.username) {
      throw TradeException(
        t('Za potvrdu upiši svoje korisničko ime: {0}', [
          state.currentUser!.handle,
        ]),
      );
    }
    await _cancelOpenAuctions(id);
    final images = await _accounts.deleteNow(
      id,
      confirmUsername: confirmUsername,
      email: email,
    );
    await ref.read(imageStoreProvider).delete(images);
    ref.read(homeTabProvider.notifier).select(0);
    await _storage.saveSession();
    _refresh();
  }

  bool _autoListing = false;

  /// Jednokratno objavljuje stare predmete iz portfolija u Marketu.
  /// Online samo kad je veza aktivna i korisnik prijavljen (baza ne
  /// dopušta pisanje gostima).
  Future<void> _autoListPortfolios() async {
    if (!ref.mounted || _autoListing) return;
    final sync = ref.read(syncProvider);
    if (sync != null) {
      final user = state.currentUser;
      if (sync.status != SyncStatus.online || user == null || user.isGuest) {
        return;
      }
    }
    if (!_storage.devices.any((d) => d.ownerId != null && !d.marketChecked)) {
      return;
    }
    _autoListing = true;
    try {
      await _trade.autoListPortfolios();
      if (ref.mounted) _refresh();
    } catch (_) {
      // Pokušat će ponovno pri sljedećem osvježavanju.
    } finally {
      _autoListing = false;
    }
  }

  Future<void> _purgeDeletedAccounts() async {
    if (!ref.mounted) return;
    try {
      final images = await _accounts.purgeExpired();
      if (images.isNotEmpty) await ref.read(imageStoreProvider).delete(images);
      if (ref.mounted) _refresh();
    } catch (_) {
      // Pokušat će ponovno pri sljedećem pokretanju.
    }
  }

  /// Svi podaci trenutnog korisnika kao JSON (izvoz).
  String exportMyData() {
    final id = _requireUserId();
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(_accounts.exportData(id, email: _currentEmail));
  }

  Future<void> verifyEmailDemo() async {
    await _accounts.verifyEmailDemo(_requireUserId());
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
    bool listOnMarket = true,
    PickedFile? file,
  }) async {
    final userId = _requireUserId();
    // Digitalni proizvod: najprije spremi datoteku (put ovisi o ID-u).
    String? id;
    DigitalFile? saved;
    if (category.section == ItemSection.digital) {
      if (file == null) {
        throw TradeException(
          t('Digitalni proizvod treba datoteku koju kupac preuzima.'),
        );
      }
      id = const Uuid().v4();
      saved = await ref.read(fileStoreProvider).save(id, file);
    }
    final Device device;
    try {
      device = await _trade.addDevice(
        id: id,
        file: saved,
        userId: userId,
        name: name,
        model: model,
        condition: condition,
        price: price,
        category: category,
        imagePaths: imagePaths,
        description: description,
        listOnMarket: listOnMarket,
      );
    } catch (_) {
      if (saved != null) await ref.read(fileStoreProvider).delete(saved);
      rethrow;
    }
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
    if (device == null) throw TradeException(t('Predmet ne postoji.'));
    if (device.isDigital) {
      // Bez dostave — datoteka se preuzima odmah.
      final tx = await _trade.buy(userId: userId, deviceId: deviceId);
      _refresh();
      return tx;
    }
    final error = DeliveryService.validate(method, destination);
    if (error != null) throw TradeException(error);
    final total = buyTotal(device.askPrice) + method.cost;
    if (user.credits < total) {
      throw TradeException(
        t('Nemaš dovoljno novca: treba {0} (s feejem i dostavom), imaš {1}.', [
          formatCredits(total),
          formatCredits(user.credits),
        ]),
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
          sellerId: tx.sellerId,
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

  // ---------------------------------------------------- digitalni proizvodi

  /// Preuzima datoteku digitalnog proizvoda (vlasnik ili kupac). Vraća
  /// gdje je spremljena.
  Future<String> downloadFile(String deviceId) async {
    final userId = _requireUserId();
    final d = state.deviceById(deviceId);
    if (d == null || d.file == null) {
      throw TradeException(t('Predmet ne postoji.'));
    }
    if (!_trade.canDownload(userId, deviceId)) {
      throw TradeException(t('Datoteku mogu preuzeti samo kupci.'));
    }
    final bytes = await ref.read(fileStoreProvider).read(d.file!);
    return saveBytesFile(d.file!.name, bytes);
  }

  /// Vlasnik učitava novu verziju datoteke.
  Future<void> replaceFile(String deviceId, PickedFile file) async {
    final userId = _requireUserId();
    final store = ref.read(fileStoreProvider);
    final saved = await store.save(deviceId, file);
    final old = await _trade.replaceFile(userId, deviceId, saved);
    if (old != null) await store.delete(old);
    _refresh();
  }

  /// Objavi vlastiti predmet u Marketu (ili promijeni cijenu).
  Future<void> listOnMarket(String deviceId, double price) async {
    await _trade.list(
      userId: _requireUserId(),
      deviceId: deviceId,
      price: price,
    );
    _refresh();
  }

  Future<void> unlist(String deviceId) async {
    await _trade.unlist(userId: _requireUserId(), deviceId: deviceId);
    _refresh();
  }

  /// Trajno briše vlastiti predmet (i njegove fotografije).
  Future<void> deleteMyDevice(String deviceId) async {
    final images = await _trade.deleteOwn(
      userId: _requireUserId(),
      deviceId: deviceId,
    );
    await ref.read(imageStoreProvider).delete(images);
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
    if (device == null) throw TradeException(t('Predmet ne postoji.'));
    final free = maxImages - device.imagePaths.length;
    if (free <= 0) {
      throw TradeException(
        t('Najviše {0} fotografije po predmetu.', [maxImages]),
      );
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

  Future<void> setLang(AppLang lang) async {
    await _storage.setLang(lang.name);
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
          showLoopSnackBar(
            t('🏆 Osvojio si aukciju: {0} za {1}', [a.deviceName, price]),
          );
        } else if (a.sellerId == me) {
          showLoopSnackBar(
            r.winnerId != null
                ? t('Tvoja aukcija je završila: {0} prodano za {1}', [
                    a.deviceName,
                    price,
                  ])
                : t('Aukcija za {0} je završila bez ponuda', [a.deviceName]),
          );
        } else if (me != null && a.bids.any((b) => b.userId == me)) {
          showLoopSnackBar(
            t('Aukcija {0} je završila — nisi pobijedio', [a.deviceName]),
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
    final user = state.currentUser;
    if (user == null) throw TradeException(t('Nisi prijavljen.'));
    if (user.isGuest) {
      throw TradeException(
        t(
          'Gost može samo razgledavati. Napravi besplatan račun za kupnju i prodaju.',
        ),
      );
    }
    return user.id;
  }
}
