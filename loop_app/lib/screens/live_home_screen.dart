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
import 'categories_screen.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/trade_actions.dart';
import 'auctions_screen.dart';
import 'for_you_feed.dart';
import 'public_profile_screen.dart';
import 'live_screens.dart';
import 'search_screen.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';
import 'swipe_feed_screen.dart';

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
    'live' => const _LiveOnly(),
    'soon' => const _Soon(),
    'timed' => const _Timed(),
    // Kupi odmah je isključen (stare poveznice vode na Za tebe).
    'buy' when kBuyNowEnabled => const _BuyNow(),
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
    widget.onImmersiveChanged?.call(filter is _ForYou);
  }

  Timer? _timer;
  _Filter get _filter => _Filter.of(ref.read(homeFilterProvider));

  /// Swipe lijevo/desno između gornjih tabova (kao TikTok): Pratim ·
  /// Za tebe · Uživo · Pretraga.
  static const _swipeTabs = ['following', 'for-you', 'live'];

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
  DeviceCategory? _auctionCategory;

  /// "Kako Subhasto radi" vidi se samo pri prvom otvaranju — odmah se bilježi
  /// kao viđeno, a do kraja ove sesije ostaje (dok ga ne zatvoriš).
  late bool _showHow = ref.read(appProvider).showHowItWorks;

  @override
  void initState() {
    super.initState();
    if (_showHow) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(appProvider.notifier).dismissHowItWorks(),
      );
    }
    // Liveovi počinju i završavaju sami (domaćin dođe ili ode).
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(homeFilterProvider);
    final s = ref.watch(appProvider);
    final me = s.currentUserId ?? '';
    final all = _filter is _ForYou ? const <BrowseItem>[] : browseItems(s);
    final allLive = all.where((i) => i.live?.isLive ?? false).toList();
    final live = allLive
        .where(
          (i) => _liveCategory == null || i.categories.contains(_liveCategory),
        )
        .toList();
    final soon = all.where((i) => i.live?.isScheduled ?? false).toList();
    final allAuctions = all.where((i) => i.auction != null).toList();
    final auctions = allAuctions
        .where(
          (i) =>
              _auctionCategory == null ||
              i.categories.contains(_auctionCategory),
        )
        .toList();
    final buyNow = all.where((i) => i.isBuyNow).toList();
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
            gridDelegate: const BrowseGridDelegate(),
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
          slivers.add(
            theirs.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        t('Računi koje pratiš trenutno nemaju oglasa.'),
                        style: TextStyle(color: LoopColors.textSecondary),
                      ),
                    ),
                  )
                : grid('home-following', theirs, t('Pratim')),
          );
        }
      case _ForYou():
        // Feed preko cijelog ekrana (vidi dolje) — bez mreže.
        break;
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
              : grid('home-live', live, t('Uživo sada')),
        );
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
              : grid('home-soon', soon, t('Uskoro')),
        );
    }

    final immersive = _filter is _ForYou;
    final foreground = immersive ? Colors.white : LoopColors.textPrimary;
    Widget tab(String id, String label, _Filter filter, bool selected) =>
        Expanded(
          child: Semantics(
            selected: selected,
            child: TextButton(
              key: ValueKey('home-cat-$id'),
              style: TextButton.styleFrom(
                foregroundColor: foreground.withValues(
                  alpha: selected ? 1 : 0.65,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                minimumSize: const Size(44, 48),
              ),
              onPressed: () => _select(filter),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  decoration: selected ? TextDecoration.underline : null,
                ),
              ),
            ),
          ),
        );
    final chips = ColoredBox(
      color: immersive ? Colors.black : LoopColors.background,
      child: SafeArea(
        bottom: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Row(
              key: const ValueKey('home-cats'),
              children: [
                tab(
                  'following',
                  t('Pratim'),
                  const _Following(),
                  _filter is _Following,
                ),
                tab('for-you', t('Za tebe'), const _ForYou(), immersive),
                tab(
                  'live',
                  t('Uživo'),
                  const _LiveOnly(),
                  _filter is _LiveOnly,
                ),
                IconButton(
                  key: const ValueKey('home-search'),
                  tooltip: t('Pretraži objave i račune'),
                  color: foreground,
                  onPressed: () => SearchScreen.open(context),
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  key: const ValueKey('home-filters'),
                  tooltip: t('Filteri'),
                  color: foreground,
                  onPressed: () async {
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
                              for (final (id, label, icon, value)
                                  in <(String, String, IconData, Object)>[
                                    if (BackendConfig.cloudCommerceEnabled)
                                      ('cloud', 'Live i trgovina online', Icons.cloud_outlined, 'cloud'),
                                    (
                                      'categories',
                                      t('Kategorije'),
                                      Icons.grid_view,
                                      'categories',
                                    ),
                                    (
                                      'my',
                                      t('Moje'),
                                      Icons.local_activity_outlined,
                                      'my',
                                    ),
                                    (
                                      'live-menu',
                                      t('Uživo'),
                                      Icons.videocam_outlined,
                                      const _LiveOnly(),
                                    ),
                                    if (kBuyNowEnabled)
                                      (
                                        'digital',
                                        t('Digitalne kupnje'),
                                        Icons.download_outlined,
                                        const _Digital(),
                                      ),
                                    (
                                      'soon',
                                      t('Uskoro'),
                                      Icons.event,
                                      const _Soon(),
                                    ),
                                    (
                                      'timed',
                                      t('Aukcije'),
                                      Icons.gavel,
                                      const _Timed(),
                                    ),
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
                              const Divider(),
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  MessagesButton(),
                                  NotificationBell(),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (!mounted || !context.mounted) return;
                    if (picked == 'cloud') {
                      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CloudCommerceScreen()));
                    } else if (picked == 'categories') {
                      await CategoriesScreen.open(context);
                    } else if (picked == 'my') {
                      ref.read(homeTabProvider.notifier).select(2);
                    } else if (picked is _Filter) {
                      _select(picked);
                    }
                  },
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
          ),
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

    // "Za tebe": TikTok — objave preko cijelog ekrana ispod izbornika,
    // beskonačno, a redoslijed uči dok listaš (vidi [ForYouFeed]).
    if (_filter is _ForYou) {
      return Column(
        children: [
          chips,
          Expanded(
            child: GestureDetector(
              key: const ValueKey('home-swipe'),
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: _swipe,
              child: ForYouFeed(
                key: ValueKey('recommendations:${s.currentUserId}'),
                active:
                    widget.visible &&
                    (ModalRoute.of(context)?.isCurrent ?? true),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        chips,
        Expanded(
          child: GestureDetector(
            key: const ValueKey('home-swipe'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: _swipe,
            child: CustomScrollView(
              slivers: [
                if (onLive || onAuctions)
                  SliverToBoxAdapter(child: categoryFilter),
                if (_showHow && _filter is _ForYou)
                  SliverToBoxAdapter(
                    child: _HowLoopWorks(
                      onClose: () => setState(() => _showHow = false),
                    ),
                  ),
                if (!_hideCheckout &&
                    s.currentUser != null &&
                    !s.currentUser!.isGuest &&
                    !s.currentUser!.checkoutReady)
                  SliverToBoxAdapter(
                    child: _CheckoutBanner(
                      onClose: () => setState(() => _hideCheckout = true),
                    ),
                  ),
                ...slivers,
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Kratko objašnjenje tri načina kupnje (može se sakriti zauvijek).
class _HowLoopWorks extends ConsumerWidget {
  const _HowLoopWorks({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ways = [
      ('🔴', t('Uživo'), t('Licitiraj dok prodavač pokazuje predmet')),
      ('⏱', t('Aukcije'), t('Najviša ponuda kad istekne vrijeme')),
      if (kBuyNowEnabled)
        ('🛒', t('Kupi odmah'), t('Fiksna cijena, kupnja jednim dodirom')),
    ];
    return Padding(
      key: const ValueKey('home-how'),
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
              for (final (emoji, title, text) in ways)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 10),
                  child: Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 20)),
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

class _EmptyLive extends StatelessWidget {
  const _EmptyLive({required this.onGoLive});
  final VoidCallback onGoLive;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFC8441E), kLiveRed],
      ),
      borderRadius: BorderRadius.circular(kRadius),
    ),
    child: Row(
      children: [
        const Icon(Icons.videocam, color: Colors.white, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            t('Nitko trenutno nije uživo — budi prvi!'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        FilledButton(
          key: const ValueKey('home-go-live'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: kLiveRed,
          ),
          onPressed: onGoLive,
          child: Text(t('Kreni uživo')),
        ),
      ],
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
