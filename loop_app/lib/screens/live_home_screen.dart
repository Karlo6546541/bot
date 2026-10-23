import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'auctions_screen.dart';
import 'create_auction_screen.dart';
import 'live_screens.dart';
import 'swipe_feed_screen.dart';

/// Početna (kao Whatnot): tko je uživo sada, zakazani liveovi i aukcije koje
/// uskoro završavaju. Dodir na karticu otvara swipe feed te skupine.
class LiveHomeScreen extends ConsumerStatefulWidget {
  const LiveHomeScreen({super.key, required this.onBrowse});

  /// Prijelaz na karticu "Aukcije" (sve aukcije i kategorije).
  final VoidCallback onBrowse;

  @override
  ConsumerState<LiveHomeScreen> createState() => _LiveHomeScreenState();
}

class _LiveHomeScreenState extends ConsumerState<LiveHomeScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Liveovi počinju i završavaju sami (domaćin dođe ili ode).
    if (ref.read(tickIntervalProvider) != null) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId ?? '';
    final all = browseItems(s);
    final live = all.where((i) => i.live?.isLive ?? false).toList();
    final soon = all.where((i) => i.live?.isScheduled ?? false).toList();
    final ending = all.where((i) => i.auction != null).take(6).toList();
    final phone = MediaQuery.sizeOf(context).width < 600;

    void open(List<BrowseItem> list, int i, String title) =>
        SwipeFeedScreen.open(
          context,
          [for (final x in list) x.entry],
          i,
          title: title,
        );

    Widget strip(String key, List<BrowseItem> list, String title) => SizedBox(
      key: ValueKey(key),
      height: 290,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(
          width: 175,
          child: AuctionBrowseCard(
            item: list[i],
            viewerId: me,
            onTap: () => open(list, i, title),
          ),
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _Hero(compact: phone),
        ),
        _Header(
          title: t('🔴 Uživo sada'),
          action: live.isEmpty ? null : t('Sve'),
          onAction: widget.onBrowse,
        ),
        if (live.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _EmptyLive(
              onGoLive: () => CreateLiveShowScreen.open(context),
            ),
          )
        else
          strip('home-live', live, t('Uživo sada')),
        if (soon.isNotEmpty) ...[
          _Header(title: t('📅 Uskoro')),
          strip('home-soon', soon, t('Uskoro')),
        ],
        _Header(
          title: t('⏱ Završavaju uskoro'),
          action: t('Sve aukcije'),
          onAction: widget.onBrowse,
        ),
        if (ending.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              t('Trenutno nema aukcija.'),
              style: TextStyle(color: LoopColors.textSecondary),
            ),
          )
        else
          GridView.builder(
            key: const ValueKey('home-ending'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              childAspectRatio: 0.6,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: ending.length,
            itemBuilder: (_, i) => AuctionBrowseCard(
              item: ending[i],
              viewerId: me,
              onTap: () => open(ending, i, t('Završavaju uskoro')),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

/// Poziv na početku: kreni uživo ili objavi aukciju.
class _Hero extends StatelessWidget {
  const _Hero({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6A2BD6), kLiveRed],
      ),
      borderRadius: BorderRadius.circular(kRadius + 4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('Licitiraj uživo'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          t(
            'Live aukcije s videom i obične aukcije — gledaj, licitiraj i prodaj u par sekundi.',
          ),
          style: const TextStyle(color: Colors.white, height: 1.35),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('home-go-live'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kLiveRed,
              ),
              onPressed: () => CreateLiveShowScreen.open(context),
              icon: const Icon(Icons.videocam),
              label: Text(t('Kreni uživo')),
            ),
            OutlinedButton.icon(
              key: const ValueKey('home-new-auction'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              onPressed: () => CreateAuctionScreen.open(context),
              icon: const Icon(Icons.gavel),
              label: Text(t('Nova aukcija')),
            ),
          ],
        ),
      ],
    ),
  );
}

class _EmptyLive extends StatelessWidget {
  const _EmptyLive({required this.onGoLive});
  final VoidCallback onGoLive;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: LoopColors.surface,
      borderRadius: BorderRadius.circular(kRadius),
    ),
    child: Row(
      children: [
        const LiveBadge(small: true),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            t('Nitko trenutno nije uživo — budi prvi!'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(onPressed: onGoLive, child: Text(t('Kreni'))),
      ],
    ),
  );
}
