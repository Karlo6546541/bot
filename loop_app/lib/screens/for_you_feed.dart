import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/feed_preferences.dart';
import '../services/storage_service.dart';
import '../widgets/feed.dart' show FeedEntry;
import 'auctions_screen.dart';
import 'for_you_ranker.dart';
import 'swipe_feed_screen.dart';

/// Bounded batches, explicit replay and account-scoped recommendation controls.
class ForYouFeed extends ConsumerStatefulWidget {
  const ForYouFeed({super.key, required this.active});
  final bool active;

  @override
  ConsumerState<ForYouFeed> createState() => _ForYouFeedState();
}

class _ForYouFeedState extends ConsumerState<ForYouFeed> {
  final _picks = <Pick>[];
  final _boost = <DeviceCategory, double>{};
  final _shown = <String>{};
  final _watched = <String, int>{};
  late final String? _userId;
  late FeedPreferences _preferences;
  late final StorageService _storage;
  int _index = 0;
  int _generation = 0;
  bool _allowSeen = false;

  static String _entryKey(FeedEntry e) =>
      e.liveId ?? e.auctionId ?? e.deviceId ?? '';

  List<Pick> _ranked({Set<String> exclude = const {}}) {
    final s = ref.read(appProvider);
    final now = DateTime.now();
    return ForYouRanker(
      s,
      now: now,
      recentCategories: ref.read(storageProvider).recentCategories,
      boost: _boost,
      preferences: _preferences,
    ).rank([
      for (final i in browseItems(s))
        if (!exclude.contains(ForYouRanker.keyOf(i)) &&
            !_shown.contains(ForYouRanker.keyOf(i)) &&
            (_allowSeen || !_preferences.seenRecently(ForYouRanker.keyOf(i), now))) i,
    ], limit: 40);
  }

  @override
  void initState() {
    super.initState();
    final s = ref.read(appProvider);
    _userId = s.currentUser?.isGuest ?? true ? null : s.currentUserId;
    _storage = ref.read(storageProvider);
    _preferences = _storage.feedPreferences(_userId);
    _picks.addAll(_ranked());
  }

  void _save() => unawaited(
    _storage.saveFeedPreferences(_userId, _preferences),
  );

  BrowseItem? _item(FeedEntry entry) {
    final key = _entryKey(entry);
    for (final p in _picks) {
      if (ForYouRanker.keyOf(p.item) == key) return p.item;
    }
    return null;
  }

  /// Called on pause, route coverage and swipe, using only visible time.
  void _watch(FeedEntry entry, Duration dwell) {
    final item = _item(entry);
    if (item == null || dwell <= Duration.zero) return;
    final key = _entryKey(entry);
    final before = _watched[key] ?? 0;
    final total = before + dwell.inMilliseconds;
    _watched[key] = total;
    if (total >= 800) {
      _shown.add(key);
      _preferences.recordSeen(key, DateTime.now());
    }
    double weight(int ms) => ms > 10000 ? 3 : ms > 4000 ? 1.5 : 0;
    final delta = weight(total) - weight(before);
    if (delta > 0 && !_preferences.hidden.contains(key)) {
      for (final c in item.categories) {
        _boost[c] = ((_boost[c] ?? 0) + delta).clamp(-4, 6).toDouble();
      }
      if (before <= 4000) {
        unawaited(_storage.addRecentCategories([
          for (final c in item.categories) c.name,
        ]));
        final d = item.device;
        if (d != null) _preferences.learnModel(d.model, d.condition.name);
      }
    }
    _save();
  }

  void _details(FeedEntry entry) {
    final d = _item(entry)?.device;
    if (d != null) {
      _preferences.learnModel(d.model, d.condition.name);
      _save();
    }
  }

  void _onPage(int from, Duration dwell, int to) {
    if (!mounted) return;
    _index = to;
    // Freeze current and next, then rerank a small upcoming batch.
    final keep = (to + 2).clamp(0, _picks.length);
    final kept = _picks.sublist(0, keep);
    final rest = _ranked(exclude: {
      for (final p in kept) ForYouRanker.keyOf(p.item),
    });
    setState(() {
      _picks..clear()..addAll(kept)..addAll(rest);
      if (_index > 60) {
        final trim = _index - 10;
        _picks.removeRange(0, trim);
        _index -= trim;
        _generation++;
      }
    });
  }

  void _restart({bool replay = false}) {
    setState(() {
      _allowSeen = replay;
      _shown.clear();
      _watched.clear();
      _index = 0;
      _generation++;
      _picks..clear()..addAll(_ranked());
    });
  }

  void _feedback(FeedEntry entry, FeedFeedback action) {
    final i = _item(entry);
    if (i == null) return;
    if (action == FeedFeedback.less) {
      for (final c in i.categories) {
        _preferences.less[c.name] =
            ((_preferences.less[c.name] ?? 0) + 3).clamp(0, 12).toDouble();
      }
      _preferences.hide(_entryKey(entry));
    } else if (action == FeedFeedback.seller) {
      final seller = i.show?.hostId ?? i.auction?.sellerId ?? i.device?.ownerId;
      if (seller != null) _preferences.hideSeller(seller);
    } else {
      _preferences.hide(_entryKey(entry));
    }
    _save();
    // Keep previously viewed entries out when replacing the hidden page.
    setState(() {
      for (final p in _picks.take(_index + 1)) {
        _shown.add(ForYouRanker.keyOf(p.item));
      }
      _index = 0;
      _generation++;
      _picks..clear()..addAll(_ranked());
    });
  }

  Future<void> _controls() async {
    final reset = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t('Tvoje preporuke'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(t('Skriveno: {0} oglasa i {1} prodavača. Postavke se spremaju samo na ovom uređaju.',
            [_preferences.hidden.length, _preferences.sellers.length])),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const ValueKey('feed-reset-preferences'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Vrati skrivene i poništi „Manje ovakvog”')),
          ),
        ]),
      )),
    );
    if (reset == true && mounted) {
      _preferences.hidden.clear();
      _preferences.sellers.clear();
      _preferences.less.clear();
      _boost.clear();
      _save();
      _restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appProvider, (_, _) {
      final fresh = _ranked(exclude: {
        for (final p in _picks) ForYouRanker.keyOf(p.item),
      });
      // Add new content without changing the visible entry.
      if (fresh.isNotEmpty && _index < _picks.length) {
        setState(() => _picks.addAll(fresh));
      }
    });
    final end = ColoredBox(
      color: Colors.black,
      child: Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          Text(t('Sve novo si pogledao'), textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(t('Provjeri nove oglase ili ponovno pogledaj dostupne.'),
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => _restart(), child: Text(t('Provjeri novo'))),
          TextButton(onPressed: () => _restart(replay: true), child: Text(t('Pogledaj ponovno'))),
          TextButton(onPressed: _controls, child: Text(t('Uredi preporuke'))),
        ]),
      )),
    );
    final reasons = {for (final p in _picks) ForYouRanker.keyOf(p.item): p.reason};
    return KeyedSubtree(
      key: ValueKey(_generation),
      child: SwipeFeedScreen(
        key: const ValueKey('for-you-feed'),
        entries: [for (final p in _picks) p.item.entry],
        initialIndex: _index.clamp(0, _picks.length),
        title: t('Za tebe'),
        embedded: true,
        active: widget.active,
        onPage: _onPage,
        onWatch: _watch,
        onDetails: _details,
        onFeedback: _feedback,
        endPage: end,
        reasonOf: (e) => reasons[_entryKey(e)],
      ),
    );
  }
}
