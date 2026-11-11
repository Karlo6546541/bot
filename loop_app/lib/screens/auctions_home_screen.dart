import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/auction.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/auction_kind_style.dart';
import '../widgets/countdown.dart';
import '../widgets/dutch_price.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import 'auction_detail_screen.dart';
import 'search_screen.dart';

/// Početna u aplikaciji samo za aukcije: pretraga, filter vrste aukcije
/// (Sve · Klasična · Nizozemska · Zatvorena) i mreža aukcija u dva stupca.
class AuctionsHomeScreen extends ConsumerStatefulWidget {
  const AuctionsHomeScreen({super.key});

  @override
  ConsumerState<AuctionsHomeScreen> createState() => _AuctionsHomeScreenState();
}

class _AuctionsHomeScreenState extends ConsumerState<AuctionsHomeScreen> {
  AuctionKind? _kind;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final now = DateTime.now();
    final list = [
      for (final a in s.activeAuctions)
        if (!a.isExpired(now) &&
            !s.isBlocked(a.sellerId) &&
            (_kind == null || a.kind == _kind))
          a,
    ]..sort((a, b) => a.endsAt.compareTo(b.endsAt));
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900
        ? 4
        : width >= 600
        ? 3
        : 2;

    Widget chip(Key key, String label, IconData icon, AuctionKind? kind) {
      final on = _kind == kind;
      final fg = on ? LoopColors.onAccent : LoopColors.textPrimary;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(99),
          onTap: () => setState(() => _kind = kind),
          child: Container(
            height: 44,
            padding: const EdgeInsets.fromLTRB(14, 0, 18, 0),
            decoration: BoxDecoration(
              color: on ? LoopColors.accent : LoopColors.surface,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: on ? LoopColors.accent : LoopColors.glassBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        key: const ValueKey('home-ending'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: InkWell(
                key: const ValueKey('home-search'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => SearchScreen.open(context),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: LoopColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: LoopColors.glassBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 20,
                        color: LoopColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('Pretraži aukcije'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 56,
              child: ListView(
                key: const ValueKey('home-formats'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                children: [
                  chip(
                    const ValueKey('home-format-all'),
                    t('Sve'),
                    Icons.grid_view_rounded,
                    null,
                  ),
                  for (final k in AuctionKind.values) ...[
                    const SizedBox(width: 8),
                    chip(
                      ValueKey('home-format-${k.name}'),
                      k == AuctionKind.dutch ? t('Nizozemska') : k.label,
                      k.icon,
                      k,
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
              child: Text(
                t('Aukcije'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                ),
              ),
            ),
          ),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                key: const ValueKey('home-no-auctions'),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    t('Trenutno nema aukcija.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // Slika (kvadrat) + natpisi; viša kartica pri većem tekstu.
                  mainAxisExtent:
                      (width - 32 - (columns - 1) * 12) / columns +
                      132 * MediaQuery.textScalerOf(context).scale(1),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => AuctionTile(
                    key: ValueKey('home-auction-${list[i].id}'),
                    auction: list[i],
                  ),
                  childCount: list.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kartica aukcije u mreži: slika s oznakom vrste, naziv, natpis, cijena
/// i vrijeme (holandska: cijena koja pada).
class AuctionTile extends ConsumerWidget {
  const AuctionTile({super.key, required this.auction});
  final Auction auction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = auction;
    final device = ref.watch(
      appProvider.select((s) => s.deviceById(a.deviceId)),
    );
    final muted = TextStyle(color: LoopColors.textSecondary, fontSize: 12.5);
    Widget price(double value) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        formatCredits(value),
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
    return Material(
      color: LoopColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => AuctionDetailScreen.open(context, a.id),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: LoopColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LayoutBuilder(
                      builder: (_, c) => device == null
                          ? ColoredBox(color: LoopColors.surfaceHover)
                          : FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: ItemThumb(
                                device: device,
                                size: c.maxWidth,
                              ),
                            ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      right: 8,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AuctionKindBadge(kind: a.kind),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device?.name ?? a.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.2,
                        ),
                      ),
                      Text(a.kind.priceCaption, style: muted, maxLines: 1),
                      if (a.isDutch)
                        DutchPrice(
                          auction: a,
                          builder: (_, value) => price(value),
                        )
                      else
                        price(a.currentPrice),
                      if (a.isDutch)
                        Text(
                          t('Cijena pada svake sekunde'),
                          style: muted,
                          maxLines: 2,
                        )
                      else
                        AuctionCountdown(
                          endsAt: a.endsAt,
                          showIcon: false,
                          style: muted,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
