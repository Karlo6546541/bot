import '../config/design_variant.dart';
import '../widgets/pill_tabs.dart';
import '../widgets/category_style.dart';
import '../widgets/discovery_live_card.dart';
import '../widgets/adaptive_shell.dart' show LoopLogo;
import '../config/backend_config.dart';
import 'cloud_commerce_screen.dart';
import '../config/features.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../widgets/user_avatar.dart';
import '../models/app_user.dart';
import '../models/device.dart';
import '../widgets/browse_category_picker.dart';
import '../providers/app_state.dart';
import 'categories_screen.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/trade_actions.dart';
import 'auctions_screen.dart';
import 'public_profile_screen.dart';
import 'live_screens.dart';
import 'search_screen.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';
import 'swipe_feed_screen.dart';
import 'for_you_ranker.dart';
import '../widgets/live_shop_widgets.dart';
import '../widgets/vision_glass.dart';
import '../widgets/formatters.dart';

/// Početna kao Whatnot: pretraga, kategorije kao "pilule" i mreža kartica —
/// tko je uživo sada, što uskoro kreće, aukcije koje završavaju i predmeti
/// za Kupi odmah. Dodir na karticu otvara swipe feed te skupine.
class LiveHomeScreen extends ConsumerStatefulWidget {
  const LiveHomeScreen({
    super.key,
    this.visible = true,
    this.onImmersiveChanged,
  });
  final ValueChanged<bool>? onImmersiveChanged;

  /// Je li tab Početna na ekranu (feed "Za tebe" pušta live samo tada).
  final bool visible;

  @override
  ConsumerState<LiveHomeScreen> createState() => _LiveHomeScreenState();
}

/// Filter na početnoj: za tebe, uživo, uskoro ili kategorija.
sealed class _Filter {
  const _Filter();

  String get id => switch (this) {
    _ForYou() => 'for-you',
    _LiveOnly() => 'live',
    _Soon() => 'soon',
    _Timed() => 'timed',
    _BuyNow() => 'buy',
    _Digital() => 'digital',
    _Following() => 'following',
  };

  static _Filter of(String id) => switch (id) {
    // Stare poveznice (Live shop / Live aukcije) vode na Live show.
    'live' || 'live-shop' || 'live-auctions' => const _LiveOnly(),
    'soon' => const _Soon(),
    'timed' => const _Timed(),
    // Kupi odmah je isključen (stare poveznice vode na Za tebe).
    'buy' when kBuyNowEnabled && !kSimpleDesign => const _BuyNow(),
    'digital' when kBuyNowEnabled => const _Digital(),
    'following' => const _Following(),
    _ => const _ForYou(),
  };
}

class _ForYou extends _Filter {
  const _ForYou();
}

class _LiveOnly extends _Filter {
  const _LiveOnly();
}

class _Soon extends _Filter {
  const _Soon();
}

class _Timed extends _Filter {
  const _Timed();
}

class _BuyNow extends _Filter {
  const _BuyNow();
}

class _Digital extends _Filter {
  const _Digital();
}

class _Following extends _Filter {
  const _Following();
}

class _LiveHomeScreenState extends ConsumerState<LiveHomeScreen> {
  void _select(_Filter filter) {
    ref.read(homeFilterProvider.notifier).select(filter.id);
    // Početna je uvijek mreža (kao Whatnot); feed preko cijelog ekrana
    // otvara se tek dodirom na karticu.
    widget.onImmersiveChanged?.call(false);
  }

  /// Kategorije za brzi izbor livea: samo one s liveovima (najviše
  /// gledatelja prve).
  static List<CategoryStat> _liveCategoryStats(
    AppState s, {
    DeviceCategory? keep,
  }) {
    final stats = categoryStats(s);
    final live = [
      for (final c in stats)
        if (c.viewers > 0) c,
    ]..sort((a, b) => b.viewers.compareTo(a.viewers));
    // Samo kategorije u kojima je netko uživo (bez pločica "Nema livea").
    final list = live.take(10).toList();
    // Odabrana kategorija uvijek je u traci (i kad nema livea).
    if (keep != null && !list.any((c) => c.category == keep)) {
      list.insert(0, stats.firstWhere((c) => c.category == keep));
    }
    return list;
  }

  /// Kategorije koje stvarno postoje: imaju prijenos ili proizvod, od
  /// najzastupljenijih (najviše osam).
  static List<DeviceCategory> _existingCategories(AppState s) {
    final counts = <DeviceCategory, int>{};
    for (final i in browseItems(s)) {
      for (final c in i.categories) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    final list = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return list.take(8).toList();
  }

  Timer? _timer;
  bool _searchOpen = false;
  String _query = '';
  final _inlineSearch = TextEditingController();
  _Filter get _filter => _Filter.of(ref.read(homeFilterProvider));

  /// Swipe follows the visible Live, Shop and Following tabs.
  static const _swipeTabs = ['for-you', 'buy', 'following'];

  void _swipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 350) return;
    final i = _swipeTabs.indexOf(_filter.id);
    if (i < 0) {
      // Ostali prikazi (Aukcije, Kupi odmah…): swipe vraća na Za tebe.
      _select(const _ForYou());
      return;
    }
    final next = v < 0 ? i + 1 : i - 1;
    if (next >= _swipeTabs.length) {
      SearchScreen.open(context);
    } else if (next >= 0) {
      _select(_Filter.of(_swipeTabs[next]));
    }
  }

  /// Digitalne kupnje: prikaz kupljenog (inače "Kupi").
  bool _digitalOwned = false;
  bool _hideCheckout = false;
  DeviceCategory? _liveCategory;

  /// Odabrana kategorija (traka ispod tabova): filtrira sve prikaze.
  DeviceCategory? _cat;

  /// Traka kategorija se sažima kad se lista prema dolje.
  bool _catCompact = false;
  DeviceCategory? _auctionCategory;

  @override
  void initState() {
    super.initState();

    if (ref.read(tickIntervalProvider) != null) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        // The swipe feed manages its own queue. Avoid rebuilding it every 5 s.
        if (mounted && widget.visible && _filter is! _ForYou) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _inlineSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(homeFilterProvider);
    final s = ref.watch(appProvider);
    final me = s.currentUserId ?? '';
    final all = [
      for (final i in browseItems(s))
        if ((_cat == null || i.categories.contains(_cat)) &&
            (_query.trim().isEmpty ||
                '${i.show?.title ?? ''} ${i.show?.hostLabel ?? ''} ${i.device?.name ?? ''} ${kSimpleDesign ? '${s.userById(i.device?.ownerId ?? i.show?.hostId)?.shopTitle ?? ''} ${s.userById(i.device?.ownerId ?? i.show?.hostId)?.username ?? ''}' : ''}'
                    .toLowerCase()
                    .contains(_query.trim().toLowerCase())))
          i,
    ];
    final allLive = all.where((i) => i.live?.isLive ?? false).toList();
    final live = _promotedOnTop(
      allLive
          .where(
            (i) =>
                _liveCategory == null || i.categories.contains(_liveCategory),
          )
          .toList(),
    );
    final soon = _promotedOnTop(
      all.where((i) => i.live?.isScheduled ?? false).toList(),
    );
    final allAuctions = all.where((i) => i.auction != null).toList();
    final auctions = allAuctions
        .where(
          (i) =>
              _auctionCategory == null ||
              i.categories.contains(_auctionCategory),
        )
        .toList();
    final reserved = liveShopReservedIds(s);
    final buyNow = all
        .where((i) => i.isBuyNow && !reserved.contains(i.device?.id))
        .toList();
    final digital = buyNow.where((i) => i.device?.isDigital ?? false).toList();

    void open(List<BrowseItem> list, int i, String title) {
      // Signal za "Za tebe": što otvaraš (samo na ovom uređaju).
      ref.read(storageProvider).addRecentCategories([
        for (final c in list[i].categories) c.name,
      ]);
      SwipeFeedScreen.open(
        context,
        [for (final x in list) x.entry],
        i,
        title: title,
      );
    }

    Widget grid(String key, List<BrowseItem> list, String title) =>
        SliverPadding(
          key: ValueKey(key),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: BrowseGridDelegate(
              textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => AuctionBrowseCard(
                item: list[i],
                viewerId: me,
                onTap: () => open(list, i, title),
              ),
              childCount: list.length,
            ),
          ),
        );

    // Računi koje pratiš i njihove objave (liveovi, aukcije, Kupi odmah).
    final following =
        _filter is! _Following ||
            s.currentUser == null ||
            s.currentUser!.isGuest
        ? const <AppUser>[]
        : s.followingListOf(me);
    final followIds = {for (final u in following) u.id};
    final theirs = [
      for (final i in all)
        if (followIds.contains(
          i.show?.hostId ?? i.auction?.sellerId ?? i.device?.ownerId,
        ))
          i,
    ];

    // Kompaktne vizualne kartice showova (2 stupca na mobitelu).
    Widget showsGrid(String key, List<BrowseItem> list, {bool soon = false}) =>
        SliverPadding(
          key: ValueKey(key),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverLayoutBuilder(
            builder: (context, c) {
              final cols = c.crossAxisExtent >= 900
                  ? 5
                  : c.crossAxisExtent >= 600
                  ? 3
                  : 2;
              final w = (c.crossAxisExtent - (cols - 1) * 12) / cols;
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  mainAxisExtent: w * 4 / 3 + 66 * scale.clamp(1, 2),
                ),
                delegate: SliverChildBuilderDelegate((_, index) {
                  final item = list[index];
                  final show = item.show!;
                  return LiveGridCard(
                    key: ValueKey('home-featured-live-${show.id}'),
                    show: show,
                    host: s.userById(show.hostId),
                    device: item.device,
                    soon: soon,
                    badge: soon ? formatDateTime(show.startsAt) : null,
                    priceLabel: soon ? null : livePriceLabel(item.live!),
                    viewers: soon ? 0 : item.live!.viewers,
                    onTap: () => LiveRoomScreen.open(context, show.id),
                    onHost: () =>
                        PublicProfileScreen.open(context, show.hostId),
                  );
                }, childCount: list.length),
              );
            },
          ),
        );

    final slivers = <Widget>[];
    switch (_filter) {
      case _Following():
        if (following.isEmpty) {
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                key: const ValueKey('home-following-empty'),
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.currentUser?.isGuest ?? true
                      ? t(
                          'Prijavi se i prati prodavače — njihovi oglasi bit će ovdje.',
                        )
                      : t(
                          'Još nikoga ne pratiš. Dodirni "Prati" na liveu ili trgovini.',
                        ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: LoopColors.textSecondary),
                ),
              ),
            ),
          );
        } else {
          slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
          slivers.add(
            SliverToBoxAdapter(
              child: _FollowingRow(
                users: following,
                liveBy: {for (final i in allLive) i.show!.hostId: i},
                onLive: (i) => open([i], 0, t('Uživo')),
              ),
            ),
          );
          slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 12)));
          final theirShows = [
            for (final i in theirs)
              if (i.show != null && i.live != null) i,
          ];
          slivers.add(
            theirShows.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        t('Prodavači koje pratiš trenutno nemaju prijenosa.'),
                        style: TextStyle(color: LoopColors.textSecondary),
                      ),
                    ),
                  )
                : showsGrid(
                    'home-following',
                    theirShows,
                    soon: !theirShows.any((i) => i.live!.isLive),
                  ),
          );
        }
      case _ForYou():
        final storage = ref.read(storageProvider);
        final ranked =
            ForYouRanker(
                  s,
                  now: DateTime.now(),
                  recentCategories: storage.recentCategories,
                  preferences: storage.feedPreferences(s.currentUserId),
                )
                .rankBatch(
                  all.where((item) => item.live != null).toList(),
                  limit: 60,
                )
                .map((p) => p.item)
                .toList();
        final liveNow = [
          for (final i in ranked)
            if (i.live?.isLive ?? false) i,
        ];
        final upcoming = [
          for (final i in ranked)
            if (i.live?.isScheduled ?? false) i,
        ];
        if (kSimpleDesign) {
          Widget sectionTitle(
            String label, {
            bool live = false,
            VoidCallback? onAll,
          }) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                if (live) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: LoopColors.live,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.4,
                    ),
                  ),
                ),
                if (onAll != null)
                  TextButton(onPressed: onAll, child: Text(t('Prikaži sve'))),
              ],
            ),
          );
          if (liveNow.isNotEmpty) {
            slivers.add(
              SliverToBoxAdapter(
                child: sectionTitle(t('Uživo sada'), live: true),
              ),
            );
            slivers.add(showsGrid('home-live-discovery', liveNow));
          } else {
            slivers.add(
              SliverToBoxAdapter(
                child: Padding(
                  key: const ValueKey('home-no-live'),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text(
                    t('Trenutno nema prijenosa uživo.'),
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ),
              ),
            );
          }
          if (upcoming.isNotEmpty) {
            slivers.add(
              SliverToBoxAdapter(
                child: sectionTitle(
                  t('Nadolazeći showovi'),
                  onAll: () => _select(const _Soon()),
                ),
              ),
            );
            slivers.add(showsGrid('home-upcoming', upcoming, soon: true));
          }
          // Prodavači bez aktivnog ili najavljenog showa: zaseban kompaktan
          // red; dodir otvara profil (show ne postoji).
          final withShow = {
            for (final i in liveNow) i.show!.hostId,
            for (final i in upcoming) i.show!.hostId,
          };
          final others =
              <String>{
                for (final u in s.users)
                  if (u.id != me &&
                      !u.isGuest &&
                      !u.pendingDeletion &&
                      !withShow.contains(u.id) &&
                      s.listingsOf(u.id).isNotEmpty)
                    u.id,
              }.toList()..sort((a, b) {
                final c = s.followersOf(a).compareTo(s.followersOf(b));
                return c != 0 ? c : a.compareTo(b);
              });
          final sellers = others.take(10).toList();
          if (sellers.isNotEmpty) {
            slivers.add(
              SliverToBoxAdapter(
                child: sectionTitle(t('Preporučeni prodavači')),
              ),
            );
            slivers.add(
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      72 +
                      36 *
                          (MediaQuery.textScalerOf(context).scale(14) / 14)
                              .clamp(1.0, 2.0),
                  child: ListView.separated(
                    key: const ValueKey('home-sellers'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: sellers.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, index) {
                      final id = sellers[index];
                      final user = s.userById(id);
                      final count = s.listingsOf(id).length;
                      return _SellerChip(
                        key: ValueKey('home-seller-$id'),
                        user: user,
                        subtitle: t('{0} proizvoda', ['$count']),
                        onTap: () => PublicProfileScreen.open(context, id),
                      );
                    },
                  ),
                ),
              ),
            );
          }
          break;
        }
        Widget section(Widget child, {Key? key}) => SliverPadding(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverToBoxAdapter(child: child),
        );
        Widget heading(String title, {VoidCallback? onAll}) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: kSimpleDesign
                    ? Text(
                        title.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600,
                          color: LoopColors.textSecondary,
                        ),
                      )
                    : VisionSectionLabel(title),
              ),
              if (onAll != null)
                TextButton(onPressed: onAll, child: Text(t('Prikaži sve'))),
            ],
          ),
        );
        slivers.add(
          const SliverToBoxAdapter(
            key: ValueKey('home-for-you'),
            child: SizedBox(height: 12),
          ),
        );
        if (liveNow.isNotEmpty) {
          final featured = liveNow.first;
          if (!kSimpleDesign) {
            slivers.add(
              section(
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: VisionSectionLabel(t('Pozornica uživo')),
                ),
              ),
            );
          }
          slivers.add(
            section(
              LiveShopFeature(
                key: ValueKey('home-featured-live-${featured.show!.id}'),
                show: featured.show!,
                host: s.userById(featured.show!.hostId),
                device: featured.device,
                viewers: featured.live!.viewers,
                price: featured.live!.current?.price,
                onTap: () => LiveRoomScreen.open(context, featured.show!.id),
              ),
              key: const ValueKey('home-for-you-live'),
            ),
          );
          if (liveNow.length > 1) {
            slivers.add(section(heading(t('Sljedeće u prijenosu'))));
            slivers.add(
              section(
                LayoutBuilder(
                  builder: (context, constraints) => Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final item in liveNow.skip(1))
                          SizedBox(
                            width: (constraints.maxWidth - 16) / 2,
                            child: LiveShopMini(
                              show: item.show!,
                              device: item.device,
                              viewers: item.live!.viewers,
                              priceLabel: livePriceLabel(item.live!),
                              price: item.live!.current?.price,
                              onTap: () =>
                                  LiveRoomScreen.open(context, item.show!.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        } else if (kSimpleDesign && buyNow.isNotEmpty) {
          final product = buyNow.first.device!;
          slivers.add(
            section(
              StageFeatureCard(
                key: const ValueKey('stage-shop-feature'),
                media: BrowseCardMedia(device: product),
                title: product.name,
                subtitle:
                    '${t('Shop')} · ${formatCredits(s.priceForMe(product))}',
                actionLabel: t('Pogledaj'),
                onTap: () => open(buyNow, 0, t('Shop')),
              ),
            ),
          );
        } else if (upcoming.isEmpty) {
          slivers.add(
            section(
              _EmptyLive(
                onGoLive: () => CreateLiveShowScreen.open(context),
                onShop: () => _select(const _BuyNow()),
              ),
            ),
          );
        }
        if (upcoming.isNotEmpty) {
          slivers.add(
            section(
              heading(t('Uskoro uživo'), onAll: () => _select(const _Soon())),
            ),
          );
          slivers.add(
            section(
              Column(
                children: [
                  for (final item in upcoming)
                    LiveShopRow(
                      show: item.show!,
                      device: item.device,
                      subtitle: formatDateTime(item.show!.startsAt),
                      onTap: () => LiveRoomScreen.open(context, item.show!.id),
                    ),
                ],
              ),
            ),
          );
        }
        if (kSimpleDesign && liveNow.isEmpty && buyNow.isNotEmpty) {
          slivers.add(
            section(
              heading(t('Iz shopa'), onAll: () => _select(const _BuyNow())),
            ),
          );
          slivers.add(
            grid('home-shop-discovery', buyNow.take(4).toList(), t('Shop')),
          );
        }
      case _Timed():
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Text(
                t('Aukcije'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
        slivers.add(
          auctions.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      t('Trenutno nema aukcija.'),
                      style: TextStyle(color: LoopColors.textSecondary),
                    ),
                  ),
                )
              : grid('home-ending', auctions, t('Aukcije')),
        );
      case _Digital():
        // Digitalno: odvojeno "Kupi" (još nije kupljeno) i "Kupljeno"
        // (preuzimanje).
        final boughtIds = {for (final d in s.myDigitalPurchases) d.id};
        final toBuy = [
          for (final i in digital)
            if (!boughtIds.contains(i.device?.id)) i,
        ];
        final owned = [
          for (final d in s.myDigitalPurchases) BrowseItem.item(d),
        ];
        final list = _digitalOwned ? owned : toBuy;
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('digital-buy'),
                    avatar: const Icon(Icons.shopping_cart_outlined, size: 18),
                    label: Text(t('Kupi ({0})', ['${toBuy.length}'])),
                    selected: !_digitalOwned,
                    onSelected: (_) => setState(() => _digitalOwned = false),
                  ),
                  ChoiceChip(
                    key: const ValueKey('digital-owned'),
                    avatar: const Icon(Icons.download_done, size: 18),
                    label: Text(t('Kupljeno ({0})', ['${owned.length}'])),
                    selected: _digitalOwned,
                    onSelected: (_) => setState(() => _digitalOwned = true),
                  ),
                ],
              ),
            ),
          ),
        );
        slivers.add(
          list.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _digitalOwned
                          ? t('Još nemaš digitalnih kupnji.')
                          : t('Trenutno nema digitalnih proizvoda.'),
                      style: TextStyle(color: LoopColors.textSecondary),
                    ),
                  ),
                )
              : grid(
                  _digitalOwned ? 'home-digital-owned' : 'home-digital',
                  list,
                  t('Digitalne kupnje'),
                ),
        );
      case _BuyNow():
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 12)));
        slivers.add(
          buyNow.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      t('Još nema predmeta za Kupi odmah.'),
                      style: TextStyle(color: LoopColors.textSecondary),
                    ),
                  ),
                )
              : grid('home-buy', buyNow, t('Kupi odmah')),
        );
      case _LiveOnly():
        if (BackendConfig.cloudLiveEnabled &&
            BackendConfig.cloudCommerceEnabled &&
            ref.read(syncProvider) != null) {
          slivers.add(
            const SliverFillRemaining(
              child: CloudCommerceScreen(liveOnly: true, embedded: true),
            ),
          );
          break;
        }
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 12)));
        slivers.add(
          live.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _liveCategory == null
                        ? _EmptyLive(
                            onGoLive: () => CreateLiveShowScreen.open(context),
                          )
                        : Column(
                            children: [
                              const SizedBox(height: 20),
                              Text(
                                t('Trenutno nema liveova u ovoj kategoriji.'),
                                textAlign: TextAlign.center,
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _liveCategory = null),
                                child: Text(t('Sve kategorije')),
                              ),
                            ],
                          ),
                  ),
                )
              : SliverPadding(
                  key: const ValueKey('home-live'),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList.builder(
                    itemCount: live.length,
                    itemBuilder: (_, i) => LiveShopRow(
                      key: ValueKey('browse-live-${live[i].show!.id}'),
                      show: live[i].show!,
                      device: live[i].device,
                      subtitle: live[i].live!.viewers > 0
                          ? t('{0} gledatelja', ['${live[i].live!.viewers}'])
                          : null,
                      onTap: () => open(live, i, t('Uživo sada')),
                    ),
                  ),
                ),
        );
        if (kSimpleDesign && live.isEmpty) {
          // Bez praznog ekrana: najavljeni prijenosi i dostupni proizvodi.
          if (soon.isNotEmpty) {
            slivers.add(
              SliverPadding(
                key: const ValueKey('home-live-soon'),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList.list(
                  children: [
                    for (final item in soon)
                      LiveShopRow(
                        show: item.show!,
                        device: item.device,
                        subtitle: formatDateTime(item.show!.startsAt),
                        onTap: () =>
                            LiveRoomScreen.open(context, item.show!.id),
                      ),
                  ],
                ),
              ),
            );
          }
          if (buyNow.isNotEmpty) {
            slivers.add(
              grid(
                'home-live-empty-products',
                buyNow.take(8).toList(),
                t('Shop'),
              ),
            );
          }
        }
      case _Soon():
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 12)));
        slivers.add(
          soon.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      t('Nema zakazanih liveova.'),
                      style: TextStyle(color: LoopColors.textSecondary),
                    ),
                  ),
                )
              : showsGrid('home-soon', soon, soon: true),
        );
    }

    Future<void> filters() async {
      final picked = await showModalBottomSheet<Object>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: const ValueKey('home-help'),
                  leading: const Icon(Icons.help_outline),
                  title: Text(t('Kako Subhasto radi')),
                  onTap: () => Navigator.pop(ctx, 'help'),
                ),
                if (!kSimpleDesign)
                  ListTile(
                    key: const ValueKey('home-profile'),
                    leading: const Icon(Icons.person_outline),
                    title: Text(t('Profil')),
                    onTap: () => Navigator.pop(ctx, 'profile'),
                  ),
                if (!kSimpleDesign)
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(t('Poruke')),
                    onTap: () => Navigator.pop(ctx, 'messages'),
                  ),
                if (!kSimpleDesign)
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(t('Obavijesti')),
                    onTap: () => Navigator.pop(ctx, 'notifications'),
                  ),
                for (final (id, label, icon, value)
                    in <(String, String, IconData, Object)>[
                      if (kSimpleDesign) ...[
                        (
                          'following',
                          t('Pratim'),
                          Icons.people_outline,
                          const _Following(),
                        ),
                      ],
                      (
                        'live',
                        t('Uživo po kategoriji'),
                        Icons.videocam_outlined,
                        const _LiveOnly(),
                      ),
                      (
                        'categories',
                        t('Kategorije'),
                        Icons.grid_view,
                        'categories',
                      ),
                      if (kBuyNowEnabled)
                        (
                          'digital',
                          t('Digitalne kupnje'),
                          Icons.download_outlined,
                          const _Digital(),
                        ),
                      ('soon', t('Uskoro'), Icons.event, const _Soon()),
                      ('timed', t('Aukcije'), Icons.gavel, const _Timed()),
                      if (kBuyNowEnabled)
                        (
                          'buy',
                          t('Kupi odmah'),
                          Icons.shopping_bag_outlined,
                          const _BuyNow(),
                        ),
                    ])
                  ListTile(
                    key: ValueKey('home-cat-$id'),
                    leading: Icon(icon),
                    title: Text(label),
                    onTap: () => Navigator.pop(ctx, value),
                  ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || !context.mounted) return;
      if (picked == 'help') {
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => _HowLoopWorks(
            expanded: true,
            onClose: () => Navigator.pop(context),
          ),
        );
      } else if (picked == 'profile') {
        ref.read(homeTabProvider.notifier).select(3);
      } else if (picked == 'messages') {
        await MessagesScreen.open(context);
      } else if (picked == 'notifications') {
        await NotificationsScreen.open(context);
      } else if (picked == 'categories') {
        await CategoriesScreen.open(context);
      } else if (picked is _Filter) {
        _select(picked);
      }
    }

    final width = MediaQuery.sizeOf(context).width;
    final small = width < 375;
    Widget headerButton(String label, Key key, VoidCallback action) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: VisionGlass(
        radius: 99,
        child: TextButton(
          key: key,
          style: TextButton.styleFrom(
            foregroundColor: LoopColors.textPrimary,
            minimumSize: const Size(0, 34),
            padding: EdgeInsets.symmetric(horizontal: small ? 9 : 12),
            textStyle: TextStyle(
              fontSize: small ? 11 : 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          onPressed: action,
          child: Text(label),
        ),
      ),
    );
    final browseControls = Row(
      children: [
        Expanded(
          child: _TileRow(
            selected: _filter.id,
            category: _cat,
            categories: _existingCategories(s),
            onCategory: (category) => setState(() => _cat = category),
            onSelect: _select,
          ),
        ),
        if (!kSimpleDesign)
          IconButton(
            key: const ValueKey('home-filters'),
            tooltip: t('Filteri'),
            onPressed: filters,
            icon: const Icon(Icons.tune, size: 20),
          ),
        const SizedBox(width: 8),
      ],
    );
    // Zaglavlje: logo, tekstualni tabovi Za tebe / Pratim, pretraga, poruke i
    // obavijesti; ispod tekstualni tabovi Sve / Uskoro / kategorije.
    Widget glassHeader() {
      Widget textTab({
        required Key key,
        required String label,
        required bool on,
        required VoidCallback onTap,
        double size = 18,
      }) => Semantics(
        button: true,
        selected: on,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 2.5,
                  color: on ? LoopColors.textPrimary : Colors.transparent,
                ),
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: size,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? LoopColors.textPrimary : LoopColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
      Widget filterChip({
        required Key key,
        required String label,
        required bool on,
        required VoidCallback onTap,
      }) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            key: key,
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on
                    ? LoopColors.textPrimary
                    : LoopColors.textPrimary.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: on ? LoopColors.background : LoopColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      );
      final soon = _filter is _Soon;
      final following = _filter is _Following;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skica: pretraga (pilula) + poruke i obavijesti u istom retku.
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: t('Pretraži prijenose i prodavače'),
                  excludeSemantics: true,
                  child: InkWell(
                    key: const ValueKey('home-search'),
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => SearchScreen.open(context),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: LoopColors.textPrimary.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            size: 22,
                            color: LoopColors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              t('Pretraži prijenose i prodavače'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                color: LoopColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButtonTheme(
                data: IconButtonThemeData(
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    fixedSize: const Size(44, 44),
                    minimumSize: const Size(44, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [MessagesButton(), NotificationBell()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Glavni tabovi: jedan red (Za tebe, Pratim, Uskoro).
          Row(
            key: const ValueKey('home-tabs'),
            children: [
              Expanded(
                child: textTab(
                  key: const ValueKey('home-view-for-you'),
                  label: t('Za tebe'),
                  on: !following && !soon,
                  onTap: () {
                    if (_filter is! _ForYou) _select(const _ForYou());
                  },
                ),
              ),
              Expanded(
                child: textTab(
                  key: const ValueKey('home-view-following'),
                  label: t('Pratim'),
                  on: following,
                  onTap: () => _select(const _Following()),
                ),
              ),
              Expanded(
                child: textTab(
                  key: const ValueKey('home-view-soon'),
                  label: t('Uskoro'),
                  on: soon,
                  onTap: () => _select(const _Soon()),
                ),
              ),
            ],
          ),
          Divider(
            height: 1,
            color: LoopColors.textPrimary.withValues(alpha: .08),
          ),
          // Zaseban red filtara: kategorije (ne miješaju se s tabovima).
          SizedBox(
            height: 48,
            child: ListView(
              key: const ValueKey('home-categories'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                filterChip(
                  key: const ValueKey('home-cat-all'),
                  label: t('Sve'),
                  on: _cat == null,
                  onTap: () => setState(() => _cat = null),
                ),
                for (final c in _existingCategories(s))
                  filterChip(
                    key: ValueKey('home-category-${c.name}'),
                    label: c.label,
                    on: _cat == c,
                    onTap: () => setState(() => _cat = _cat == c ? null : c),
                  ),
                filterChip(
                  key: const ValueKey('home-all-categories'),
                  label: '${t('Kategorije')} ›',
                  on: false,
                  onTap: () => ref.read(homeTabProvider.notifier).select(1),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final chips = SafeArea(
      bottom: false,
      child: Padding(
        key: const ValueKey('home-cats'),
        padding: kSimpleDesign
            ? const EdgeInsets.fromLTRB(16, 8, 8, 0)
            : EdgeInsets.fromLTRB(small ? 16 : 24, 20, small ? 16 : 24, 12),
        child: Column(
          children: [
            if (kSimpleDesign)
              glassHeader()
            else
              LayoutBuilder(
                builder: (context, box) {
                  final logo = LoopLogo(size: small ? 22 : 25);
                  final actions = <Widget>[
                    headerButton(
                      t('Pretraži'),
                      const ValueKey('home-search'),
                      () => setState(() => _searchOpen = !_searchOpen),
                    ),
                  ];
                  if (MediaQuery.textScalerOf(context).scale(14) / 14 > 1.2) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        logo,
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            for (final action in actions)
                              Expanded(child: action),
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(
                        width: box.maxWidth * .28,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: logo,
                        ),
                      ),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: actions,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: !_searchOpen
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        children: [
                          TextField(
                            key: const ValueKey('home-inline-search'),
                            controller: _inlineSearch,
                            autofocus: true,
                            onChanged: (value) =>
                                setState(() => _query = value),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (value) =>
                                SearchScreen.open(context, initialQuery: value),
                            decoration: InputDecoration(
                              hintText: t(
                                'Pronađi predmet u prijenosima uživo…',
                              ),
                              suffixIcon: IconButton(
                                tooltip: t('Pretraži objave i račune'),
                                icon: const Icon(Icons.arrow_forward),
                                onPressed: () => SearchScreen.open(
                                  context,
                                  initialQuery: _query,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const MessagesButton(),
                              const NotificationBell(),
                              IconButton(
                                tooltip: t('Profil'),
                                icon: const Icon(Icons.person_outline),
                                onPressed: () => ref
                                    .read(homeTabProvider.notifier)
                                    .select(3),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );

    final onLive = _filter is _LiveOnly;
    final onAuctions = _filter is _Timed;
    final selectedCategory = onLive
        ? _liveCategory
        : onAuctions
        ? _auctionCategory
        : null;
    Future<void> categories() async {
      if (!onLive && !onAuctions) {
        await CategoriesScreen.open(context);
        return;
      }
      final counts = <DeviceCategory, int>{};
      for (final item in onLive ? allLive : allAuctions) {
        for (final c in item.categories) {
          counts[c] = (counts[c] ?? 0) + 1;
        }
      }
      final picked = await pickBrowseCategory(
        context,
        title: onLive ? t('Kategorije uživo') : t('Kategorije aukcija'),
        keyPrefix: onLive ? 'live-category' : 'auction-category',
        counts: counts,
        selected: selectedCategory,
      );
      if (picked == null || !mounted) return;
      setState(() {
        if (onLive) {
          _liveCategory = picked.category;
        } else {
          _auctionCategory = picked.category;
        }
      });
    }

    final categoryFilter = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          key: ValueKey(
            onLive ? 'live-category-filter' : 'auction-category-filter',
          ),
          avatar: const Icon(Icons.filter_list, size: 16),
          label: Text(selectedCategory?.label ?? t('Sve kategorije')),
          onPressed: categories,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );

    final content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _filter is _ForYou ? (kSimpleDesign ? 1080 : 480) : 1200,
        ),
        child: Column(
          children: [
            if (!kSimpleDesign) chips,
            if (!kSimpleDesign) browseControls,
            // Dolje kategorije: odabrana ostaje označena i filtrira prikaz.
            if (onLive && !kSimpleDesign)
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _LiveCategoryStrip(
                  stats: _liveCategoryStats(s, keep: _cat),
                  selected: _cat,
                  compact: _catCompact,
                  onSelect: (c) => setState(() => _cat = _cat == c ? null : c),
                ),
              ),
            Expanded(
              child: GestureDetector(
                key: const ValueKey('home-swipe'),
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: _swipe,
                child: NotificationListener<ScrollUpdateNotification>(
                  onNotification: (n) {
                    if (n.depth != 0) return false;
                    final compact = n.metrics.pixels > 60;
                    if (compact != _catCompact) {
                      setState(() => _catCompact = compact);
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    slivers: [
                      if (kSimpleDesign) SliverToBoxAdapter(child: chips),
                      if ((onLive || onAuctions) && !kSimpleDesign)
                        SliverToBoxAdapter(child: categoryFilter),
                      ...slivers,
                      if (!_hideCheckout &&
                          s.currentUser != null &&
                          !s.currentUser!.isGuest &&
                          !s.currentUser!.checkoutReady)
                        SliverToBoxAdapter(
                          child: _CheckoutBanner(
                            onClose: () => setState(() => _hideCheckout = true),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 96)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return content;
  }
}

/// Kratko objašnjenje tri načina kupnje (može se sakriti zauvijek).
class _HowLoopWorks extends ConsumerWidget {
  const _HowLoopWorks({required this.onClose, this.expanded = false});
  final bool expanded;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ways = [
      (
        Icons.videocam_outlined,
        t('Uživo'),
        t('Licitiraj dok prodavač pokazuje predmet'),
      ),
      (
        Icons.gavel_outlined,
        t('Aukcije'),
        t('Najviša ponuda kad istekne vrijeme'),
      ),
      if (kBuyNowEnabled)
        (
          Icons.shopping_bag_outlined,
          t('Kupi odmah'),
          t('Fiksna cijena, kupnja jednim dodirom'),
        ),
    ];
    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
        child: Row(
          key: const ValueKey('home-how'),
          children: [
            Expanded(
              child: InkWell(
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (ctx) => appThemed(
                    SafeArea(
                      child: SingleChildScrollView(
                        child: _HowLoopWorks(
                          expanded: true,
                          onClose: () => Navigator.pop(ctx),
                        ),
                      ),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: LoopColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t('Kako Subhasto radi'),
                          style: TextStyle(
                            fontSize: 13,
                            color: LoopColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('home-how-close'),
              tooltip: t('Sakrij'),
              onPressed: onClose,
              icon: Icon(
                Icons.close,
                size: 18,
                color: LoopColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      key: const ValueKey('home-how-details'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('Kako Subhasto radi'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('home-how-close'),
                    tooltip: t('Sakrij'),
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              for (final (icon, title, text) in ways)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 10),
                  child: Row(
                    children: [
                      Icon(icon, size: 22, color: LoopColors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '$title  ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(
                                text: text,
                                style: TextStyle(
                                  color: LoopColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
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

/// Podsjetnik: s karticom i adresom kupuješ i licitiraš jednim dodirom.
class _CheckoutBanner extends ConsumerWidget {
  const _CheckoutBanner({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: LoopColors.peach,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const ValueKey('home-checkout'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => ensureCheckout(context, ref, force: true),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
            child: Row(
              children: [
                const Icon(Icons.credit_card),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t(
                      'Dodaj karticu i adresu — licitiraj i kupuj jednim dodirom',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: t('Sakrij'),
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kompaktna kartica prodavača bez showa: avatar, naziv i broj proizvoda;
/// dodir otvara profil (show ne postoji).
class _SellerChip extends StatelessWidget {
  const _SellerChip({
    super.key,
    required this.user,
    required this.subtitle,
    required this.onTap,
  });
  final AppUser? user;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${user?.shopTitle ?? t('Prodavač')}, $subtitle',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 96,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            UserAvatar(user: user, size: 56),
            const SizedBox(height: 6),
            Text(
              user?.shopTitle ?? t('Prodavač'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: LoopColors.textSecondary),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyLive extends StatelessWidget {
  const _EmptyLive({required this.onGoLive, this.onShop});
  final VoidCallback onGoLive;
  final VoidCallback? onShop;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Container(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.videocam_outlined,
            size: 28,
            color: LoopColors.textSecondary,
          ),
          const SizedBox(height: 14),
          Text(
            t('Uživo se uskoro vraća.'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            kSimpleDesign
                ? t('Pogledaj najavljene prijenose i dostupne proizvode.')
                : t('Istraži ponude ili pokreni svoj prvi live.'),
            style: TextStyle(color: LoopColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: onShop ?? () => CategoriesScreen.open(context),
                child: Text(
                  onShop == null ? t('Pregledaj kategorije') : t('Otvori shop'),
                ),
              ),
              // Pokretanje livea je u dijelu Prodaj, ne na kupovnoj Početnoj.
              if (!kSimpleDesign)
                TextButton(
                  key: const ValueKey('home-go-live'),
                  onPressed: onGoLive,
                  child: Text(t('Kreni uživo')),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Računi koje pratiš (kao priče): krug s avatarom, crveni prsten i
/// UŽIVO kad emitira (dodir ulazi u live), inače otvara trgovinu.
class _FollowingRow extends StatelessWidget {
  const _FollowingRow({
    required this.users,
    required this.liveBy,
    required this.onLive,
  });

  final List<AppUser> users;
  final Map<String, BrowseItem> liveBy;
  final void Function(BrowseItem) onLive;

  @override
  Widget build(BuildContext context) {
    // Oni koji su uživo idu prvi.
    final list = [...users]
      ..sort(
        (a, b) => (liveBy.containsKey(b.id) ? 1 : 0).compareTo(
          liveBy.containsKey(a.id) ? 1 : 0,
        ),
      );
    return SizedBox(
      height: 96,
      child: ListView.separated(
        key: const ValueKey('home-following-row'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final u = list[i];
          final live = liveBy[u.id];
          return InkWell(
            key: ValueKey('following-${u.id}'),
            borderRadius: BorderRadius.circular(40),
            onTap: () => live != null
                ? onLive(live)
                : PublicProfileScreen.open(context, u.id),
            child: SizedBox(
              width: 66,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: live != null
                                ? LoopColors.live
                                : LoopColors.surfaceHover,
                            width: 2.5,
                          ),
                        ),
                        child: UserAvatar(user: u, size: 54),
                      ),
                      if (live != null)
                        Positioned(
                          bottom: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: LoopColors.live,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              t('UŽIVO'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    u.handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Vodoravni tekstualni tabovi vrste prikaza: aktivni je podebljan i
/// podcrtan, ostali sivi.
class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.selected,
    required this.onSelect,
    this.category,
    this.onCategory,
    this.categories = const [],
  });
  final DeviceCategory? category;

  /// Kategorije koje stvarno postoje u sustavu (filteri na Početnoj).
  final List<DeviceCategory> categories;
  final ValueChanged<DeviceCategory?>? onCategory;

  final String selected;
  final void Function(_Filter) onSelect;

  @override
  Widget build(BuildContext context) {
    if (kSimpleDesign) {
      // Pogledi unutar iste Početne (ne nova odredišta): Za tebe, Pratim,
      // Uživo i Proizvodi. Kategorije su zasebno odredište u navigaciji.
      void pick(_Filter f) {
        onCategory?.call(null);
        onSelect(f);
      }

      final soon = selected == 'soon';
      final following = selected == 'following';
      return PillSwitch(
        key: const ValueKey('home-tiles'),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        items: [
          PillSwitchItem(
            key: const ValueKey('home-view-for-you'),
            label: t('Za tebe'),
            selected: !soon && !following,
            onTap: () => pick(const _ForYou()),
          ),
          PillSwitchItem(
            key: const ValueKey('home-view-following'),
            label: t('Pratim'),
            selected: following,
            onTap: () => pick(const _Following()),
          ),
          PillSwitchItem(
            key: const ValueKey('home-view-soon'),
            label: t('Uskoro'),
            selected: soon,
            onTap: () => pick(const _Soon()),
          ),
        ],
      );
    }
    // Aktivni tab je svijetla kapsula; sporedni prikazi (Kupi odmah,
    // aukcije…) su manji i tiši — fokus je na liveu.
    Widget tab({
      required String id,
      required String label,
      required VoidCallback onTap,
      Key? key,
    }) {
      final on =
          selected == id && (id != 'for-you' || category == null) ||
          id == 'cat-${category?.name}';
      return Padding(
        padding: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
        child: InkWell(
          key: key ?? ValueKey('tile-$id'),
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? LoopColors.textPrimary : LoopColors.glass,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: on ? LoopColors.textPrimary : LoopColors.glassBorder,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? LoopColors.background : LoopColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 50,
      child: ListView(
        key: const ValueKey('home-tiles'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          tab(
            id: 'for-you',
            key: const ValueKey('home-cat-for-you'),
            label: selected == 'for-you' ? t('Sve uživo') : t('Uživo'),
            onTap: () {
              onCategory?.call(null);
              onSelect(const _ForYou());
            },
          ),
          if (selected == 'for-you')
            for (final (categoryValue, label) in <(DeviceCategory, String)>[
              (DeviceCategory.watches, t('Satovi')),
              (DeviceCategory.sneakers, t('Tenisice')),
              (DeviceCategory.vintage, t('Vintage')),
              (DeviceCategory.cards, t('Kolekcionarstvo')),
            ])
              tab(
                id: 'cat-${categoryValue.name}',
                label: label,
                onTap: () => onCategory?.call(
                  category == categoryValue ? null : categoryValue,
                ),
              ),
          if (selected == 'live')
            tab(
              id: 'live',
              key: const ValueKey('home-cat-live-selected'),
              label: t('Po kategoriji'),
              onTap: () => onSelect(const _LiveOnly()),
            ),
          if (selected == 'timed')
            tab(
              id: 'timed',
              label: t('Aukcije'),
              onTap: () => onSelect(const _Timed()),
            ),
          if (kBuyNowEnabled)
            tab(
              id: 'buy',
              label: t('Shop'),
              onTap: () => onSelect(const _BuyNow()),
            ),
          tab(
            id: 'following',
            key: const ValueKey('home-cat-following'),
            label: t('Pratim'),
            onTap: () => onSelect(const _Following()),
          ),
          if (selected == 'soon')
            tab(
              id: 'soon',
              label: t('Uskoro'),
              onTap: () => onSelect(const _Soon()),
            ),
          if (kBuyNowEnabled && selected == 'digital')
            tab(
              id: 'digital',
              label: t('Digitalno'),
              onTap: () => onSelect(const _Digital()),
            ),
        ],
      ),
    );
  }
}

/// Red pločica kategorija za brzi izbor livea (kao Trending na Whatnotu).
class _LiveCategoryStrip extends StatelessWidget {
  const _LiveCategoryStrip({
    required this.stats,
    required this.onSelect,
    this.selected,
    this.compact = false,
  });
  final List<CategoryStat> stats;

  /// Sažeto (pri listanju prema dolje): samo mali čipovi s nazivom.
  final bool compact;
  final ValueChanged<DeviceCategory> onSelect;

  /// Odabrana kategorija ostaje označena (ponovni dodir je poništava).
  final DeviceCategory? selected;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    if (compact) {
      return SizedBox(
        key: const ValueKey('home-live-categories-compact'),
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          itemCount: stats.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final c = stats[i];
            final on = selected == c.category;
            return ChoiceChip(
              key: ValueKey('live-cat-${c.category.name}'),
              label: Text(
                c.viewers > 0
                    ? '${c.category.label} · ${c.viewers}'
                    : c.category.label,
              ),
              selected: on,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              selectedColor: LoopColors.accent,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: on ? LoopColors.onAccent : null,
              ),
              onSelected: (_) => onSelect(c.category),
            );
          },
        ),
      );
    }
    return SizedBox(
      key: const ValueKey('home-live-categories-full'),
      height: 72,
      child: ListView.separated(
        key: const ValueKey('home-live-categories'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        itemCount: stats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = stats[i];
          final on = selected == c.category;
          return Material(
            color: on ? LoopColors.accent : LoopColors.surfaceHover,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: ValueKey('live-cat-${c.category.name}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => onSelect(c.category),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                child: Row(
                  children: [
                    CategoryArt(category: c.category, size: 44),
                    const SizedBox(width: 6),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.category.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: on ? LoopColors.onAccent : null,
                          ),
                        ),
                        Row(
                          children: [
                            if (c.viewers > 0) ...[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: kLiveRed,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              c.viewers > 0
                                  ? t('{0} gledatelja', ['${c.viewers}'])
                                  : t('Nema livea'),
                              style: TextStyle(
                                color: on
                                    ? LoopColors.onAccent.withValues(alpha: 0.8)
                                    : LoopColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Poredak liveova: promovirani prvi (jača promocija ispred), zatim
/// najgledaniji.
int _promotedFirst(BrowseItem a, BrowseItem b) {
  final w = (b.live?.boost.weight ?? 0).compareTo(a.live?.boost.weight ?? 0);
  if (w != 0) return w;
  return (b.live?.viewers ?? 0).compareTo(a.live?.viewers ?? 0);
}

/// Promovirani liveovi na vrh (jača promocija ispred), ostali zadržavaju
/// svoj redoslijed.
List<BrowseItem> _promotedOnTop(List<BrowseItem> list) => [
  ...list.where((i) => i.live?.boost.active ?? false).toList()
    ..sort(_promotedFirst),
  ...list.where((i) => !(i.live?.boost.active ?? false)),
];
