import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/empty_state.dart';
import 'auctions_screen.dart';
import 'live_screens.dart' show kLiveRed;
import 'search_screen.dart';
import 'swipe_feed_screen.dart';

/// Gledatelji uživo i broj predmeta po kategoriji (za Trending i pločice).
class CategoryStat {
  const CategoryStat(this.category, {this.viewers = 0, this.items = 0});
  final DeviceCategory category;
  final int viewers;
  final int items;

  /// "1,2k gledatelja" ili, bez livea, broj predmeta.
  String get label => viewers > 0
      ? t('{0} gledatelja', [
          viewers >= 1000
              ? '${(viewers / 1000).toStringAsFixed(1)}k'
              : '$viewers',
        ])
      : items > 0
      ? itemsLabel(items)
      : t('Još prazno');
}

List<CategoryStat> categoryStats(AppState s) {
  final items = <DeviceCategory, int>{};
  for (final i in browseItems(s)) {
    for (final c in i.categories) {
      items[c] = (items[c] ?? 0) + 1;
    }
  }
  final viewers = <DeviceCategory, int>{};
  final now = DateTime.now();
  for (final show in s.liveShows) {
    final st = s.liveStateOf(show, now);
    if (!st.isLive) continue;
    final c = DeviceCategory.values
        .where((c) => c.name == show.category)
        .firstOrNull;
    if (c != null) viewers[c] = (viewers[c] ?? 0) + st.viewers;
  }
  return [
    for (final c in DeviceCategory.values)
      CategoryStat(c, viewers: viewers[c] ?? 0, items: items[c] ?? 0),
  ];
}

/// Najgledanije kategorije, pa one s najviše predmeta.
List<CategoryStat> trendingCategories(AppState s) {
  final list =
      [
        for (final c in categoryStats(s))
          if (c.viewers > 0 || c.items > 0) c,
      ]..sort((a, b) {
        final byViewers = b.viewers.compareTo(a.viewers);
        return byViewers != 0 ? byViewers : b.items.compareTo(a.items);
      });
  return list;
}

/// Kartica "Kategorije" (kao Whatnot): traka za pretragu, Trending danas
/// i mreža kategorija s filterom Preporučeno / Popularno / A–Z.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(t('Kategorije'))),
        body: const CategoriesScreen(),
      ),
    ),
  );

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  /// recommended | popular | az
  String _order = 'recommended';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final stats = categoryStats(s);
    final trending = trendingCategories(s).take(6).toList();
    final list = [...stats];
    switch (_order) {
      case 'popular':
        list.sort((a, b) {
          final v = b.viewers.compareTo(a.viewers);
          return v != 0 ? v : b.items.compareTo(a.items);
        });
      case 'az':
        list.sort((a, b) => a.category.label.compareTo(b.category.label));
    }
    Widget orderChip(String id, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('categories-order-$id'),
        label: Text(label),
        selected: _order == id,
        showCheckmark: false,
        onSelected: (_) => setState(() => _order = id),
      ),
    );
    return CustomScrollView(
      key: const ValueKey('categories'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: InkWell(
              key: const ValueKey('categories-search'),
              borderRadius: BorderRadius.circular(99),
              onTap: () => SearchScreen.open(context),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: LoopColors.textSecondary),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: LoopColors.textSecondary),
                    const SizedBox(width: 10),
                    Text(
                      t('Traži na Subhastu'),
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (trending.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('Trending danas'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('trending-all'),
                    onPressed: () => TrendingScreen.open(context),
                    child: Text('${t('Prikaži sve')} ›'),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 160,
              child: GridView.builder(
                key: const ValueKey('trending-chips'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 200,
                ),
                itemCount: trending.length,
                itemBuilder: (_, i) => _TrendingChip(
                  stat: trending[i],
                  onTap: () =>
                      CategoryItemsScreen.open(context, trending[i].category),
                ),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              t('Kategorije'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  orderChip('recommended', t('Preporučeno')),
                  orderChip('popular', t('Popularno')),
                  orderChip('az', t('A–Z')),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisExtent: 192,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            delegate: SliverChildListDelegate([
              for (final c in list)
                CategoryStatTile(
                  stat: c,
                  onTap: () => CategoryItemsScreen.open(context, c.category),
                ),
            ]),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

/// Zaobljena crvena oznaka gledatelja ("🔴 1,2k").
class _ViewersDot extends StatelessWidget {
  const _ViewersDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: const BoxDecoration(color: kLiveRed, shape: BoxShape.circle),
    child: const Icon(Icons.bar_chart, size: 13, color: Colors.white),
  );
}

class _TrendingChip extends StatelessWidget {
  const _TrendingChip({required this.stat, required this.onTap});
  final CategoryStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: LoopColors.surfaceHover,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      key: ValueKey('trending-${stat.category.name}'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            CategoryArt(category: stat.category, size: 52),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stat.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (stat.viewers > 0) ...[
                        const _ViewersDot(),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          stat.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 13,
                          ),
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

/// Pločica kategorije: naziv gore, ilustracija, dolje gledatelji.
class CategoryStatTile extends StatelessWidget {
  const CategoryStatTile({super.key, required this.stat, required this.onTap});
  final CategoryStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: LoopColors.surfaceHover,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      key: ValueKey('category-${stat.category.name}'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stat.category.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                height: 1.15,
              ),
            ),
            Expanded(
              child: Center(
                child: CategoryArt(category: stat.category, size: 56),
              ),
            ),
            Row(
              children: [
                if (stat.viewers > 0) ...[
                  const _ViewersDot(),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    stat.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// "Prikaži sve": rang lista kategorija (najgledanije / najviše predmeta).
class TrendingScreen extends ConsumerStatefulWidget {
  const TrendingScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const TrendingScreen()));

  @override
  ConsumerState<TrendingScreen> createState() => _TrendingScreenState();
}

class _TrendingScreenState extends ConsumerState<TrendingScreen> {
  bool _byViewers = true;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final list = trendingCategories(s);
    if (!_byViewers) {
      list.sort((a, b) => b.items.compareTo(a.items));
    }
    Widget chip(bool viewers, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('trending-order-${viewers ? 'viewers' : 'items'}'),
        label: Text(label),
        selected: _byViewers == viewers,
        showCheckmark: false,
        onSelected: (_) => setState(() => _byViewers = viewers),
      ),
    );
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        key: const ValueKey('trending-screen'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(
            t('Trending danas'),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            t('Što je trenutno popularno na Subhastu.'),
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              chip(true, t('Najgledanije')),
              chip(false, t('Najviše predmeta')),
            ],
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                t('Još nema aktivnosti.'),
                style: TextStyle(color: LoopColors.textSecondary),
              ),
            ),
          for (final (i, c) in list.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: LoopColors.surface,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  key: ValueKey('trending-rank-${c.category.name}'),
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => CategoryItemsScreen.open(context, c.category),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CategoryArt(category: c.category, size: 64),
                            Positioned(
                              left: -6,
                              top: -6,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: LoopColors.accent,
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: LoopColors.onAccent,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.category.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (c.viewers > 0) ...[
                                    const _ViewersDot(),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    c.label,
                                    style: TextStyle(
                                      color: LoopColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: LoopColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Jedna kategorija: mreža liveova, aukcija i Kupi odmah predmeta.
class CategoryItemsScreen extends ConsumerWidget {
  const CategoryItemsScreen({super.key, required this.category});
  final DeviceCategory category;

  static Future<void> open(BuildContext context, DeviceCategory c) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CategoryItemsScreen(category: c),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId ?? '';
    final list = [
      for (final i in browseItems(s))
        if (i.categories.contains(category)) i,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      body: list.isEmpty
          ? EmptyState(
              icon: category.icon,
              title: t('Ovdje još nema ničega'),
              message: t(
                'Kad netko objavi predmet u ovoj kategoriji, bit će ovdje.',
              ),
            )
          : GridView.builder(
              key: const ValueKey('category-items'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              gridDelegate: const BrowseGridDelegate(),
              itemCount: list.length,
              itemBuilder: (_, i) => AuctionBrowseCard(
                item: list[i],
                viewerId: me,
                onTap: () => SwipeFeedScreen.open(
                  context,
                  [for (final x in list) x.entry],
                  i,
                  title: category.label,
                ),
              ),
            ),
    );
  }
}
