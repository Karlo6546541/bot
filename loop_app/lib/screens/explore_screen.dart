import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../services/demo_accounts.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../widgets/live_shop_widgets.dart';
import '../widgets/pill_tabs.dart';
import '../widgets/user_avatar.dart';
import 'auction_detail_screen.dart';
import 'auctions_screen.dart';
import 'categories_screen.dart';
import 'device_detail_screen.dart';
import 'live_screens.dart';
import 'public_profile_screen.dart';
import 'search_screen.dart';

/// Otvara objavu prema vrsti: live → prijenos, aukcija → detalji aukcije,
/// proizvod s fiksnom cijenom → stranica proizvoda (galerija prirodnog
/// omjera, ne cijeli videoekran).
void openBrowseItem(BuildContext context, BrowseItem item) {
  if (item.show != null) {
    LiveRoomScreen.open(context, item.show!.id);
  } else if (item.auction != null) {
    AuctionDetailScreen.open(context, item.auction!.id);
  } else if (item.device != null) {
    DeviceDetailScreen.open(context, item.device!);
  }
}

/// Istraži: jedno mjesto za proizvode, lajvove, shopove i kategorije, uz
/// pretraživanje proizvoda, prodavača i prijenosa.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final items = browseItems(s);
    final products = [
      for (final i in items)
        if (i.show == null) i,
    ];
    final lives = [
      for (final i in items)
        if (i.show != null) i,
    ];
    final liveNow = [
      for (final i in lives)
        if (i.live?.isLive ?? false) i,
    ];
    final upcoming = [
      for (final i in lives)
        if (i.live?.isScheduled ?? false) i,
    ];
    final shops = s.shops
        .where((u) => u.id != s.currentUserId && !s.isBlocked(u.id))
        .toList();
    final me = s.currentUserId ?? '';

    return DefaultTabController(
      length: 4,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              key: const ValueKey('explore'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          key: const ValueKey('explore-search'),
                          borderRadius: BorderRadius.circular(kRadiusButton),
                          onTap: () => SearchScreen.open(context),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: LoopColors.surface,
                              borderRadius: BorderRadius.circular(
                                kRadiusButton,
                              ),
                              border: Border.all(color: LoopColors.glassBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search,
                                  color: LoopColors.textSecondary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    t('Traži proizvode, prodavače i prijenose'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: LoopColors.textSecondary,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PillTabBar(
                  scrollable: true,
                  tabs: [
                    Tab(
                      key: const ValueKey('explore-tab-products'),
                      text: t('Proizvodi'),
                    ),
                    Tab(
                      key: const ValueKey('explore-tab-lives'),
                      text: t('Lajvovi'),
                    ),
                    Tab(
                      key: const ValueKey('explore-tab-shops'),
                      text: t('Shopovi'),
                    ),
                    Tab(
                      key: const ValueKey('explore-tab-categories'),
                      text: t('Kategorije'),
                    ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _Products(products: products, viewerId: me),
                      _Lives(liveNow: liveNow, upcoming: upcoming),
                      _Shops(shops: shops),
                      const CategoriesScreen(),
                    ],
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

class _Empty extends StatelessWidget {
  const _Empty(this.title, this.message);
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: LoopColors.textSecondary),
          ),
        ],
      ),
    ),
  );
}

class _Products extends StatelessWidget {
  const _Products({required this.products, required this.viewerId});
  final List<BrowseItem> products;
  final String viewerId;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return _Empty(
        t('Još nema proizvoda'),
        t('Novi proizvodi i aukcije pojavit će se ovdje.'),
      );
    }
    return GridView.builder(
      key: const ValueKey('explore-products'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      gridDelegate: const BrowseGridDelegate(),
      itemCount: products.length,
      itemBuilder: (_, i) => AuctionBrowseCard(
        item: products[i],
        viewerId: viewerId,
        onTap: () => openBrowseItem(context, products[i]),
      ),
    );
  }
}

class _Lives extends StatelessWidget {
  const _Lives({required this.liveNow, required this.upcoming});
  final List<BrowseItem> liveNow;
  final List<BrowseItem> upcoming;

  @override
  Widget build(BuildContext context) {
    if (liveNow.isEmpty && upcoming.isEmpty) {
      return _Empty(
        t('Trenutno nema prijenosa'),
        t('Najavljeni prijenosi pojavit će se ovdje.'),
      );
    }
    return ListView(
      key: const ValueKey('explore-lives'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (liveNow.isNotEmpty)
          LayoutBuilder(
            builder: (_, c) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final item in liveNow)
                  SizedBox(
                    width: (c.maxWidth - 12) / 2,
                    child: LiveShopMini(
                      show: item.show!,
                      device: item.device,
                      viewers: item.live!.viewers,
                      priceLabel: livePriceLabel(item.live!),
                      onTap: () => LiveRoomScreen.open(context, item.show!.id),
                    ),
                  ),
              ],
            ),
          ),
        if (upcoming.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
            child: Text(
              t('Uskoro uživo'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          for (final item in upcoming)
            LiveShopRow(
              show: item.show!,
              device: item.device,
              subtitle: formatDateTime(item.show!.startsAt),
              onTap: () => LiveRoomScreen.open(context, item.show!.id),
            ),
        ],
      ],
    );
  }
}

class _Shops extends ConsumerWidget {
  const _Shops({required this.shops});
  final List<dynamic> shops;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    if (shops.isEmpty) {
      return _Empty(
        t('Još nema shopova'),
        t('Shopovi prodavača bit će ovdje.'),
      );
    }
    return ListView(
      key: const ValueKey('explore-shops'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final user in shops)
          Builder(
            builder: (_) {
              final rating = s.ratingOf(user.id);
              final live = s.activeLives.any(
                (e) => e.$1.hostId == user.id && e.$2.isLive,
              );
              final listings = s.listingsOf(user.id).length;
              return InkWell(
                key: ValueKey('explore-shop-${user.id}'),
                borderRadius: BorderRadius.circular(kRadiusButton),
                onTap: () => PublicProfileScreen.open(context, user.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      UserAvatar(user: user, size: 48),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.shopTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                // Ocjena uvijek s brojem recenzija.
                                if (rating.count > 0)
                                  '★ ${rating.average.toStringAsFixed(1)} (${rating.count})'
                                else
                                  t('Još nema recenzija'),
                                t('{0} oglasa', ['$listings']),
                                if (isDemoAccount(user.id)) t('Demo'),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: LoopColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (live)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: LoopColors.live,
                            borderRadius: BorderRadius.circular(kRadiusChip),
                          ),
                          child: Text(
                            t('UŽIVO'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      Icon(
                        Icons.chevron_right,
                        color: LoopColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
