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
import '../services/market_filter.dart' show normalizeSearch;
import '../services/smart_search.dart';
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

/// Jednostavna tanka tražilica (filtrira popis na istom ekranu).
class SlimSearchField extends StatelessWidget {
  const SlimSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        prefixIcon: Icon(
          Icons.search,
          size: 20,
          color: LoopColors.textSecondary,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: t('Očisti'),
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: LoopColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: BorderSide(color: LoopColors.textSecondary),
        ),
      ),
    ),
  );
}

/// Kartica "Kategorije": tanka tražilica koja traži kategorije, pa
/// jednostavan popis (uživo sada, zatim po skupinama).
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
  final _query = TextEditingController();
  ItemSection _section = ItemSection.values.first;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Taobao raspored: lijevo odjeljci, desno mreža podkategorija.
  Widget _rail(Map<ItemSection, int> live) => SizedBox(
    width: 96,
    child: ListView(
      key: const ValueKey('categories-rail'),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final sec in ItemSection.values)
          InkWell(
            key: ValueKey('cat-section-${sec.name}'),
            onTap: () => setState(() => _section = sec),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              decoration: BoxDecoration(
                color: _section == sec
                    ? LoopColors.surface
                    : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    width: 3,
                    color: _section == sec
                        ? LoopColors.textPrimary
                        : Colors.transparent,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        sec.icon,
                        size: 22,
                        color: _section == sec
                            ? LoopColors.textPrimary
                            : LoopColors.textSecondary,
                      ),
                      if ((live[sec] ?? 0) > 0)
                        Positioned(
                          right: -4,
                          top: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: kLiveRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sec.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.15,
                      fontWeight: _section == sec
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: _section == sec
                          ? LoopColors.textPrimary
                          : LoopColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _tile(CategoryStat c) => InkWell(
    key: ValueKey('category-${c.category.name}'),
    borderRadius: BorderRadius.circular(16),
    onTap: () => CategoryItemsScreen.open(context, c.category),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CategoryArt(category: c.category, size: 44),
          const SizedBox(height: 4),
          Text(
            c.category.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          if (c.viewers > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: kLiveRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${c.viewers}',
                  style: TextStyle(
                    fontSize: 11,
                    color: LoopColors.textSecondary,
                  ),
                ),
              ],
            )
          else if (c.items > 0)
            Text(
              '${c.items}',
              style: TextStyle(fontSize: 11, color: LoopColors.textSecondary),
            )
          else
            const SizedBox(height: 13),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final stats = categoryStats(s);
    final q = normalizeSearch(_query.text.trim());
    final live = <ItemSection, int>{
      for (final c in stats)
        if (c.viewers > 0) c.category.section: 1,
    };
    final Widget body;
    if (q.isNotEmpty) {
      final hits = [
        for (final c in stats)
          if (normalizeSearch(c.category.label).contains(q) ||
              normalizeSearch(c.category.section.label).contains(q))
            c,
      ];
      body = ListView(
        key: const ValueKey('categories'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          if (hits.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                t('Nema takve kategorije.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: LoopColors.textSecondary),
              ),
            ),
          for (final c in hits)
            CategoryRow(
              stat: c,
              onTap: () => CategoryItemsScreen.open(context, c.category),
            ),
        ],
      );
    } else {
      final inSec = [
        for (final c in stats)
          if (c.category.section == _section) c,
      ];
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rail(live),
          Expanded(
            child: ListView(
              key: const ValueKey('categories'),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _section.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      TextButton(
                        key: ValueKey('category-all-${_section.name}'),
                        onPressed: () =>
                            CategoryItemsScreen.openSection(context, _section),
                        child: Text(t('Sve')),
                      ),
                    ],
                  ),
                ),
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // Visina prati veličinu teksta (nema prelijevanja).
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisExtent:
                        70 + 44 * MediaQuery.textScalerOf(context).scale(1),
                  ),
                  children: [for (final c in inSec) _tile(c)],
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: SlimSearchField(
                key: const ValueKey('categories-search'),
                controller: _query,
                hint: t('Traži kategoriju'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Redak kategorije: mala ilustracija, naziv i broj predmeta/gledatelja.
class CategoryRow extends StatelessWidget {
  const CategoryRow({super.key, required this.stat, required this.onTap});
  final CategoryStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('category-${stat.category.name}'),
    borderRadius: BorderRadius.circular(99),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          CategoryArt(category: stat.category, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              stat.category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
          if (stat.viewers > 0) ...[
            const _ViewersDot(),
            const SizedBox(width: 6),
          ],
          Text(
            stat.viewers > 0 || stat.items > 0 ? stat.label : '',
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: LoopColors.textSecondary, size: 20),
        ],
      ),
    ),
  );
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

/// Jedna kategorija: tražilica samo za tu kategoriju i mreža liveova,
/// aukcija i Kupi odmah predmeta.
class CategoryItemsScreen extends ConsumerStatefulWidget {
  const CategoryItemsScreen({super.key, this.category, this.section})
    : assert(category != null || section != null);

  /// Jedna podkategorija ILI cijeli odjeljak ("Prikaži sve").
  final DeviceCategory? category;
  final ItemSection? section;

  static Future<void> openSection(BuildContext context, ItemSection s) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CategoryItemsScreen(section: s),
        ),
      );

  static Future<void> open(BuildContext context, DeviceCategory c) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CategoryItemsScreen(category: c),
        ),
      );

  @override
  ConsumerState<CategoryItemsScreen> createState() =>
      _CategoryItemsScreenState();
}

class _CategoryItemsScreenState extends ConsumerState<CategoryItemsScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final title = category?.label ?? widget.section!.label;
    final s = ref.watch(appProvider);
    final me = s.currentUserId ?? '';
    final all = [
      for (final i in browseItems(s))
        if (category != null
            ? i.categories.contains(category)
            : i.categories.any((c) => c.section == widget.section))
          i,
    ];
    final q = SmartQuery.parse(_query.text);
    final list = q.isEmpty
        ? all
        : [
            for (final i in all)
              if (q.matches(_textOf(i)) &&
                  (!q.hasPrice ||
                      (_priceOf(i) != null && q.priceOk(_priceOf(i)!))))
                i,
          ];
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          if (all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SlimSearchField(
                key: const ValueKey('category-search'),
                controller: _query,
                hint: t('Traži u kategoriji {0}', [title]),
                onChanged: (_) => setState(() {}),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? EmptyState(
                    icon: category?.icon ?? widget.section!.icon,
                    title: all.isEmpty
                        ? t('Ovdje još nema ničega')
                        : t('Ništa ne odgovara pretrazi'),
                    message: all.isEmpty
                        ? t(
                            'Kad netko objavi predmet u ovoj kategoriji, bit će ovdje.',
                          )
                        : t('Probaj drugu riječ ili očisti pretragu.'),
                  )
                : GridView.builder(
                    key: const ValueKey('category-items'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    gridDelegate: BrowseGridDelegate(
                      textScale:
                          MediaQuery.textScalerOf(context).scale(14) / 14,
                    ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => AuctionBrowseCard(
                      item: list[i],
                      viewerId: me,
                      onTap: () => SwipeFeedScreen.open(
                        context,
                        [for (final x in list) x.entry],
                        i,
                        title: title,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Tekst objave za pretragu unutar kategorije.
String _textOf(BrowseItem i) => [
  if (i.show case final show?) ...[
    show.title,
    show.hostLabel,
    for (final l in show.lots) l.deviceName,
  ],
  if (i.auction case final a?) ...[a.deviceName, a.sellerLabel],
  if (i.device case final d?) ...[d.name, d.model, d.description],
].join(' ');

/// Cijena objave (live nema cijenu).
double? _priceOf(BrowseItem i) =>
    i.auction?.currentPrice ?? i.device?.priceAt(DateTime.now());
