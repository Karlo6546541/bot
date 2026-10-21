import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../screens/device_detail_screen.dart';
import '../screens/shop_screens.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'item_image.dart';

/// Zašto je oglas u feedu.
enum FeedReason { following, promoted, discount, fresh }

/// Oglasi za početnu: od prodavatelja koje pratim, istaknuti računi,
/// popusti, pa najnovije objave korisnika. Bez duplikata.
List<(Device, FeedReason)> buildFeed(AppState state, {int limit = 12}) {
  final me = state.currentUser;
  final market = state.marketDevices.where((d) => d.isListed).toList()
    ..sort(
      (a, b) =>
          (b.listedAt ?? b.createdAt).compareTo(a.listedAt ?? a.createdAt),
    );
  final out = <(Device, FeedReason)>[];
  final seen = <String>{};
  void add(Iterable<Device> list, FeedReason r) {
    for (final d in list) {
      if (out.length >= limit) return;
      if (seen.add(d.id)) out.add((d, r));
    }
  }

  final following = me?.following ?? const [];
  add(market.where((d) => following.contains(d.ownerId)), FeedReason.following);
  add(market.where(state.isPromotedItem), FeedReason.promoted);
  add(market.where((d) => d.hasDiscount), FeedReason.discount);
  add(market, FeedReason.fresh);
  return out;
}

/// "Za tebe" — vodoravni niz oglasa na početnoj.
class HomeFeed extends ConsumerWidget {
  const HomeFeed({super.key, required this.onGoToMarket});
  final VoidCallback onGoToMarket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final feed = buildFeed(state);
    if (feed.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t('Za tebe'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('open-leaderboard'),
              onPressed: () => LeaderboardScreen.open(context),
              icon: const Icon(Icons.emoji_events_outlined, size: 18),
              label: Text(t('Top prodavatelji')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 236,
          child: ListView.separated(
            key: const ValueKey('home-feed'),
            scrollDirection: Axis.horizontal,
            itemCount: feed.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              if (i == feed.length) {
                return _MoreCard(onTap: onGoToMarket);
              }
              final (d, reason) = feed[i];
              return _FeedCard(device: d, reason: reason, state: state);
            },
          ),
        ),
      ],
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.device,
    required this.reason,
    required this.state,
  });
  final Device device;
  final FeedReason reason;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final seller = state.userLabel(d.ownerId);
    final label = switch (reason) {
      FeedReason.following => t('Pratiš {0}', [seller]),
      FeedReason.promoted => t('⭐ Istaknuto'),
      FeedReason.discount => t('−{0}% popust', ['${d.discountPercent}']),
      FeedReason.fresh => t('Novo · {0}', [seller]),
    };
    final color = switch (reason) {
      FeedReason.following => LoopColors.lilac,
      FeedReason.promoted => LoopColors.sunny,
      FeedReason.discount => LoopColors.peach,
      FeedReason.fresh => LoopColors.mint,
    };
    return SizedBox(
      width: 160,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => DeviceDetailScreen.open(context, d),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: ItemThumb(device: d, size: 110)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  formatCredits(d.askPrice),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: d.hasDiscount ? LoopColors.error : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreCard extends StatelessWidget {
  const _MoreCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    child: Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront_outlined, size: 32),
              const SizedBox(height: 6),
              Text(
                t('Cijeli Market'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
