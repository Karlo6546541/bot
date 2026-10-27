import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/empty_state.dart';
import 'auctions_screen.dart';
import 'swipe_feed_screen.dart';

/// Kartica "Kategorije": samo kategorije, po odjeljcima, s brojem
/// predmeta (liveovi, aukcije, Kupi odmah). Dodir otvara kategoriju.
class CategoriesScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final counts = <DeviceCategory, int>{};
    for (final i in browseItems(s)) {
      for (final c in i.categories) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    // Uključujući digitalno (softver, e-knjige, 3D modeli…).
    const sections = ItemSection.values;
    return CustomScrollView(
      key: const ValueKey('categories'),
      slivers: [
        for (final sec in sections) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(sec.icon, size: 20, color: sec.color),
                  const SizedBox(width: 8),
                  Text(
                    sec.label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                mainAxisExtent: 164,
                mainAxisSpacing: 8,
                crossAxisSpacing: 10,
              ),
              delegate: SliverChildListDelegate([
                for (final c in sec.categories)
                  _CategoryTile(
                    category: c,
                    count: counts[c] ?? 0,
                    onTap: () => CategoryItemsScreen.open(context, c),
                  ),
              ]),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.count,
    required this.onTap,
  });

  final DeviceCategory category;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('category-${category.name}'),
    borderRadius: BorderRadius.circular(kRadius),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          // Sličica preko cijele širine pločice.
          LayoutBuilder(
            builder: (context, c) =>
                CategoryArt(category: category, size: c.maxWidth.clamp(0, 88)),
          ),
          const SizedBox(height: 6),
          Text(
            category.label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              height: 1.15,
            ),
          ),
          Text(
            count > 0 ? itemsLabel(count) : t('Još prazno'),
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    ),
  );
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
