import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../screens/add_device_screen.dart';
import '../screens/public_profile_screen.dart';
import '../screens/shop_screens.dart';
import '../screens/swipe_feed_screen.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'community_widgets.dart';
import 'item_image.dart';
import 'shop_widgets.dart';
import 'user_avatar.dart';

/// Nasumičan redoslijed feeda, isti dok je aplikacija otvorena (da se
/// objave ne premještaju pri svakom osvježavanju).
final feedSeedProvider = Provider<int>((ref) => Random().nextInt(1 << 30));

/// Objave za feed: svi oglasi drugih korisnika, nasumično, ali s prednošću
/// za trgovine koje pratim, istaknute račune, popuste i popularne trgovine.
List<Device> feedPosts(AppState state, int seed) {
  final rnd = Random(seed);
  final me = state.currentUser;
  final following = me?.following ?? const [];
  final scored = [
    for (final d in state.marketDevices)
      if (d.isListed)
        (
          d,
          rnd.nextDouble() +
              (following.contains(d.ownerId) ? 1.0 : 0) +
              (state.isPromotedItem(d) ? 0.8 : 0) +
              (d.hasDiscount ? 0.3 : 0) +
              min(state.followersOf(d.ownerId!) * 0.05, 0.4),
        ),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (d, _) in scored) d];
}

/// Trgovine za feed: istaknute i one s više pratitelja prve, uz malo
/// nasumičnosti, bez onih koje već pratim (njih vidiš kroz objave).
List<AppUser> feedShops(AppState state, int seed) {
  final rnd = Random(seed + 1);
  final me = state.currentUser;
  final scored = [
    for (final u in state.shops)
      if (u.id != me?.id && !state.isBlocked(u.id))
        (
          u,
          rnd.nextDouble() +
              (u.isPromoted ? 2.0 : 0) +
              (state.isFollowing(u.id) ? -1.0 : 0) +
              min(state.followersOf(u.id) * 0.2, 1.5) +
              state.ratingOf(u.id).average * 0.1,
        ),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (u, _) in scored) u];
}

/// Početni feed: poziv da svaki račun otvori trgovinu, trgovine za tebe i
/// mreža objava koje se otvaraju kao TikTok (swipe gore/dolje).
class HomeFeed extends ConsumerWidget {
  const HomeFeed({super.key, required this.onGoToMarket});
  final VoidCallback onGoToMarket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final seed = ref.watch(feedSeedProvider);
    final posts = feedPosts(state, seed);
    final shops = feedShops(state, seed);
    final me = state.currentUser;
    final heading = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (posts.isNotEmpty) ...[
          _WatchButton(
            count: posts.length,
            onTap: () => SwipeFeedScreen.open(context, posts, 0),
          ),
          const SizedBox(height: 16),
        ],
        if (me != null && !me.isGuest) ...[
          _OwnShopBanner(user: me),
          const SizedBox(height: 16),
        ],
        if (shops.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: Text(t('Trgovine za tebe'), style: heading)),
              TextButton(
                key: const ValueKey('all-shops'),
                onPressed: () => ShopsScreen.open(context),
                child: Text(t('Sve trgovine')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 252,
            child: ListView.separated(
              key: const ValueKey('home-shops'),
              scrollDirection: Axis.horizontal,
              itemCount: shops.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => ShopCard(user: shops[i]),
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (posts.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: Text(t('Objave'), style: heading)),
              TextButton.icon(
                key: const ValueKey('open-leaderboard'),
                onPressed: () => LeaderboardScreen.open(context),
                icon: const Icon(Icons.emoji_events_outlined, size: 18),
                label: Text(t('Top prodavatelji')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 900
                  ? 5
                  : c.maxWidth >= 600
                  ? 4
                  : 3;
              final shown = posts.take(cols * 4).toList();
              return GridView.builder(
                key: const ValueKey('home-feed'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 3 / 4,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) => PostTile(
                  device: shown[i],
                  state: state,
                  onTap: () => SwipeFeedScreen.open(context, posts, i),
                ),
              );
            },
          ),
          if (posts.length > 12) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => SwipeFeedScreen.open(context, posts, 0),
              icon: const Icon(Icons.swipe_vertical_outlined),
              label: Text(t('Još {0} objava — listaj', ['${posts.length}'])),
            ),
          ],
        ],
      ],
    );
  }
}

/// Veliki gumb "Gledaj objave" (TikTok način).
class _WatchButton extends StatelessWidget {
  const _WatchButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    borderRadius: BorderRadius.circular(kRadius),
    clipBehavior: Clip.antiAlias,
    child: Ink(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF2D55), Color(0xFF7B2FF7)],
        ),
      ),
      child: InkWell(
        key: const ValueKey('watch-posts'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              const Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('Gledaj objave'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      t('{0} objava iz trgovina — listaj gore i dolje', [
                        '$count',
                      ]),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.swipe_vertical, color: Colors.white),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Podsjetnik da je svaki račun trgovina.
class _OwnShopBanner extends ConsumerWidget {
  const _OwnShopBanner({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final listings = state.listingsOf(user.id).length;
    return Card(
      color: LoopColors.lilac,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            UserAvatar(user: user, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listings == 0
                        ? t('Svaki račun je webshop — otvori svoj!')
                        : t('Tvoja trgovina {0}', [user.shopTitle]),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    t('{0} oglasa · {1} pratitelja · {2} prodaja', [
                      '$listings',
                      '${state.followersOf(user.id)}',
                      '${state.salesCountOf(user.id)}',
                    ]),
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('my-shop-banner'),
              onPressed: listings == 0
                  ? () => AddDeviceScreen.open(context)
                  : () => PublicProfileScreen.open(context, user.id),
              child: Text(listings == 0 ? t('Objavi') : t('Otvori')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartica trgovine: avatar, naziv, ocjena, pratitelji, 3 oglasa, Prati.
class ShopCard extends ConsumerWidget {
  const ShopCard({super.key, required this.user, this.width = 200});
  final AppUser user;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final items = state.listingsOf(user.id).take(3).toList();
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('shop-${user.id}'),
          onTap: () => PublicProfileScreen.open(context, user.id),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(user: user, size: 40),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.shopTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            t('{0} pratitelja', [
                              '${state.followersOf(user.id)}',
                            ]),
                            style: TextStyle(
                              color: LoopColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: RatingBadge(
                        rating: state.ratingOf(user.id),
                        compact: true,
                      ),
                    ),
                    if (user.isPromoted) ...[
                      const SizedBox(width: 4),
                      const PromotedBadge(small: true),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: i < items.length
                                ? LayoutBuilder(
                                    builder: (context, c) => ItemThumb(
                                      device: items[i],
                                      size: c.maxWidth,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FollowButton(userId: user.id, compact: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pločica objave u mreži (slika, cijena, prikazi).
class PostTile extends StatelessWidget {
  const PostTile({
    super.key,
    required this.device,
    required this.state,
    required this.onTap,
  });
  final Device device;
  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final photo = d.imagePaths.isEmpty
        ? ItemIllustration(category: d.category, iconSize: 36)
        : LocalPhoto(
            path: d.imagePaths.first,
            cacheWidth: 360,
            fallback: ItemIllustration(category: d.category, iconSize: 36),
          );
    const shadow = [Shadow(blurRadius: 6, color: Colors.black54)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              photo,
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                    stops: [0.55, 1],
                  ),
                ),
              ),
              if (d.hasDiscount)
                Positioned(
                  top: 6,
                  left: 6,
                  child: DiscountBadge(percent: d.discountPercent, small: true),
                ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        shadows: shadow,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatCredits(d.shownPrice),
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              shadows: shadow,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.play_arrow_outlined,
                          color: Colors.white,
                          size: 14,
                        ),
                        Text(
                          '${state.viewsOf(d.id)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            shadows: shadow,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
