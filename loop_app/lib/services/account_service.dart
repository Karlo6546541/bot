import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../utils/formatters.dart';
import '../models/app_notification.dart';
import 'auth_backend.dart';
import 'inbox.dart';
import 'live_service.dart';
import 'storage_service.dart';
import 'trade_service.dart';
import 'username_rules.dart';

/// Ishod prijave/registracije.
sealed class SignInResult {
  const SignInResult();
}

/// Prijavljen, profil postoji.
class SignedIn extends SignInResult {
  const SignedIn(this.user, {this.restored = false});
  final AppUser user;

  /// Račun je bio zakazan za brisanje — prijava ga je vratila.
  final bool restored;
}

/// Treba odabrati korisničko ime (npr. prva Google prijava).
class NeedsUsername extends SignInResult {
  const NeedsUsername(this.identity);
  final AuthIdentity identity;
}

/// Registracija poslana — treba potvrditi e-mail.
class NeedsEmailConfirmation extends SignInResult {
  const NeedsEmailConfirmation(this.email);
  final String email;
}

/// Računi: registracija, prijava, korisničko ime i profil.
class AccountService {
  AccountService(this._storage, this.backend);

  final StorageService _storage;
  final AuthBackend backend;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static const minPassword = LocalAuthBackend.minPassword;
  static const maxName = 40;

  static String? validateEmail(String email) =>
      _emailPattern.hasMatch(email.trim()) ? null : t('Unesi ispravan e-mail.');

  static String? validatePassword(String password) =>
      password.length < minPassword
      ? t('Lozinka mora imati barem {0} znakova.', [minPassword])
      : null;

  // ------------------------------------------------------------ registracija

  Future<SignInResult> register({
    required String email,
    required String password,
    required String username,
    String referral = '',
  }) async {
    final emailError = validateEmail(email);
    if (emailError != null) throw TradeException(emailError);
    final passError = validatePassword(password);
    if (passError != null) throw TradeException(passError);
    if (email.trim().toLowerCase() == TradeService.adminEmail) {
      throw TradeException(t('Za admin račun koristi "Admin prijava".'));
    }
    final name = await _checkUsername(username);
    final ref = referral.trim();
    if (ref.isNotEmpty && _storage.userByUsername(ref) == null) {
      throw TradeException(t('Kod za poziv "{0}" ne postoji.', [ref]));
    }

    final identity = await backend.signUp(
      email: email,
      password: password,
      username: name,
      referral: ref.isEmpty ? null : UsernameRules.normalize(ref),
    );
    if (identity == null) {
      return NeedsEmailConfirmation(email.trim());
    }
    return completeSignIn(identity);
  }

  /// Provjerava format i zauzetost; vraća normalizirano ime.
  Future<String> _checkUsername(String input, {String? exceptUserId}) async {
    final error = UsernameRules.validate(input);
    if (error != null) throw TradeException(error);
    final name = UsernameRules.normalize(input);
    if (UsernameRules.isTaken(
          name,
          _storage.users,
          exceptUserId: exceptUserId,
        ) ||
        !await backend.isUsernameFree(name, uid: exceptUserId)) {
      throw UsernameTakenException(
        name,
        UsernameRules.suggestions(name, _storage.users),
      );
    }
    return name;
  }

  /// Je li ime slobodno (za provjeru dok korisnik tipka).
  Future<UsernameCheck> checkUsername(
    String input, {
    String? exceptUserId,
  }) async {
    final error = UsernameRules.validate(input);
    if (error != null) return UsernameCheck.invalid(error);
    final name = UsernameRules.normalize(input);
    var free = !UsernameRules.isTaken(
      name,
      _storage.users,
      exceptUserId: exceptUserId,
    );
    if (free) {
      try {
        free = await backend.isUsernameFree(name, uid: exceptUserId);
      } catch (_) {
        // Bez mreže: oslanjamo se na lokalnu provjeru.
      }
    }
    return free
        ? UsernameCheck.free(name)
        : UsernameCheck.taken(
            name,
            UsernameRules.suggestions(name, _storage.users),
          );
  }

  // ------------------------------------------------------------------ prijava

  /// Prijava e-mailom ili (lokalno) korisničkim imenom.
  Future<SignInResult> login(String identifier, String password) async {
    final id = identifier.trim();
    if (id.isEmpty) throw TradeException(t('Upiši e-mail ili korisničko ime.'));
    if (password.isEmpty) throw TradeException(t('Unesi lozinku.'));
    var email = id;
    if (!id.contains('@') || id.startsWith('@')) {
      if (backend.isOnline) {
        throw TradeException(t('Za prijavu upiši e-mail.'));
      }
      final user = _storage.userByUsername(id);
      if (user == null) {
        throw TradeException(
          t('Ne postoji korisnik @{0}.', [UsernameRules.normalize(id)]),
        );
      }
      email = user.email;
    }
    if (email.toLowerCase() == TradeService.adminEmail) {
      throw TradeException(t('Za admin račun koristi "Admin prijava".'));
    }
    final identity = await backend.signIn(email, password);
    return completeSignIn(identity);
  }

  /// Nakon uspješne prijave: pronađi ili napravi profil.
  Future<SignInResult> completeSignIn(AuthIdentity identity) async {
    final existing = _storage.userById(identity.uid);
    if (existing != null) {
      var user = existing;
      final restored = user.pendingDeletion;
      if (restored || (identity.verified && !user.emailVerified)) {
        user = user.copyWith(
          clearDeletion: true,
          emailVerified: user.emailVerified || identity.verified,
        );
        await _storage.putUser(user);
      }
      await _storage.setPendingAuth(null);
      return SignedIn(user, restored: restored);
    }
    final wanted = identity.username;
    if (wanted != null && UsernameRules.validate(wanted) == null) {
      try {
        final user = await createProfile(identity, wanted);
        return SignedIn(user);
      } on UsernameTakenException {
        // Ime je u međuvremenu zauzeto — korisnik bira novo.
      }
    }
    await _storage.setPendingAuth(identity.toMap());
    return NeedsUsername(identity);
  }

  /// Novi profil s odabranim korisničkim imenom.
  Future<AppUser> createProfile(AuthIdentity identity, String username) async {
    final name = await _checkUsername(username, exceptUserId: identity.uid);
    if (!await backend.claimUsername(identity.uid, name)) {
      throw UsernameTakenException(
        name,
        UsernameRules.suggestions(name, _storage.users),
      );
    }
    final referrer = identity.referral == null
        ? null
        : _storage.userByUsername(identity.referral!);
    final user = AppUser(
      id: identity.uid,
      // Online se e-mail ne sprema u javni profil.
      email: backend.isOnline ? '' : identity.email.toLowerCase(),
      name: identity.name ?? '',
      username: name,
      credits: TradeService.welcomeCredits.toDouble(),
      emailVerified: identity.verified,
      authProvider: identity.provider,
      referredBy: referrer?.id,
      createdAt: DateTime.now(),
    );
    await _storage.putUser(user);
    await _storage.recordSnapshot(user.id);
    if (referrer != null) {
      // Poziv se samo bilježi — nema novčanog bonusa.
      await Inbox(_storage).send(
        referrer.id,
        NotificationKind.referral,
        args: [user.handle],
        targetId: user.id,
      );
    }
    await _storage.setPendingAuth(null);
    return user;
  }

  /// Prijava koja čeka odabir korisničkog imena.
  AuthIdentity? get pendingIdentity {
    final m = _storage.pendingAuth;
    return m == null ? null : AuthIdentity.fromMap(m);
  }

  Future<void> cancelPending() => _storage.setPendingAuth(null);

  Future<AppUser> loginAsGuest() async {
    final existing = _storage.userById(guestId);
    if (existing != null) return existing;
    final guest = AppUser(
      id: guestId,
      email: TradeService.guestEmail,
      name: t('Gost'),
      username: '',
      credits: 0,
      isGuest: true,
      authProvider: 'guest',
      createdAt: DateTime.now(),
    );
    await _storage.putUser(guest);
    return guest;
  }

  static const guestId = 'user-guest';

  // ---------------------------------------------------------------- lozinka

  Future<void> requestPasswordReset(String email) async {
    final error = validateEmail(email);
    if (error != null) throw TradeException(error);
    await backend.sendPasswordReset(email);
  }

  /// Lokalno: nova lozinka bez e-maila (podaci su samo na ovom uređaju).
  Future<void> resetPasswordLocally(String email, String newPassword) async {
    final error = validatePassword(newPassword);
    if (error != null) throw TradeException(error);
    await backend.updatePassword(email: email, newPassword: newPassword);
  }

  Future<void> changePassword({
    required String email,
    required String newPassword,
    String? oldPassword,
  }) async {
    final error = validatePassword(newPassword);
    if (error != null) throw TradeException(error);
    await backend.updatePassword(
      email: email,
      newPassword: newPassword,
      oldPassword: oldPassword,
    );
  }

  // ------------------------------------------------------------------ profil

  Future<AppUser> changeUsername(
    String userId,
    String input, {
    DateTime? now,
  }) async {
    final user = _require(userId);
    final at = now ?? DateTime.now();
    final normalized = UsernameRules.normalize(input);
    if (normalized == user.username) return user;
    final next = user.nextUsernameChange;
    if (next != null && at.isBefore(next)) {
      throw TradeException(
        t('Korisničko ime možeš ponovno promijeniti {0}.', [
          formatDateTime(next),
        ]),
      );
    }
    final name = await _checkUsername(input, exceptUserId: userId);
    if (!await backend.claimUsername(userId, name, release: user.username)) {
      throw UsernameTakenException(
        name,
        UsernameRules.suggestions(name, _storage.users),
      );
    }
    final updated = user.copyWith(
      username: name,
      formerUsername: user.username,
      usernameChangedAt: at,
    );
    await _storage.putUser(updated);
    return updated;
  }

  Future<AppUser> updateProfile(
    String userId, {
    required String name,
    required String bio,
    required String city,
  }) async {
    final user = _require(userId);
    if (name.trim().length > maxName) {
      throw TradeException(t('Ime može imati najviše {0} znakova.', [maxName]));
    }
    if (bio.trim().length > AppUser.maxBio) {
      throw TradeException(
        t('Opis profila može imati najviše {0} znakova.', [AppUser.maxBio]),
      );
    }
    final updated = user.copyWith(
      name: name.trim(),
      bio: bio.trim(),
      city: city.trim(),
    );
    await _storage.putUser(updated);
    return updated;
  }

  Future<String?> setAvatar(String userId, String? path) async {
    final user = _require(userId);
    await _storage.putUser(
      user.copyWith(avatarPath: path, clearAvatar: path == null),
    );
    return user.avatarPath;
  }

  /// Naslovna slika trgovine (`null` uklanja). Vraća staru putanju.
  Future<String?> setCover(String userId, String? path) async {
    final user = _require(userId);
    await _storage.putUser(
      user.copyWith(coverPath: path, clearCover: path == null),
    );
    return user.coverPath;
  }

  /// Demo (lokalno): potvrda e-maila bez stvarnog e-maila.
  Future<void> verifyEmailDemo(String userId) async {
    final user = _require(userId);
    await _storage.putUser(user.copyWith(emailVerified: true));
  }

  // --------------------------------------------------------- brisanje računa

  /// Razlozi zbog kojih se račun još ne može obrisati (prazno = može).
  /// Ponude su obvezujuće, a pošiljke moraju završiti.
  List<String> deletionBlockers(String userId) {
    final out = <String>[];
    for (final a in _storage.auctions.where((a) => a.isActive)) {
      if (a.sellerId == userId && a.bids.isNotEmpty) {
        out.add(t('Aukcija s ponudama: {0}', [a.deviceName]));
      } else if (a.highestBid?.userId == userId) {
        out.add(
          t('Vodiš na aukciji: {0} (ponuda je obvezujuća)', [a.deviceName]),
        );
      }
    }
    for (final d in _storage.deliveries.where((d) => d.confirmedAt == null)) {
      if (d.buyerId == userId) {
        out.add(t('Pošiljka u tijeku: {0}', [d.deviceName]));
      } else if (d.sellerId == userId) {
        out.add(t('Prodani predmet još nije isporučen: {0}', [d.deviceName]));
      }
    }
    return out;
  }

  /// Zakazuje brisanje: račun se skriva odmah, a briše nakon
  /// [AppUser.deletionGraceDays] dana. Prijava u tom roku ga vraća.
  /// Aukcije bez ponuda treba otkazati prije poziva (radi kontroler).
  Future<void> requestDeletion(
    String userId, {
    required String confirmUsername,
    DateTime? now,
  }) async {
    final user = _require(userId);
    if (UsernameRules.normalize(confirmUsername) != user.username) {
      throw TradeException(
        t('Za potvrdu upiši svoje korisničko ime: {0}', [user.handle]),
      );
    }
    final blockers = deletionBlockers(userId);
    if (blockers.isNotEmpty) throw TradeException(blockers.join('\n'));
    // Objave nestaju iz Marketa.
    for (final d in _storage.devices.where(
      (d) => d.ownerId == userId && d.isListed,
    )) {
      await _storage.putDevice(d.withListing(null));
    }
    await _storage.putUser(
      user.copyWith(deletionRequestedAt: now ?? DateTime.now()),
    );
  }

  /// Trajno briše račune kojima je istekao rok. Vraća putanje fotografija
  /// za brisanje.
  Future<List<String>> purgeExpired({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final expired = [
      for (final u in _storage.users)
        if (u.deletionRequestedAt != null &&
            at.difference(u.deletionRequestedAt!).inDays >=
                AppUser.deletionGraceDays)
          u,
    ];
    if (expired.isEmpty) return const [];
    // Najprije računi za prijavu (baza ih pronalazi preko profila), pa
    // tek onda profili.
    await backend.purgeDeleted();
    final images = <String>[];
    for (final u in expired) {
      images.addAll(await _erase(u));
    }
    return images;
  }

  /// Odmah i bez povratka (korisnik je prijavljen). Vraća putanje
  /// fotografija za brisanje.
  Future<List<String>> deleteNow(
    String userId, {
    required String confirmUsername,
    required String email,
  }) async {
    final user = _require(userId);
    if (UsernameRules.normalize(confirmUsername) != user.username) {
      throw TradeException(
        t('Za potvrdu upiši svoje korisničko ime: {0}', [user.handle]),
      );
    }
    final blockers = deletionBlockers(userId);
    if (blockers.isNotEmpty) throw TradeException(blockers.join('\n'));
    await backend.deleteAccount(email: email, uid: userId);
    return _erase(user);
  }

  /// Briše profil, predmete, povijest i lozinku; u transakcijama ime
  /// postaje "@obrisani" (drugima povijest ostaje).
  Future<List<String>> _erase(AppUser user) async {
    final images = <String>[?user.avatarPath, ?user.coverPath];
    for (final d in _storage.devices.where((d) => d.ownerId == user.id)) {
      if (_storage.activeAuctionFor(d.id) != null ||
          LiveService.isLocked(_storage, d.id)) {
        continue;
      }
      images.addAll(d.imagePaths);
      await _storage.deleteDevice(d.id);
    }
    for (final tx in _storage.transactions) {
      if (tx.buyerId == user.id || tx.sellerId == user.id) {
        await _storage.putTransaction(tx.anonymize(user.id, deletedLabel));
      }
    }
    await _storage.deleteHistory(user.id);
    if (user.email.isNotEmpty) await _storage.deleteCredential(user.email);
    await _storage.deleteUser(user.id);
    return images;
  }

  static const deletedLabel = '@obrisani';

  /// Svi podaci korisnika (GDPR izvoz) — bez lozinki.
  Map<String, dynamic> exportData(String userId, {String? email}) {
    final user = _require(userId);
    final profile = user.toMap();
    if (email != null && email.isNotEmpty) profile['email'] = email;
    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'app': 'Subhasto',
      'profile': profile,
      'items': [
        for (final d in _storage.devices.where((d) => d.ownerId == userId))
          d.toMap(),
      ],
      'transactions': [
        for (final tx in _storage.transactions.where(
          (tx) =>
              tx.userId == userId ||
              tx.buyerId == userId ||
              tx.sellerId == userId,
        ))
          tx.toMap(),
      ],
      'deliveries': [
        for (final d in _storage.deliveries.where(
          (d) => d.buyerId == userId || d.sellerId == userId,
        ))
          d.toMap(),
      ],
      'auctions': [
        for (final a in _storage.auctions.where(
          (a) => a.sellerId == userId || a.bids.any((b) => b.userId == userId),
        ))
          a.toMap(),
      ],
      'portfolioHistory': [
        for (final p in _storage.historyOf(userId)) p.toMap(),
      ],
    };
  }

  AppUser _require(String id) {
    final user = _storage.userById(id);
    if (user == null) throw TradeException(t('Korisnik ne postoji.'));
    return user;
  }
}

/// Korisničko ime je zauzeto; [suggestions] su slobodne alternative.
class UsernameTakenException extends TradeException {
  UsernameTakenException(String name, this.suggestions)
    : super(t('@{0} je zauzeto.', [name]));
  final List<String> suggestions;
}

/// Rezultat provjere korisničkog imena dok korisnik tipka.
class UsernameCheck {
  const UsernameCheck._(this.name, this.error, this.free, this.suggestions);

  const UsernameCheck.invalid(String error)
    : this._(null, error, false, const []);
  const UsernameCheck.free(String name) : this._(name, null, true, const []);
  const UsernameCheck.taken(String name, List<String> suggestions)
    : this._(name, null, false, suggestions);

  final String? name;
  final String? error;
  final bool free;
  final List<String> suggestions;
}
