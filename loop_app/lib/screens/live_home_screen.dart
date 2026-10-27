import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../widgets/user_avatar.dart';
import '../models/app_user.dart';
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
  const LiveHomeScreen({super.key, this.visible = true});

  /// Je li tab Početna na ekranu (feed "Za tebe" pušta live samo tada).
  final bool visible;

  @override
  ConsumerState<LiveHomeScreen> createState() => _LiveHomeScreenState();
}

/// Filter na početnoj: za tebe, uživo, uskoro ili kategorija.
sealed class _Filter {
  const _Filter();
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

class _Following extends _Filter {
  const _Following();
}

class _LiveHomeScreenState extends ConsumerState<LiveHomeScreen> {
  Timer? _timer;
  _Filter _filter = const _ForYou();
  bool _hideCheckout = false;

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
    final auctions = all.where((i) => i.auction != null).toList();
    final buyNow = all.where((i) => i.isBuyNow).toList();

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
    final following = s.currentUser == null || s.currentUser!.isGuest
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
                liveBy: {for (final i in live) i.show!.hostId: i},
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
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 12)));
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
                    child: _EmptyLive(
                      onGoLive: () => CreateLiveShowScreen.open(context),
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

    final Widget search = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: const ValueKey('home-search'),
          borderRadius: BorderRadius.circular(999),
          onTap: () => SearchScreen.open(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.search, color: LoopColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t('Pretraži liveove, aukcije i prodavače'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final immersive = _filter is _ForYou;
    final foreground = immersive ? Colors.white : LoopColors.textPrimary;
    Widget tab(String id, String label, _Filter filter, bool selected) => Expanded(
      child: Semantics(
        selected: selected,
        child: TextButton(
          key: ValueKey('home-cat-$id'),
          style: TextButton.styleFrom(
            foregroundColor: foreground.withValues(alpha: selected ? 1 : 0.65),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            minimumSize: const Size(44, 48),
          ),
          onPressed: () => setState(() => _filter = filter),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              decoration: selected ? TextDecoration.underline : null)),
        ),
      ),
    );
    final chips = ColoredBox(
      color: immersive ? Colors.black : LoopColors.background,
      child: SafeArea(bottom: false, child: Row(
        key: const ValueKey('home-cats'),
        children: [
          tab('following', t('Pratim'), const _Following(), _filter is _Following),
          tab('for-you', t('Za tebe'), const _ForYou(), immersive),
          tab('live', t('Uživo'), const _LiveOnly(), _filter is _LiveOnly),
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
              final picked = await showModalBottomSheet<_Filter>(
                context: context,
                showDragHandle: true,
                builder: (ctx) => SafeArea(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (id, label, icon, value) in [
                      ('soon', t('Uskoro'), Icons.event, const _Soon()),
                      ('timed', t('Aukcije'), Icons.gavel, const _Timed()),
                      ('buy', t('Kupi odmah'), Icons.shopping_bag_outlined, const _BuyNow()),
                    ]) ListTile(
                      key: ValueKey('home-cat-$id'),
                      leading: Icon(icon), title: Text(label),
                      onTap: () => Navigator.pop(ctx, value),
                    ),
                    const Divider(),
                    const Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [MessagesButton(), NotificationBell()]),
                  ],
                )),
              );
              if (picked != null && mounted) setState(() => _filter = picked);
            },
            icon: const Icon(Icons.tune),
          ),
        ],
      )),
    );

    // "Za tebe": TikTok — objave preko cijelog ekrana ispod izbornika,
    // beskonačno, a redoslijed uči dok listaš (vidi [ForYouFeed]).
    if (_filter is _ForYou) {
      return Column(
        children: [
          chips,
          Expanded(
            child: ForYouFeed(
              key: ValueKey('recommendations:${s.currentUserId}'),
              active:
                  widget.visible && (ModalRoute.of(context)?.isCurrent ?? true),
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: search),
        SliverToBoxAdapter(child: chips),
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

