import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../l10n/tr.dart';
import 'storage_service.dart';
import 'trade_service.dart';

/// Prijavljeni identitet (od lokalne pohrane ili Supabase Autha).
class AuthIdentity {
  const AuthIdentity({
    required this.uid,
    required this.email,
    this.provider = 'email',
    this.verified = false,
    this.username,
    this.referral,
    this.name,
  });

  final String uid;
  final String email;

  /// 'email' | 'google'.
  final String provider;
  final bool verified;

  /// Korisničko ime upisano pri registraciji (Supabase ga čuva dok se
  /// e-mail ne potvrdi).
  final String? username;
  final String? referral;

  /// Ime iz Google računa.
  final String? name;

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'email': email,
    'provider': provider,
    'verified': verified,
    'username': username,
    'referral': referral,
    'name': name,
  };

  factory AuthIdentity.fromMap(Map<dynamic, dynamic> m) => AuthIdentity(
    uid: m['uid'] as String,
    email: m['email'] as String? ?? '',
    provider: m['provider'] as String? ?? 'email',
    verified: m['verified'] as bool? ?? false,
    username: m['username'] as String?,
    referral: m['referral'] as String?,
    name: m['name'] as String?,
  );
}

/// Događaji prijave koji ne dolaze iz aplikacije (povratak s Google
/// prijave, link za novu lozinku, istek sesije).
sealed class AuthEvent {
  const AuthEvent();
}

class AuthSignedIn extends AuthEvent {
  const AuthSignedIn(this.identity);
  final AuthIdentity identity;
}

class AuthPasswordRecovery extends AuthEvent {
  const AuthPasswordRecovery();
}

class AuthSignedOut extends AuthEvent {
  const AuthSignedOut();
}

/// Prijava i registracija. Lokalno ([LocalAuthBackend]) ili preko
/// Supabase Autha ([SupabaseAuthBackend]) kad je postavljena online baza.
abstract class AuthBackend {
  bool get isOnline;

  /// Google prijava (samo online, na webu).
  bool get supportsGoogle;

  /// Novi račun. Vraća `null` ako treba potvrditi e-mail prije prijave.
  Future<AuthIdentity?> signUp({
    required String email,
    required String password,
    required String username,
    String? referral,
  });

  Future<AuthIdentity> signIn(String email, String password);

  Future<void> signOut();

  /// Šalje e-mail s linkom za novu lozinku.
  Future<void> sendPasswordReset(String email);

  /// Nova lozinka. Lokalno traži staru (osim nakon resetiranja).
  Future<void> updatePassword({
    required String email,
    required String newPassword,
    String? oldPassword,
  });

  Future<void> signInWithGoogle();

  /// Rezervira korisničko ime (online: tablica `loop_usernames`, gdje je
  /// ime primarni ključ). Vraća `false` ako ga je netko već uzeo.
  /// [release] je staro ime koje se oslobađa.
  Future<bool> claimUsername(String uid, String username, {String? release});

  /// Online provjera zauzetosti (lokalno uvijek `true`; lokalnu provjeru
  /// radi `UsernameRules.isTaken`).
  Future<bool> isUsernameFree(String username);

  /// Trajno briše račun za prijavu (podatke profila briše aplikacija).
  Future<void> deleteAccount({required String email, String? uid});

  Stream<AuthEvent> get events;
}

// ---------------------------------------------------------------- lokalno

/// Lokalni računi: lozinke su spremljene samo na ovom uređaju, kao
/// sažetak (SHA-256, sol, 2000 ponavljanja), u boxu koji se ne
/// sinkronizira.
class LocalAuthBackend implements AuthBackend {
  LocalAuthBackend(this._storage);

  final StorageService _storage;
  final _uuid = const Uuid();
  final _random = Random.secure();

  static const minPassword = 6;

  static String hash(String password, String salt) {
    List<int> digest = utf8.encode('$salt:$password');
    for (var i = 0; i < 2000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return base64Encode(digest);
  }

  String _salt() =>
      base64Encode(List.generate(16, (_) => _random.nextInt(256)));

  Map<String, dynamic> _credential(String userId, String password) {
    final salt = _salt();
    return {'userId': userId, 'salt': salt, 'hash': hash(password, salt)};
  }

  @override
  bool get isOnline => false;

  @override
  bool get supportsGoogle => false;

  @override
  Stream<AuthEvent> get events => const Stream.empty();

  @override
  Future<AuthIdentity?> signUp({
    required String email,
    required String password,
    required String username,
    String? referral,
  }) async {
    final e = email.trim().toLowerCase();
    if (_storage.credentialFor(e) != null || _storage.userByEmail(e) != null) {
      throw TradeException(t('Račun s ovim e-mailom već postoji. Prijavi se.'));
    }
    final uid = _uuid.v4();
    await _storage.putCredential(e, _credential(uid, password));
    return AuthIdentity(
      uid: uid,
      email: e,
      username: username,
      referral: referral,
    );
  }

  @override
  Future<AuthIdentity> signIn(String email, String password) async {
    final e = email.trim().toLowerCase();
    final cred = _storage.credentialFor(e);
    final user = _storage.userByEmail(e);
    if (cred == null) {
      if (user == null || user.isGuest) {
        throw TradeException(
          t('Ne postoji račun s tim e-mailom. Registriraj se.'),
        );
      }
      // Račun iz starije verzije (bez lozinke): prva lozinka postaje
      // njegova lozinka.
      await _storage.putCredential(e, _credential(user.id, password));
      return AuthIdentity(uid: user.id, email: e, verified: user.emailVerified);
    }
    if (hash(password, cred['salt'] as String) != cred['hash']) {
      throw TradeException(t('Pogrešan e-mail ili lozinka.'));
    }
    return AuthIdentity(
      uid: cred['userId'] as String,
      email: e,
      verified: user?.emailVerified ?? false,
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> sendPasswordReset(String email) async {
    throw TradeException(
      t('Lokalni način rada nema slanje e-maila — postavi novu lozinku ovdje.'),
    );
  }

  @override
  Future<void> updatePassword({
    required String email,
    required String newPassword,
    String? oldPassword,
  }) async {
    final e = email.trim().toLowerCase();
    final cred = _storage.credentialFor(e);
    final user = _storage.userByEmail(e);
    final userId = cred?['userId'] as String? ?? user?.id;
    if (userId == null) {
      throw TradeException(
        t('Ne postoji račun s tim e-mailom. Registriraj se.'),
      );
    }
    if (oldPassword != null &&
        cred != null &&
        hash(oldPassword, cred['salt'] as String) != cred['hash']) {
      throw TradeException(t('Trenutna lozinka nije točna.'));
    }
    await _storage.putCredential(e, _credential(userId, newPassword));
  }

  @override
  Future<void> signInWithGoogle() async {
    throw TradeException(t('Google prijava radi na web linku s online bazom.'));
  }

  @override
  Future<bool> claimUsername(
    String uid,
    String username, {
    String? release,
  }) async => true;

  @override
  Future<bool> isUsernameFree(String username) async => true;

  @override
  Future<void> deleteAccount({required String email, String? uid}) =>
      _storage.deleteCredential(email.trim().toLowerCase());
}

// ---------------------------------------------------------------- online

/// Supabase Auth: e-mail + lozinka, potvrda e-maila, reset lozinke i
/// Google prijava. Lozinke nikad ne prolaze kroz našu bazu.
class SupabaseAuthBackend implements AuthBackend {
  SupabaseAuthBackend(this._client);

  final SupabaseClient _client;
  GoTrueClient get _auth => _client.auth;

  /// Adresa na koju se vraća nakon potvrde e-maila, Google prijave ili
  /// linka za novu lozinku (web: trenutna stranica, npr.
  /// https://karlo6546541.github.io/bot/).
  static String? get redirectUrl =>
      kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : null;

  @override
  bool get isOnline => true;

  @override
  bool get supportsGoogle => kIsWeb;

  static AuthIdentity identityOf(User u) {
    final meta = u.userMetadata ?? const {};
    final provider = u.appMetadata['provider'] as String? ?? 'email';
    return AuthIdentity(
      uid: u.id,
      email: u.email ?? '',
      provider: provider,
      verified: u.emailConfirmedAt != null || provider == 'google',
      username: meta['username'] as String?,
      referral: meta['referral'] as String?,
      name: (meta['full_name'] ?? meta['name']) as String?,
    );
  }

  /// Supabase poruke → razumljive poruke na jeziku aplikacije.
  static TradeException _friendly(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) {
      return TradeException(t('Pogrešan e-mail ili lozinka.'));
    }
    if (m.contains('not confirmed')) {
      return TradeException(
        t('Prvo potvrdi e-mail (link je u tvom inboxu), pa se prijavi.'),
      );
    }
    if (m.contains('already registered') || m.contains('already exists')) {
      return TradeException(
        t('Račun s ovim e-mailom već postoji. Prijavi se.'),
      );
    }
    if (m.contains('rate limit') || e.statusCode == '429') {
      return TradeException(
        t('Previše pokušaja. Pričekaj malo pa pokušaj ponovno.'),
      );
    }
    if (m.contains('password')) {
      return TradeException(t('Lozinka nije prihvaćena: {0}', [e.message]));
    }
    return TradeException(t('Greška: {0}', [e.message]));
  }

  Future<T> _wrap<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on AuthException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Stream<AuthEvent> get events => _auth.onAuthStateChange
      .map<AuthEvent?>((s) {
        switch (s.event) {
          case AuthChangeEvent.passwordRecovery:
            return const AuthPasswordRecovery();
          case AuthChangeEvent.signedOut:
            return const AuthSignedOut();
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.initialSession:
          case AuthChangeEvent.userUpdated:
            final u = s.session?.user;
            return u == null ? null : AuthSignedIn(identityOf(u));
          default:
            return null;
        }
      })
      .where((e) => e != null)
      .cast<AuthEvent>();

  @override
  Future<AuthIdentity?> signUp({
    required String email,
    required String password,
    required String username,
    String? referral,
  }) => _wrap(() async {
    final res = await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {'username': username, 'referral': ?referral},
      emailRedirectTo: redirectUrl,
    );
    final user = res.user;
    // Supabase za postojeći e-mail (kad je potvrda uključena) vraća
    // "lažni" uspjeh bez identiteta.
    if (user != null && (user.identities?.isEmpty ?? false)) {
      throw TradeException(t('Račun s ovim e-mailom već postoji. Prijavi se.'));
    }
    if (res.session == null || user == null) return null;
    return identityOf(user);
  });

  @override
  Future<AuthIdentity> signIn(String email, String password) => _wrap(() async {
    final res = await _auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    return identityOf(res.user!);
  });

  @override
  Future<void> signOut() => _wrap(() => _auth.signOut());

  @override
  Future<void> sendPasswordReset(String email) => _wrap(
    () => _auth.resetPasswordForEmail(email.trim(), redirectTo: redirectUrl),
  );

  @override
  Future<void> updatePassword({
    required String email,
    required String newPassword,
    String? oldPassword,
  }) => _wrap(() async {
    if (oldPassword != null) {
      // Provjera trenutne lozinke prije promjene.
      await _auth.signInWithPassword(email: email, password: oldPassword);
    }
    await _auth.updateUser(UserAttributes(password: newPassword));
  });

  @override
  Future<void> signInWithGoogle() => _wrap(() async {
    await _auth.signInWithOAuth(OAuthProvider.google, redirectTo: redirectUrl);
  });

  @override
  Future<bool> claimUsername(
    String uid,
    String username, {
    String? release,
  }) async {
    try {
      await _client.from('loop_usernames').insert({
        'username': username,
        'user_id': uid,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return false; // već postoji
      // Tablica još nije napravljena (SQL nije pokrenut) — oslanjamo se
      // na provjeru u aplikaciji.
      if (_missingTable(e)) return true;
      rethrow;
    }
    if (release != null && release != username) {
      await _client
          .from('loop_usernames')
          .delete()
          .eq('username', release)
          .eq('user_id', uid);
    }
    return true;
  }

  @override
  Future<bool> isUsernameFree(String username) async {
    try {
      final rows = await _client
          .from('loop_usernames')
          .select('username')
          .eq('username', username)
          .limit(1);
      return rows.isEmpty;
    } on PostgrestException catch (e) {
      if (_missingTable(e)) return true;
      rethrow;
    }
  }

  static bool _missingTable(PostgrestException e) =>
      e.code == '42P01' ||
      e.code == 'PGRST205' ||
      e.code == 'PGRST202' ||
      e.message.contains('does not exist') ||
      e.message.contains('Could not find');

  @override
  Future<void> deleteAccount({required String email, String? uid}) async {
    // Funkcija u bazi briše prijavljenog korisnika iz auth.users
    // (vidi supabase/schema.sql).
    try {
      await _client.rpc('loop_delete_me');
    } on PostgrestException catch (e) {
      if (_missingTable(e)) {
        throw TradeException(
          t(
            'Brisanje računa u bazi nije postavljeno (pokreni supabase/schema.sql).',
          ),
        );
      }
      rethrow;
    }
    await _auth.signOut();
  }
}
