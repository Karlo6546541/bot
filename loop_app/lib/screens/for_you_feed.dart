import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../widgets/feed.dart' show FeedEntry;
import 'auctions_screen.dart';
import 'for_you_ranker.dart';
import 'search_screen.dart';
import 'swipe_feed_screen.dart';

/// "Za tebe" kao TikTok: objave preko cijelog ekrana, beskonačno, a
/// redoslijed se prilagođava dok listaš.
///
/// - Gledao > 4 s → kategorija +1,5 (> 10 s: +3); preskočio < 1,2 s → −1,2.
/// - Nakon svake objave ostatak reda se ponovno slaže (već viđene i sljedeća
///   ostaju na mjestu, da ekran ne "skoči").
/// - Kad ponestane objava, kreće novi krug (bez nedavno viđenih).
class ForYouFeed extends ConsumerStatefulWidget {
  const ForYouFeed({super.key, required this.active});

  /// Je li feed na ekranu (tab Početna, "Za tebe", nije prekriven).
  final bool active;

  @override
  ConsumerState<ForYouFeed> createState() => _ForYouFeedState();
}

class _ForYouFeedState extends ConsumerState<ForYouFeed> {
  final _picks = <Pick>[];
  final _boost = <DeviceCategory, double>{};
  int _index = 0;

  static String _entryKey(FeedEntry e) =>
      e.liveId ?? e.auctionId ?? e.deviceId ?? '';

  List<Pick> _ranked({Set<String> exclude = const {}}) {
    final s = ref.read(appProvider);
    return ForYouRanker(
      s,
      now: DateTime.now(),
      recentCategories: ref.read(storageProvider).recentCategories,
      boost: _boost,
    ).rank([
      for (final i in browseItems(s))
        if (!exclude.contains(ForYouRanker.keyOf(i))) i,
    ], limit: 1000);
  }

  @override
  void initState() {
    super.initState();
    _picks.addAll(_ranked());
  }

  void _onPage(int from, Duration dwell, int to) {
    if (from < _picks.length) {
      final cats = _picks[from].item.categories;
      final ms = dwell.inMilliseconds;
      final delta = ms > 10000
          ? 3.0
          : ms > 4000
          ? 1.5
          : ms < 1200
          ? -1.2
          : 0.0;
      if (delta != 0) {
        for (final c in cats) {
          _boost[c] = ((_boost[c] ?? 0) + delta).clamp(-4.0, 6.0);
        }
      }
      if (ms > 4000) {
        ref.read(storageProvider).addRecentCategories([
          for (final c in cats) c.name,
        ]);
      }
    }
    _index = to;
    // Viđeno i sljedeća objava ostaju; ostatak se slaže iznova.
    final keep = (to + 2).clamp(0, _picks.length);
    final kept = _picks.sublist(0, keep);
    final seen = {for (final p in kept) ForYouRanker.keyOf(p.item)};
    var rest = _ranked(exclude: seen);
    if (rest.length < 3) {
      // Novi krug: sve osim zadnjih 5 viđenih.
      final recent = {
        for (final p in kept.reversed.take(5)) ForYouRanker.keyOf(p.item),
      };
      rest = [
        ...rest,
        ..._ranked(
          exclude: {
            ...recent,
            for (final p in rest) ForYouRanker.keyOf(p.item),
          },
        ),
      ];
    }
    setState(() {
      _picks
        ..clear()
        ..addAll(kept)
        ..addAll(rest);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Novi oglasi/liveovi (sinkronizacija) dolaze na kraj reda.
    ref.listen(appProvider, (_, _) {
      final have = {for (final p in _picks) ForYouRanker.keyOf(p.item)};
      final fresh = _ranked(exclude: have);
      if (fresh.isNotEmpty) setState(() => _picks.addAll(fresh));
    });
    if (_picks.isEmpty) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Text(
          t('Još nema objava — svrati uskoro.'),
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    final reasons = {
      for (final p in _picks) ForYouRanker.keyOf(p.item): p.reason,
    };
    final onLive = _index < _picks.length && _picks[_index].item.show != null;
    final feed = SwipeFeedScreen(
      key: const ValueKey('for-you-feed'),
      entries: [for (final p in _picks) p.item.entry],
      initialIndex: _index.clamp(0, _picks.length - 1),
      title: t('Za tebe'),
      embedded: true,
      active: widget.active,
      onPage: _onPage,
      reasonOf: (e) => reasons[_entryKey(e)],
    );
    // Pretraga preko objave gore desno (kao TikTok); live ima svoju traku.
    return Stack(
      children: [
        feed,
        if (!onLive)
          Positioned(
            right: 6,
            top: 6,
            child: IconButton(
              key: const ValueKey('home-search'),
              tooltip: t('Pretraži liveove, aukcije i prodavače'),
              onPressed: () => SearchScreen.open(context),
              icon: const Icon(
                Icons.search,
                color: Colors.white,
                size: 28,
                shadows: [Shadow(blurRadius: 8, color: Colors.black87)],
              ),
            ),
          ),
      ],
    );
  }
}
