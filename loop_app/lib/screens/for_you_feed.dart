import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
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
  bool _scrolling = false;
  bool _rankingDirty = false;
  bool _inventoryDirty = false;
  bool _pendingSave = false;
  bool _disposed = false;
  Timer? _queueTimer;
  Timer? _saveTimer;
  final _pendingCategories = <String>[];

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
            (_allowSeen ||
                !_preferences.seenRecently(ForYouRanker.keyOf(i), now)))
          i,
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

  void _save() {
    _pendingSave = true;
    _saveTimer?.cancel();
    if (_disposed) { _flushStorage(); return; }
    if (!_scrolling) {
      _saveTimer = Timer(const Duration(milliseconds: 300), _flushStorage);
    }
  }

  void _flushStorage() {
    _saveTimer?.cancel();
    if (!_storage.isOpen) return;
    if (_pendingSave) {
      _pendingSave = false;
      unawaited(_storage.saveFeedPreferences(_userId, _preferences));
    }
    if (_pendingCategories.isNotEmpty) {
      final recent = _pendingCategories.toList();
      _pendingCategories.clear();
      unawaited(_storage.addRecentCategories(recent));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _queueTimer?.cancel();
    _saveTimer?.cancel();
    _flushStorage();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ForYouFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) _scheduleQueue();
  }

  void _onScrollState(bool scrolling) {
    _scrolling = scrolling;
    _queueTimer?.cancel();
    _saveTimer?.cancel();
    if (!scrolling) {
      if (_pendingSave) _save();
      _scheduleQueue();
    }
  }

  void _scheduleQueue() {
    _queueTimer?.cancel();
    if (_disposed || _scrolling || !widget.active) return;
    if (!_rankingDirty && !_inventoryDirty && _picks.length - _index > 12) return;
    _queueTimer = Timer(const Duration(milliseconds: 100), _refreshQueue);
  }

  void _refreshQueue() {
    if (!mounted || _scrolling || !widget.active) return;
    // Freeze the current entry and the next two already being decoded.
    final keep = (_index + 3).clamp(0, _picks.length);
    final kept = _picks.sublist(0, keep);
    final rest = _ranked(exclude: {
      for (final p in kept) ForYouRanker.keyOf(p.item),
    });
    _rankingDirty = false;
    _inventoryDirty = false;
    if (kept.length == _picks.length && rest.isEmpty) return;
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

  BrowseItem? _item(FeedEntry entry) {
    final key = _entryKey(entry);
    for (final p in _picks) {
      if (ForYouRanker.keyOf(p.item) == key) return p.item;
    }
    return null;
  }

  /// Called on pause, route coverage and swipe, using only visible time.
  void _watch(FeedEntry entry, Duration dwell) {
    if (!_storage.isOpen) return;
    final item = _item(entry);
    if (item == null || dwell <= Duration.zero) return;
    final key = _entryKey(entry);
    final before = _watched[key] ?? 0;
    final total = before + dwell.inMilliseconds;
    _watched[key] = total;
    if (_watched.length > 500) _watched.remove(_watched.keys.first);
    if (total > 0) {
      _shown.add(key);
      _preferences.recordSeen(key, DateTime.now());
    }
    double weight(int ms) => ms > 10000
        ? 3
        : ms > 4000
        ? 1.5
        : 0;
    final delta = weight(total) - weight(before);
    if (delta > 0 && !_preferences.hidden.contains(key)) {
      _rankingDirty = true;
      for (final c in item.categories) {
        _boost[c] = ((_boost[c] ?? 0) + delta).clamp(-4, 6).toDouble();
      }
      if (before <= 4000) {
        _pendingCategories.addAll([for (final c in item.categories) c.name]);
        if (_pendingCategories.length > 30) _pendingCategories.removeRange(0, _pendingCategories.length - 30);
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
      _rankingDirty = true;
      _save();
    }
  }

  void _onPage(int from, Duration dwell, int to) {
    // Page changes happen while a drag is still animating. Never rank or
    // rebuild the queue here; ScrollEnd schedules that work after settling.
    _index = to;
    _scheduleQueue();
  }

  void _restart({bool replay = false}) {
    _queueTimer?.cancel();
    setState(() {
      _allowSeen = replay;
      _shown.clear();
      _watched.clear();
      _index = 0;
      _generation++;
      _picks
        ..clear()
        ..addAll(_ranked());
    });
  }

  void _feedback(FeedEntry entry, FeedFeedback action) {
    _queueTimer?.cancel();
    if (action == FeedFeedback.settings) {
      unawaited(_controls());
      return;
    }
    final i = _item(entry);
    if (i == null) return;
    if (action == FeedFeedback.less) {
      for (final c in i.categories) {
        _preferences.less[c.name] = ((_preferences.less[c.name] ?? 0) + 3)
            .clamp(0, 12)
            .toDouble();
      }
      _preferences.hide(_entryKey(entry));
    } else if (action == FeedFeedback.seller) {
      final seller = i.show?.hostId ?? i.auction?.sellerId ?? i.device?.ownerId;
      if (seller != null) _preferences.hideSeller(seller);
    } else {
      _preferences.hide(_entryKey(entry));
    }
    _save();
    _flushStorage();
    // Keep previously viewed entries out when replacing the hidden page.
    setState(() {
      for (final p in _picks.take(_index + 1)) {
        _shown.add(ForYouRanker.keyOf(p.item));
      }
      _index = 0;
      _generation++;
      _picks
        ..clear()
        ..addAll(_ranked());
    });
  }

  Future<void> _controls() async {
    final reset = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t('Tvoje preporuke'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t(
                  'Skriveno: {0} oglasa i {1} prodavača. Postavke se spremaju samo na ovom uređaju.',
                  [_preferences.hidden.length, _preferences.sellers.length],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                key: const ValueKey('feed-reset-preferences'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('Vrati skrivene i poništi „Manje ovakvog”')),
              ),
            ],
          ),
        ),
      ),
    );
    if (reset == true && mounted) {
      _preferences.hidden.clear();
      _preferences.sellers.clear();
      _preferences.less.clear();
      _boost.clear();
      _save();
      _flushStorage();
      _restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appProvider, (previous, next) {
      // View counters alone must not reorder an actively scrolling feed.
      _inventoryDirty = _inventoryDirty || previous == null ||
          previous.devices.length != next.devices.length ||
          previous.auctions.length != next.auctions.length ||
          previous.liveShows.length != next.liveShows.length;
      _rankingDirty = _rankingDirty || previous == null ||
          previous.transactions.length != next.transactions.length ||
          !listEquals(previous.currentUser?.favorites, next.currentUser?.favorites) ||
          !listEquals(previous.currentUser?.following, next.currentUser?.following);
      if (_inventoryDirty || _rankingDirty) _scheduleQueue();
    });
    final end = ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                t('Sve novo si pogledao'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t('Provjeri nove oglase ili ponovno pogledaj dostupne.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _restart(),
                child: Text(t('Provjeri novo')),
              ),
              TextButton(
                onPressed: () => _restart(replay: true),
                child: Text(t('Pogledaj ponovno')),
              ),
              TextButton(
                onPressed: _controls,
                child: Text(t('Uredi preporuke')),
              ),
            ],
          ),
        ),
      ),
    );
    final reasons = {
      for (final p in _picks) ForYouRanker.keyOf(p.item): p.reason,
    };
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
        onScrollState: _onScrollState,
        onWatch: _watch,
        onDetails: _details,
        onFeedback: _feedback,
        endPage: end,
        reasonOf: (e) => reasons[_entryKey(e)],
      ),
    );
  }
}
