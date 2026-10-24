import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/trade_actions.dart';
import 'auctions_screen.dart';
import 'live_screens.dart';
import 'search_screen.dart';
import 'swipe_feed_screen.dart';

/// Početna kao Whatnot: pretraga, kategorije kao "pilule" i mreža kartica —
/// tko je uživo sada, što uskoro kreće, aukcije koje završavaju i predmeti
/// za Kupi odmah. Dodir na karticu otvara swipe feed te skupine.
class LiveHomeScreen extends ConsumerStatefulWidget {
  const LiveHomeScreen({super.key});

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

class _LiveHomeScreenState extends ConsumerState<LiveHomeScreen> {
  Timer? _timer;
  _Filter _filter = const _ForYou();
  bool _hideCheckout = false;

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
    final auctions = all.where((i) => i.auction != null).toList();
    final buyNow = all.where((i) => i.isBuyNow).toList();

    void open(List<BrowseItem> list, int i, String title) =>
        SwipeFeedScreen.open(
          context,
          [for (final x in list) x.entry],
          i,
          title: title,
        );

    Widget grid(String key, List<BrowseItem> list, String title) =>
        SliverPadding(
          key: ValueKey(key),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              childAspectRatio: 0.52,
              mainAxisSpacing: 16,
              crossAxisSpacing: 12,
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

    Widget header(String title, {String? action, VoidCallback? onAction}) =>
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (action != null)
                  TextButton(onPressed: onAction, child: Text(action)),
              ],
            ),
          ),
        );

    final slivers = <Widget>[];
    switch (_filter) {
      case _ForYou():
        slivers.add(header(t('🔴 Uživo sada')));
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
        if (soon.isNotEmpty) {
          slivers.add(header(t('📅 Uskoro')));
          slivers.add(grid('home-soon', soon, t('Uskoro')));
        }
        slivers.add(
          header(
            t('⏱ Završavaju uskoro'),
            action: t('Sve aukcije'),
            onAction: () => setState(() => _filter = const _Timed()),
          ),
        );
        slivers.add(
          auctions.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      t('Trenutno nema aukcija.'),
                      style: TextStyle(color: LoopColors.textSecondary),
                    ),
                  ),
                )
              : grid('home-ending', auctions, t('Završavaju uskoro')),
        );
        if (buyNow.isNotEmpty) {
          slivers.add(
            header(
              t('🏷️ Kupi odmah'),
              action: buyNow.length > 6 ? t('Sve') : null,
              onAction: () => setState(() => _filter = const _BuyNow()),
            ),
          );
          slivers.add(
            grid('home-buy', buyNow.take(6).toList(), t('Kupi odmah')),
          );
        }
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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Material(
              color: LoopColors.surface,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                key: const ValueKey('home-search'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => SearchScreen.open(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView(
              key: const ValueKey('home-cats'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _Pill(
                  id: 'for-you',
                  label: t('Za tebe'),
                  selected: _filter is _ForYou,
                  onTap: () => setState(() => _filter = const _ForYou()),
                ),
                _Pill(
                  id: 'live',
                  label: t('🔴 Uživo'),
                  selected: _filter is _LiveOnly,
                  onTap: () => setState(() => _filter = const _LiveOnly()),
                ),
                _Pill(
                  id: 'soon',
                  label: t('📅 Uskoro'),
                  selected: _filter is _Soon,
                  onTap: () => setState(() => _filter = const _Soon()),
                ),
                _Pill(
                  id: 'timed',
                  label: t('⏱ Aukcije'),
                  selected: _filter is _Timed,
                  onTap: () => setState(() => _filter = const _Timed()),
                ),
                _Pill(
                  id: 'buy',
                  label: t('🏷️ Kupi odmah'),
                  selected: _filter is _BuyNow,
                  onTap: () => setState(() => _filter = const _BuyNow()),
                ),
                // Kategorije su u svojoj kartici (donja traka).
              ],
            ),
          ),
        ),
        if (s.showHowItWorks && _filter is _ForYou)
          const SliverToBoxAdapter(child: _HowLoopWorks()),
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
  const _HowLoopWorks();

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
                      t('Kako LOOP radi'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('home-how-close'),
                    tooltip: t('Sakrij'),
                    onPressed: () =>
                        ref.read(appProvider.notifier).dismissHowItWorks(),
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

/// Kategorija kao "pilula" (kao na Whatnotu); odabrana je ispunjena.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? LoopColors.background : LoopColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? LoopColors.textPrimary : LoopColors.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: ValueKey('home-cat-$id'),
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
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
