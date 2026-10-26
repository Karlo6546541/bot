import 'dart:math' as math;

import '../l10n/tr.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../models/loop_transaction.dart';
import '../providers/app_state.dart';
import '../widgets/formatters.dart';
import 'auctions_screen.dart';

/// Preporuka za "Za tebe": oglas i kratak razlog ("Jer pratiš @ana").
class Pick {
  const Pick(this.item, this.reason, this.score);
  final BrowseItem item;
  final String reason;
  final double score;
}

/// Algoritam "Za tebe".
///
/// 1. **Ukus** — težina po kategoriji iz onoga što si radio: kupnja (5),
///    ponuda na aukciji (4), ponuda u liveu (3), srce (3), pretraga (2),
///    otvoreni oglas (1). Novije radnje vrijede više (pola težine nakon
///    14 dana).
/// 2. **Prodavači** — koje pratiš (+3) ili od kojih si kupovao (+2).
/// 3. **Cijena** — blizu cijena koje inače plaćaš/nudiš (+1).
/// 4. **Hitnost** — live je uživo (+2,5), aukcija završava u sat vremena
///    (do +2), live počinje danas (+0,5).
/// 5. **Popularnost** — gledatelji, prikazi, srca i ponude (logaritamski,
///    da veliki ne pojedu sve).
/// 6. **Novo** — objavljeno u zadnja 24 h (+0,8).
/// 7. **Raznolikost** — isti prodavač ili kategorija zaredom dobivaju
///    kaznu, a mala dnevna "slučajnost" (ista cijeli dan) miješa redoslijed.
///
/// Bez prijave (ili bez povijesti) ostaju hitnost, popularnost i novo.
class ForYouRanker {
  ForYouRanker(this.s, {required this.now, this.recentCategories = const []});

  final AppState s;
  final DateTime now;

  /// Kategorije oglasa koje si nedavno otvorio (najnovije zadnje).
  final List<String> recentCategories;

  late final String? _me = s.currentUser?.isGuest ?? true
      ? null
      : s.currentUserId;

  double _decay(DateTime at) {
    final days = now.difference(at).inHours / 24;
    return math.pow(0.5, math.max(0, days) / 14).toDouble();
  }

  /// Težina po kategoriji (ukus) — svaka kategorija svoj zbroj.
  late final Map<DeviceCategory, double> taste = () {
    final me = _me;
    final w = <DeviceCategory, double>{};
    if (me == null) return w;
    void add(DeviceCategory? c, double v) {
      if (c != null) w[c] = (w[c] ?? 0) + v;
    }

    for (final t in s.transactions) {
      if (t.buyerId == me &&
          t.type != TransactionType.delivery &&
          t.type != TransactionType.payout) {
        add(s.deviceById(t.deviceId)?.category, 5 * _decay(t.createdAt));
      }
    }
    for (final a in s.auctions) {
      final mine = a.bids.where((b) => b.userId == me);
      if (mine.isNotEmpty) {
        add(s.deviceById(a.deviceId)?.category, 4 * _decay(mine.last.time));
      }
    }
    for (final e in s.liveEvents) {
      if (e.userId != me || e.type != LiveEventType.bid) continue;
      final show = s.liveShowById(e.showId);
      if (show == null || e.lot >= show.lots.length) continue;
      add(s.deviceById(show.lots[e.lot].deviceId)?.category, 3 * _decay(e.at));
    }
    for (final id in s.currentUser?.favorites ?? const <String>[]) {
      add(s.deviceById(id)?.category, 3);
    }
    for (final q in s.searchHistory.take(10)) {
      final term = q.toLowerCase();
      for (final c in DeviceCategory.values) {
        final l = c.label.toLowerCase();
        if (term.length >= 3 && (l.contains(term) || term.contains(l))) {
          add(c, 2);
        }
      }
    }
    final recent = recentCategories.reversed.take(20).toList();
    for (var i = 0; i < recent.length; i++) {
      // Zadnje otvoreno vrijedi 1, starije sve manje.
      add(DeviceCategory.fromName(recent[i]), 1 / (1 + i * 0.2));
    }
    return w;
  }();

  late final double _maxTaste = taste.values.fold(0.0, math.max);

  late final Set<String> _following = {
    if (_me != null) ...s.currentUser!.following,
  };

  /// Prodavači od kojih sam kupovao.
  late final Set<String> _boughtFrom = {
    for (final t in s.transactions)
      if (_me != null && t.buyerId == _me && t.sellerId != null) t.sellerId!,
  };

  /// Srednja cijena koju plaćam ili nudim (null = nema povijesti).
  late final double? _usualPrice = () {
    final me = _me;
    if (me == null) return null;
    final prices = <double>[
      for (final t in s.transactions)
        if (t.buyerId == me && t.price > 0) t.price,
      for (final a in s.auctions)
        for (final b in a.bids)
          if (b.userId == me) b.amount,
    ]..sort();
    return prices.isEmpty ? null : prices[prices.length ~/ 2];
  }();

  late final List<String> _terms = [
    for (final q in s.searchHistory.take(10))
      if (q.trim().length >= 3) q.trim().toLowerCase(),
  ];

  String? _sellerOf(BrowseItem i) =>
      i.show?.hostId ?? i.auction?.sellerId ?? i.device?.ownerId;

  String _title(BrowseItem i) =>
      (i.show?.title ?? i.device?.name ?? i.auction?.deviceName ?? '')
          .toLowerCase();

  double? _price(BrowseItem i) =>
      i.live?.current?.price ?? i.auction?.currentPrice ?? i.device?.price;

  /// Mala dnevna "slučajnost" (0–0,6), ista cijeli dan za isti oglas.
  double _jitter(BrowseItem i) {
    final key =
        '${_me ?? 'gost'}|${i.show?.id ?? i.auction?.id ?? i.device?.id}|${now.year}-${now.month}-${now.day}';
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return (h % 1000) / 1000 * 0.6;
  }

  /// Ocjena oglasa i glavni razlog.
  (double, String) score(BrowseItem i) {
    final parts = <(double, String)>[];
    final seller = _sellerOf(i);

    // 1. Ukus (do +4, prema najjačoj kategoriji).
    if (_maxTaste > 0) {
      DeviceCategory? best;
      var bestW = 0.0;
      for (final c in i.categories) {
        final v = taste[c] ?? 0;
        if (v > bestW) {
          bestW = v;
          best = c;
        }
      }
      if (best != null) {
        parts.add((4 * bestW / _maxTaste, t('Voliš: {0}', [best.label])));
      }
    }
    final title = _title(i);
    for (final term in _terms) {
      if (title.contains(term)) {
        parts.add((1.5, t('Tražio si "{0}"', [term])));
        break;
      }
    }

    // 2. Prodavači.
    if (seller != null && _following.contains(seller)) {
      parts.add((3, t('Jer pratiš {0}', [s.userLabel(seller)])));
    } else if (seller != null && _boughtFrom.contains(seller)) {
      parts.add((2, t('Kupovao si od {0}', [s.userLabel(seller)])));
    }

    // 3. Cijena.
    final p = _price(i);
    final usual = _usualPrice;
    if (p != null && usual != null && p >= usual * 0.4 && p <= usual * 2.5) {
      parts.add((1, t('U tvom budžetu')));
    }

    // 4. Hitnost.
    final live = i.live;
    if (live != null && live.isLive) {
      parts.add((2.5, t('Uživo sada')));
    } else if (i.show != null &&
        i.show!.startsAt.isAfter(now) &&
        i.show!.startsAt.difference(now) < const Duration(hours: 24)) {
      parts.add((0.5, t('Počinje {0}', [formatDateTime(i.show!.startsAt)])));
    }
    final a = i.auction;
    if (a != null) {
      final left = a.endsAt.difference(now);
      if (left > Duration.zero && left < const Duration(hours: 1)) {
        parts.add((
          2 * (1 - left.inSeconds / 3600),
          t('Završava za {0} min', ['${left.inMinutes + 1}']),
        ));
      }
    }

    // 5. Popularnost.
    final id = i.device?.id ?? a?.deviceId;
    final pop =
        (live?.viewers ?? 0) * 2 +
        (id == null ? 0 : s.viewsOf(id) + s.likesOf(id) * 2) +
        (a?.bids.length ?? 0) * 3;
    if (pop > 0) {
      parts.add((0.6 * math.log(1 + pop), t('Popularno')));
    }

    // 6. Novo.
    final listed = i.device?.listedAt ?? a?.createdAt;
    if (listed != null && now.difference(listed) < const Duration(hours: 24)) {
      parts.add((0.8, t('Novo')));
    }

    final total = parts.fold(0.0, (sum, x) => sum + x.$1) + _jitter(i);
    final top = parts.isEmpty
        ? t('Za tebe')
        : (parts..sort((x, y) => y.$1.compareTo(x.$1))).first.$2;
    return (total, top);
  }

  /// Najboljih [limit] oglasa — bez vlastitih, s raznolikošću (isti
  /// prodavač ili kategorija zaredom dobivaju kaznu).
  List<Pick> rank(List<BrowseItem> items, {int limit = 8}) {
    final pool = <Pick>[
      for (final i in items)
        if (_sellerOf(i) != _me || _me == null)
          if (score(i) case (final sc, final why)) Pick(i, why, sc),
    ];
    final out = <Pick>[];
    while (pool.isNotEmpty && out.length < limit) {
      Pick? best;
      var bestScore = double.negativeInfinity;
      for (final c in pool) {
        var sc = c.score;
        final recent = out.length < 2 ? out : out.sublist(out.length - 2);
        if (recent.any((o) => _sellerOf(o.item) == _sellerOf(c.item))) {
          sc -= 1.5;
        }
        if (out.isNotEmpty &&
            out.last.item.categories
                .intersection(c.item.categories)
                .isNotEmpty) {
          sc -= 0.8;
        }
        if (sc > bestScore) {
          bestScore = sc;
          best = c;
        }
      }
      out.add(best!);
      pool.remove(best);
    }
    return out;
  }
}
