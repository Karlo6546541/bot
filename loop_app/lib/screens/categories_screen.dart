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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final counts = <DeviceCategory, int>{};
    for (final i in browseItems(s)) {
      for (final c in i.categories) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    // Digitalni proizvodi su uklonjeni iz aplikacije.
    final sections = [
      for (final sec in ItemSection.values)
        if (sec != ItemSection.digital) sec,
    ];
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
                maxCrossAxisExtent: 190,
                mainAxisExtent: 64,
                mainAxisSpacing: 10,
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
  Widget build(BuildContext context) {
    final color = category.color;
    return Material(
      color: LoopColors.surface,
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        key: ValueKey('category-${category.name}'),
        borderRadius: BorderRadius.circular(kRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(color: LoopColors.surfaceHover),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(category.icon, size: 20, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    if (count > 0)
                      Text(
                        t('{0} predmeta', ['$count']),
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 11,
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
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                childAspectRatio: 0.52,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
              ),
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
