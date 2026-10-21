import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/l10n/en.dart';

/// Svaki tekst u kodu (`t('...')`) mora imati engleski prijevod, s istim
/// mjestima za vrijednosti ({0}, {1}…).
void main() {
  // t('...') s jednim ili više spojenih literala (kod koristi ' navodnike).
  final call = RegExp(r"\bt\(\s*((?:'(?:[^'\\]|\\.)*'\s*)+)");
  final literal = RegExp(r"'((?:[^'\\]|\\.)*)'");

  String unescape(String s) => s
      .replaceAll(r"\'", "'")
      .replaceAll(r'\"', '"')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\$', r'$')
      .replaceAll(r'\\', r'\');

  Set<String> keysInCode() {
    final keys = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('l10n')) continue;
      final src = f.readAsStringSync();
      for (final m in call.allMatches(src)) {
        final parts = literal
            .allMatches(m.group(1)!)
            .map((l) => unescape(l.group(1)!));
        keys.add(parts.join());
      }
    }
    return keys;
  }

  test('svi tekstovi imaju engleski prijevod', () {
    final keys = keysInCode()..remove('...');
    expect(keys.length, greaterThan(300));
    final missing = keys.where((k) => !kEn.containsKey(k)).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason: 'Nedostaju prijevodi:\n${missing.join('\n')}',
    );
  });

  test('prijevodi imaju ista mjesta za vrijednosti', () {
    final ph = RegExp(r'\{\d+\}');
    Set<String> of(String s) => ph.allMatches(s).map((m) => m[0]!).toSet();
    final wrong = [
      for (final e in kEn.entries)
        if (!setEquals(of(e.key), of(e.value))) e.key,
    ];
    expect(wrong, isEmpty);
  });
}

bool setEquals<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
