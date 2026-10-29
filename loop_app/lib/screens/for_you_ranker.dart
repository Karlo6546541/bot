import 'dart:math' as math;

import '../l10n/tr.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../models/loop_transaction.dart';
import '../providers/app_state.dart';
import '../services/feed_preferences.dart';
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
  ForYouRanker(
    this.s, {
    required this.now,
    this.recentCategories = const [],
    this.boost = const {},
    FeedPreferences? preferences,
  }) : preferences = preferences ?? FeedPreferences();

  final FeedPreferences preferences;

  /// Učenje u stvarnom vremenu (feed "Za tebe"): dugo gledano (+),
  /// brzo preskočeno (−), po kategoriji, samo za ovu sesiju.
  final Map<DeviceCategory, double> boost;

  /// Jedinstveni ključ oglasa (live, aukcija ili predmet).
  static String keyOf(BrowseItem i) =>
      i.show?.id ?? i.auction?.id ?? i.device?.id ?? '';

  final AppState s;
  final DateTime now;

  // Build indexes once per batch instead of scanning users/devices per candidate.
  late final _devicesById = {for (final d in s.devices) d.id: d};
  late final _showsById = {for (final show in s.liveShows) show.id: show};
  late final Map<String, int> _likeCounts = () {
    final counts = <String, int>{};
    for (final user in s.users) {
      for (final id in user.favorites.toSet()) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return counts;
  }();

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
    void add(DeviceCategory? c, double v) {
      if (c != null) w[c] = (w[c] ?? 0) + v;
    }

    for (final t in s.transactions) {
      if (t.buyerId == me &&
          t.type != TransactionType.delivery &&
          t.type != TransactionType.payout) {
        add(_devicesById[t.deviceId]?.category, 5 * _decay(t.createdAt));
      }
    }
    for (final a in s.auctions) {
      final mine = a.bids.where((b) => b.userId == me);
      if (mine.isNotEmpty) {
        add(_devicesById[a.deviceId]?.category, 4 * _decay(mine.last.time));
      }
    }
    for (final e in s.liveEvents) {
      if (e.userId != me || e.type != LiveEventType.bid) continue;
      final show = _showsById[e.showId];
      if (show == null || e.lot >= show.lots.length) continue;
      add(_devicesById[show.lots[e.lot].deviceId]?.category, 3 * _decay(e.at));
    }
    for (final id in me == null ? const <String>[] : s.currentUser!.favorites) {
      add(_devicesById[id]?.category, 3);
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
  /// Budget is learned separately for each product category.
  late final Map<DeviceCategory, double> _usualPrices = () {
    final me = _me;
    final prices = <DeviceCategory, List<double>>{};
    if (me == null) return <DeviceCategory, double>{};
    for (final tx in s.transactions) {
      final c = _devicesById[tx.deviceId]?.category;
      if (tx.buyerId == me &&
          c != null &&
          tx.price > 0 &&
          tx.type != TransactionType.delivery &&
          tx.type != TransactionType.payout) {
        (prices[c] ??= []).add(tx.price);
      }
    }
    for (final a in s.auctions) {
      final c = _devicesById[a.deviceId]?.category;
      final bids = a.bids.where((b) => b.userId == me);
      if (c != null && bids.isNotEmpty) {
        (prices[c] ??= []).add(bids.last.amount);
      }
    }
    return {
      for (final e in prices.entries)
        e.key: (e.value..sort())[e.value.length ~/ 2],
    };
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
        '${_me ?? 'gost'}|${keyOf(i)}|${now.year}-${now.month}-${now.day}';
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
    // Učenje u sesiji: najjači signal kategorije (pozitivan ili negativan).
    var penalty = 0.0;
    if (boost.isNotEmpty) {
      DeviceCategory? cat;
      var b = 0.0;
      for (final c in i.categories) {
        final v = boost[c] ?? 0;
        if (v.abs() > b.abs()) {
          b = v;
          cat = c;
        }
      }
      if (b > 0 && cat != null) {
        parts.add((b, t('Gledaš puno: {0}', [cat.label])));
      } else {
        penalty = b;
      }
    }
    for (final c in i.categories) {
      penalty -= preferences.less[c.name] ?? 0;
    }
    final title = _title(i);
    final modelMatch = preferences.models.entries.where(
      (e) => title.contains(e.key),
    );
    if (modelMatch.isNotEmpty) {
      parts.add((
        modelMatch.map((e) => e.value).reduce(math.max),
        t('Slično onome što gledaš'),
      ));
    }
    final condition = preferences.conditions[i.device?.condition.name];
    if (condition != null && condition > 0) {
      parts.add((condition, t('Stanje koje te zanima')));
    }
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
    final usual = i.device == null ? null : _usualPrices[i.device!.category];
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
        (id == null ? 0 : s.viewsOf(id) + (_likeCounts[id] ?? 0) * 2) +
        (a?.bids.length ?? 0) * 3;
    if (pop > 0) {
      parts.add((0.6 * math.log(1 + pop), t('Popularno')));
    }

    // 6. Novo.
    final listed = i.device?.listedAt ?? a?.createdAt;
    if (listed != null && now.difference(listed) < const Duration(hours: 24)) {
      parts.add((0.8, t('Novo')));
    }

    final total =
        parts.fold(0.0, (sum, x) => sum + x.$1) + _jitter(i) + penalty;
    final top = parts.isEmpty
        ? t('Za tebe')
        : (parts..sort((x, y) => y.$1.compareTo(x.$1))).first.$2;
    return (total, top);
  }

  /// Prefer unseen entries, then fill the batch from available seen entries.
  /// Explicit hides and seller exclusions still apply in [rank].
  List<Pick> rankBatch(
    List<BrowseItem> items, {
    Set<String> exclude = const {},
    int limit = 40,
    bool replay = false,
  }) {
    final eligible = items.where((i) => !exclude.contains(keyOf(i))).toList();
    if (replay) return rank(eligible, limit: limit);
    final fresh = rank([
      for (final i in eligible)
        if (!preferences.seenRecently(keyOf(i), now)) i,
    ], limit: limit);
    if (fresh.length == limit) return fresh;
    return [
      ...fresh,
      ...rank([
        for (final i in eligible)
          if (preferences.seenRecently(keyOf(i), now)) i,
      ], limit: limit - fresh.length),
    ];
  }

  /// Najboljih [limit] oglasa — bez vlastitih, s raznolikošću (isti
  /// prodavač ili kategorija zaredom dobivaju kaznu).
  List<Pick> rank(List<BrowseItem> items, {int limit = 8}) {
    final pool = <Pick>[
      for (final i in items)
        if ((_sellerOf(i) != _me || _me == null) &&
            !preferences.hidden.contains(keyOf(i)) &&
            !preferences.sellers.contains(_sellerOf(i)))
          if (score(i) case (final sc, final why)) Pick(i, why, sc),
    ];
    final out = <Pick>[];
    while (pool.isNotEmpty && out.length < limit) {
      Pick? best;
      var bestScore = double.negativeInfinity;
      final window = out.skip(math.max(0, out.length - 4)).toList();
      final diverse = pool
          .where(
            (p) =>
                window
                    .where((o) => _sellerOf(o.item) == _sellerOf(p.item))
                    .length <
                2,
          )
          .toList();
      var candidates = diverse.isEmpty ? pool : diverse;
      // One slot in five can surface a new, little-seen listing.
      if (out.length % 5 == 4) {
        final fresh = candidates.where((p) {
          final d = p.item.device;
          final at = d?.listedAt;
          return d != null &&
              at != null &&
              now.difference(at) < const Duration(days: 7) &&
              s.viewsOf(d.id) < 10;
        }).toList();
        if (fresh.isNotEmpty) candidates = fresh;
      }
      for (final c in candidates) {
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
