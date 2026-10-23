import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../screens/add_device_screen.dart';
import '../screens/public_profile_screen.dart';
import '../screens/shop_screens.dart';
import '../screens/swipe_feed_screen.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'item_image.dart';
import 'shop_widgets.dart';
import 'user_avatar.dart';

/// Nasumičan redoslijed feeda, isti dok je aplikacija otvorena (da se
/// objave ne premještaju pri svakom osvježavanju).
final feedSeedProvider = Provider<int>((ref) => Random().nextInt(1 << 30));

/// Objava u feedu: oglas (predmet), aukcija ili live aukcija.
class FeedEntry {
  const FeedEntry.item(String id)
    : deviceId = id,
      auctionId = null,
      liveId = null;
  const FeedEntry.auction(String id)
    : auctionId = id,
      deviceId = null,
      liveId = null;
  const FeedEntry.live(String id)
    : liveId = id,
      deviceId = null,
      auctionId = null;

  final String? deviceId;
  final String? auctionId;
  final String? liveId;

  bool get isAuction => auctionId != null;
  bool get isLive => liveId != null;
}

/// Objave za feed: oglasi i aktivne aukcije drugih korisnika, nasumično,
/// ali s prednošću za trgovine koje pratim, istaknute račune, popuste,
/// popularne trgovine i aukcije koje uskoro završavaju.
List<FeedEntry> feedPosts(AppState state, int seed) {
  final rnd = Random(seed);
  final me = state.currentUser;
  final following = me?.following ?? const [];
  final now = DateTime.now();
  double shopBonus(String? ownerId) =>
      (following.contains(ownerId) ? 1.0 : 0) +
      (ownerId != null && (state.userById(ownerId)?.isPromoted ?? false)
          ? 0.8
          : 0) +
      (ownerId == null ? 0 : min(state.followersOf(ownerId) * 0.05, 0.4));
  final scored = <(FeedEntry, double)>[
    for (final d in state.marketDevices)
      if (d.isListed)
        (
          FeedEntry.item(d.id),
          rnd.nextDouble() + shopBonus(d.ownerId) + (d.hasDiscount ? 0.3 : 0),
        ),
    for (final a in state.activeAuctions)
      if (a.sellerId != me?.id &&
          !state.isBlocked(a.sellerId) &&
          !a.isExpired(now) &&
          state.deviceById(a.deviceId) != null)
        (
          FeedEntry.auction(a.id),
          rnd.nextDouble() +
              shopBonus(a.sellerId) +
              0.4 +
              (a.endsAt.difference(now) < const Duration(hours: 1) ? 0.8 : 0),
        ),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (e, _) in scored) e];
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
        // 1. Objave (kao TikTok): mreža + "Gledaj" za listanje.
        if (posts.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: Text(t('Objave'), style: heading)),
              FilledButton.tonalIcon(
                key: const ValueKey('watch-posts'),
                onPressed: () => SwipeFeedScreen.open(context, posts, 0),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(t('Gledaj')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 900
                  ? 5
                  : c.maxWidth >= 600
                  ? 4
                  : 3;
              final shown = posts.take(cols * 2).toList();
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
                  entry: shown[i],
                  state: state,
                  onTap: () => SwipeFeedScreen.open(context, posts, i),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
        // 2. Trgovine.
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
            height: 262,
            child: ListView.separated(
              key: const ValueKey('home-shops'),
              scrollDirection: Axis.horizontal,
              itemCount: shops.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => ShopCard(user: shops[i]),
            ),
          ),
        ],
        // 3. Poziv da i ti otvoriš trgovinu (dok nemaš oglasa).
        if (me != null && !me.isGuest && state.listingsOf(me.id).isEmpty) ...[
          const SizedBox(height: 16),
          _OwnShopBanner(user: me),
        ],
      ],
    );
  }
}

/// Podsjetnik da je svaki račun trgovina.
class _OwnShopBanner extends ConsumerWidget {
  const _OwnShopBanner({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final listings = state.listingsOf(user.id).length;
    final cover = user.coverPath;
    const white = TextStyle(
      color: Colors.white,
      shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
    );
    final background = cover == null
        ? const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF7B2FF7), Color(0xFFFF2D55)],
              ),
            ),
          )
        : LocalPhoto(path: cover, cacheWidth: 1000, fallback: const SizedBox());
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => PublicProfileScreen.open(context, user.id),
        child: Stack(
          children: [
            // Naslovna slika trgovine je pozadina kartice (cijela vidljiva,
            // samo s tamnim prijelazom ispod teksta).
            Positioned.fill(child: background),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: UserAvatar(user: user, size: 48),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listings == 0
                              ? t('Svaki račun je webshop — otvori svoj!')
                              : t('Tvoja trgovina {0}', [user.shopTitle]),
                          style: white.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          t('{0} oglasa · {1} pratitelja · {2} prodaja', [
                            '$listings',
                            '${state.followersOf(user.id)}',
                            '${state.salesCountOf(user.id)}',
                          ]),
                          style: white.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('my-shop-banner'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: listings == 0
                        ? () => AddDeviceScreen.open(context)
                        : () => PublicProfileScreen.open(context, user.id),
                    child: Text(listings == 0 ? t('Objavi') : t('Otvori')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartica trgovine: naslovna slika, profilna slika preko ruba, naziv,
/// pratitelji i ocjena, tri oglasa i "Prati".
class ShopCard extends ConsumerWidget {
  const ShopCard({super.key, required this.user, this.width = 210});
  final AppUser user;
  final double width;

  static const coverHeight = 78.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final items = state.listingsOf(user.id).take(3).toList();
    final rating = state.ratingOf(user.id);
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LoopColors.accent.withValues(alpha: 0.85),
            const Color(0xFF7B2FF7),
          ],
        ),
      ),
    );
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('shop-${user.id}'),
          onTap: () => PublicProfileScreen.open(context, user.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Naslovna slika + profilna slika preko donjeg ruba.
              SizedBox(
                height: coverHeight + 24,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: coverHeight,
                      child: user.coverPath == null
                          ? gradient
                          : LocalPhoto(
                              path: user.coverPath!,
                              cacheWidth: 600,
                              fallback: gradient,
                            ),
                    ),
                    if (user.isPromoted)
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: PromotedBadge(small: true),
                      ),
                    Positioned(
                      left: 10,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: LoopColors.surface,
                            width: 3,
                          ),
                        ),
                        child: UserAvatar(user: user, size: 46),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
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
                        [
                          t('{0} pratitelja', [
                            '${state.followersOf(user.id)}',
                          ]),
                          if (rating.count > 0)
                            '★ ${rating.average.toStringAsFixed(1)}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (var i = 0; i < 3; i++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
                                child: SizedBox(
                                  height: 48,
                                  child: i < items.length
                                      ? LayoutBuilder(
                                          builder: (context, c) => Center(
                                            child: ItemThumb(
                                              device: items[i],
                                              size: min(c.maxWidth, 48),
                                            ),
                                          ),
                                        )
                                      : null,
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Pločica objave u mreži (slika, cijena ili aukcija, prikazi).
class PostTile extends StatelessWidget {
  const PostTile({
    super.key,
    required this.entry,
    required this.state,
    required this.onTap,
  });
  final FeedEntry entry;
  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final auction = entry.isAuction
        ? state.auctionById(entry.auctionId!)
        : null;
    final d = state.deviceById(entry.deviceId ?? auction?.deviceId ?? '');
    if (d == null) return const SizedBox.shrink();
    final photo = d.imagePaths.isEmpty
        ? ItemIllustration(category: d.category, iconSize: 36)
        : LocalPhoto(
            path: d.imagePaths.first,
            cacheWidth: 360,
            fallback: ItemIllustration(category: d.category, iconSize: 36),
          );
    const shadow = [Shadow(blurRadius: 6, color: Colors.black54)];
    const white = TextStyle(color: Colors.white, shadows: shadow);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
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
                    stops: [0.5, 1],
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: auction != null
                    ? const _TileBadge(text: '🔨', color: Color(0xFF7B2FF7))
                    : d.hasDiscount
                    ? DiscountBadge(percent: d.discountPercent, small: true)
                    : const SizedBox.shrink(),
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
                      style: white.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatCredits(
                              auction?.currentPrice ?? d.shownPrice,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: white.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const Icon(
                          Icons.play_arrow_outlined,
                          color: Colors.white,
                          size: 14,
                        ),
                        Text(
                          '${state.viewsOf(d.id)}',
                          style: white.copyWith(fontSize: 11),
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

class _TileBadge extends StatelessWidget {
  const _TileBadge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 11),
    ),
  );
}
