import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/l10n/en.dart';
import 'package:loop_app/l10n/tr.dart';
import 'package:loop_app/models/app_notification.dart';
import 'package:loop_app/models/auction.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/models/report.dart';
import 'package:loop_app/models/swap_offer.dart';
import 'package:loop_app/screens/auctions_screen.dart';
import 'package:loop_app/screens/market_screen.dart';
import 'package:loop_app/widgets/portfolio_chart.dart';

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

  test('tekstovi u enumima (kategorije, statusi, obavijesti…)', () {
    Tr.lang = AppLang.en;
    Tr.missing.clear();
    final texts = [
      for (final v in ItemSection.values) v.label,
      for (final v in DeviceCategory.values) ...[v.label, v.singular],
      for (final v in DeviceCondition.values) v.label,
      for (final v in TransactionType.values) v.label,
      for (final v in AuctionStatus.values) v.label,
      for (final v in DeliveryMethod.values) ...[v.label, v.subtitle],
      for (final v in DeliveryStatus.values) v.label,
      for (final v in ReportReason.values) v.label,
      for (final v in SwapStatus.values) v.label,
      for (final v in MyTab.values) v.label,
      for (final v in AuctionRole.values)
        if (v != AuctionRole.none) v.label,
      for (final v in MarketSort.values) v.label,
      for (final v in ChartRange.values) v.label,
      for (final k in NotificationKind.values)
        AppNotification(
          id: 'x',
          userId: 'u',
          kind: k,
          args: const ['a', 'b', 'c'],
          createdAt: DateTime(2026),
        ).text,
    ];
    Tr.lang = AppLang.hr;
    expect(texts, isNotEmpty);
    expect(Tr.missing, isEmpty);
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
