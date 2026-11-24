import 'dart:math';

import '../l10n/tr.dart';
import '../models/app_user.dart';

/// Pravila za korisničko ime.
///
/// - 3–20 znakova: mala slova a–z, brojevi, `_` i `.`
/// - počinje slovom, ne završava točkom, bez `..`
/// - nije rezervirano (admin, loop, support…) ni neprimjereno
/// - jedinstveno bez obzira na velika/mala slova ("Karlo" = "karlo")
///
/// Jedinstvenost u online bazi dodatno jamči tablica `loop_usernames`
/// (primarni ključ), pa ni dva istovremena zahtjeva ne mogu dobiti isto ime.
class UsernameRules {
  static const minLength = 3;
  static const maxLength = 20;

  static final _pattern = RegExp(r'^[a-z][a-z0-9_.]*$');

  static const reserved = {
    'admin',
    'administrator',
    'loop',
    'loopmarket',
    'loop_market',
    'support',
    'podrska',
    'moderator',
    'mod',
    'system',
    'sustav',
    'root',
    'null',
    'undefined',
    'help',
    'pomoc',
    'info',
    'gost',
    'guest',
    'official',
    'staff',
    'team',
    'tim',
    'security',
    'sigurnost',
    'obrisani',
    'deleted',
    'anonymous',
    'anonimno',
    'me',
    'ja',
  };

  /// Neprimjereni dijelovi (provjera "sadrži").
  static const _blocked = [
    'kurac',
    'picka',
    'pička',
    'jebem',
    'jebi',
    'jeben',
    'kurva',
    'peder',
    'govno',
    'sranje',
    'fuck',
    'shit',
    'bitch',
    'cunt',
    'dick',
    'pussy',
    'nigger',
    'nigga',
    'whore',
    'slut',
    'nazi',
    'hitler',
  ];

  /// Normalizira unos: bez razmaka i `@`, mala slova.
  static String normalize(String input) =>
      input.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();

  /// Greška formata ili `null` ako je ime ispravno (ne provjerava zauzetost).
  static String? validate(String input) {
    final u = normalize(input);
    if (u.isEmpty) return t('Upiši korisničko ime.');
    if (u.length < minLength || u.length > maxLength) {
      return t('Korisničko ime mora imati {0}–{1} znakova.', [
        minLength,
        maxLength,
      ]);
    }
    if (!RegExp(r'^[a-z]').hasMatch(u)) {
      return t('Korisničko ime mora počinjati slovom.');
    }
    if (!_pattern.hasMatch(u)) {
      return t('Dopuštena su samo slova a–z, brojevi, _ i točka.');
    }
    if (u.contains('..') || u.endsWith('.')) {
      return t('Točka ne smije biti na kraju ni dvaput zaredom.');
    }
    if (reserved.contains(u)) return t('Ovo korisničko ime je rezervirano.');
    if (_blocked.any(u.contains)) {
      return t('Ovo korisničko ime nije dopušteno.');
    }
    return null;
  }

  /// Je li ime zauzeto: trenutno ime nekog korisnika ili nedavno
  /// promijenjeno ime (zaključano [AppUser.usernameLockDays] dana).
  static bool isTaken(
    String input,
    Iterable<AppUser> users, {
    String? exceptUserId,
    DateTime? now,
  }) {
    final u = normalize(input);
    final at = now ?? DateTime.now();
    for (final user in users) {
      if (user.id == exceptUserId) continue;
      if (user.username.toLowerCase() == u) return true;
      final changed = user.usernameChangedAt;
      if (user.formerUsername?.toLowerCase() == u &&
          changed != null &&
          at.difference(changed).inDays < AppUser.usernameLockDays) {
        return true;
      }
    }
    return false;
  }

  /// Osnova za ime iz e-maila ili imena: "Karlo Šimić" → "karlo.simic".
  static String baseFrom(String source) {
    const map = {'č': 'c', 'ć': 'c', 'š': 's', 'ž': 'z', 'đ': 'd'};
    var s = source.split('@').first.toLowerCase();
    s = s.split('').map((c) => map[c] ?? c).join();
    s = s.replaceAll(RegExp(r'[\s\-]+'), '.');
    s = s.replaceAll(RegExp(r'[^a-z0-9_.]'), '');
    s = s.replaceAll(RegExp(r'\.{2,}'), '.');
    s = s.replaceAll(RegExp(r'^[^a-z]+'), '');
    s = s.replaceAll(RegExp(r'\.+$'), '');
    if (s.length > 14) s = s.substring(0, 14);
    if (s.length < minLength) s = 'loop${s.isEmpty ? '' : '_$s'}er';
    return s;
  }

  /// Slobodna imena slična [wanted] (za "zauzeto — probaj…").
  static List<String> suggestions(
    String wanted,
    Iterable<AppUser> users, {
    int count = 3,
    Random? random,
    DateTime? now,
  }) {
    final rnd = random ?? Random();
    final base = baseFrom(wanted);
    final year = (now ?? DateTime.now()).year;
    final candidates = <String>[
      '${base}_${10 + rnd.nextInt(90)}',
      '$base.hr',
      '$base$year',
      '${base}_loop',
      '$base.${100 + rnd.nextInt(900)}',
      'the.$base',
    ];
    final out = <String>[];
    for (final c in candidates) {
      if (out.length >= count) break;
      final name = c.length > maxLength ? c.substring(0, maxLength) : c;
      if (validate(name) == null && !isTaken(name, users, now: now)) {
        out.add(name);
      }
    }
    return out;
  }

  /// Prvo slobodno ime iz [source] (za starije račune bez imena).
  static String firstFree(String source, Iterable<AppUser> users) {
    var base = baseFrom(source);
    if (validate(base) == null && !isTaken(base, users)) return base;
    // Neprimjerena osnova ostaje neprimjerena i s brojem.
    if (validate('${base}2') != null) base = 'loopuser';
    if (validate(base) == null && !isTaken(base, users)) return base;
    for (var i = 2; ; i++) {
      final name = '${base.length > 16 ? base.substring(0, 16) : base}$i';
      if (validate(name) == null && !isTaken(name, users)) return name;
    }
  }
}
