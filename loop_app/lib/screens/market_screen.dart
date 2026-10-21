import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/device_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';
import 'device_detail_screen.dart';
import 'market_filters.dart';

export 'market_filters.dart' show MarketSort;
import '../l10n/tr.dart';

class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  late final _search = TextEditingController(
    text: ref.read(marketFilterProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  MarketFilterNotifier get _filters => ref.read(marketFilterProvider.notifier);

  void _setQuery(String q) => _filters.update((f) => f.copyWith(query: q));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final f = ref.watch(marketFilterProvider);
    final all = state.marketDevices;
    final devices = f.apply(all, state);
    final credits = state.currentUser?.credits ?? 0;
    final sectionCounts = <ItemSection, int>{};
    for (final d in all) {
      sectionCounts[d.section] = (sectionCounts[d.section] ?? 0) + 1;
    }
    final categoryCounts = AppState.countByCategory(
      all.where((d) => d.section == f.section),
    );

    final searchRow = Row(
      children: [
        Expanded(
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _setQuery(v)),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: t('Pretraži po nazivu…'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: t('Očisti'),
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _search.clear();
                        _setQuery('');
                      }),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _FiltersButton(
          count: f.activeCount,
          onTap: () => showMarketFilterSheet(context, all: all),
        ),
      ],
    );

    // Brzi odabir odjeljka (i kategorija odabranog odjeljka).
    final chips = _ChipRow(
      children: [
        _CategoryChip(
          label: t('Sve'),
          icon: Icons.apps,
          color: Theme.of(context).colorScheme.primary,
          count: all.length,
          selected: f.section == null,
          onTap: () => _filters.update((f) => f.copyWith(clearSection: true)),
        ),
        if (f.section == null)
          for (final sec in ItemSection.values)
            _CategoryChip(
              label: sec.label,
              icon: sec.icon,
              color: sec.color,
              count: sectionCounts[sec] ?? 0,
              selected: false,
              onTap: () => _filters.update(
                (f) => f.copyWith(section: sec, clearCategory: true),
              ),
            )
        else ...[
          _CategoryChip(
            label: f.section!.label,
            icon: f.section!.icon,
            color: f.section!.color,
            count: sectionCounts[f.section] ?? 0,
            selected: f.category == null,
            onTap: () =>
                _filters.update((f) => f.copyWith(clearCategory: true)),
          ),
          for (final c in f.section!.categories)
            if ((categoryCounts[c] ?? 0) > 0)
              _CategoryChip(
                label: c.label,
                icon: c.icon,
                color: c.color,
                count: categoryCounts[c]!,
                selected: f.category == c,
                small: true,
                onTap: () => _filters.update(
                  (x) => x.category == c
                      ? x.copyWith(clearCategory: true)
                      : x.copyWith(category: c),
                ),
              ),
        ],
      ],
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              t('Dostupno: {0} · fee 5% na kupnju', [formatCredits(credits)]),
              style: TextStyle(color: LoopColors.textSecondary),
            ),
          ),
        ),
        // Pretraga, filteri i odjeljci ostaju vidljivi pri skrolanju.
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedHeader(
            height: 124,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: searchRow,
                  ),
                ),
                chips,
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: const ActiveFilterChips()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('{0} predmeta', [devices.length]),
                    key: const ValueKey('market-count'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _SortChip(
                  value: f.sort,
                  onChanged: (s) => _filters.update((f) => f.copyWith(sort: s)),
                ),
              ],
            ),
          ),
        ),
        if (devices.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: f.onlyFavorites ? Icons.favorite_border : Icons.search_off,
              title: all.isEmpty
                  ? t('Market je trenutno prazan')
                  : f.onlyFavorites && !all.any((d) => state.isFavorite(d.id))
                  ? t('Još nemaš favorita')
                  : t('Nema rezultata'),
              message: all.isEmpty
                  ? t('Prodani predmeti pojavljuju se ovdje.')
                  : f.onlyFavorites
                  ? t('Dodirni ♥ na predmetu da ga spremiš ovdje.')
                  : t('Promijeni pretragu, odjeljak ili kategoriju.'),
              action: f.isEmpty
                  ? null
                  : OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _search.clear();
                        _filters.set(MarketFilter(sort: f.sort));
                      }),
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: Text(t('Očisti pretragu i filtere')),
                    ),
            ),
          )
        else
          DeviceGrid(
            devices: devices,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemBuilder: (context, d) => DeviceCard(
              device: d,
              actionLabel: t('Kupi odmah'),
              actionIcon: Icons.shopping_bag_outlined,
              onAction: () => confirmAndBuy(context, ref, d),
              onTap: () => DeviceDetailScreen.open(context, d),
              isFavorite: state.isFavorite(d.id),
              onFavorite: () => toggleFavorite(ref, d),
              badge: d.isListed ? state.userLabel(d.ownerId) : null,
            ),
          ),
      ],
    );
  }
}

/// Zaglavlje koje ostaje na vrhu pri skrolanju.
class _PinnedHeader extends SliverPersistentHeaderDelegate {
  _PinnedHeader({required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrink, bool overlaps) => Material(
    color: LoopColors.background,
    elevation: overlaps ? 2 : 0,
    shadowColor: Colors.black26,
    child: child,
  );

  @override
  bool shouldRebuild(_PinnedHeader old) => true;
}

/// "Filteri" s brojem aktivnih filtera.
class _FiltersButton extends StatelessWidget {
  const _FiltersButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Material(
      color: active ? LoopColors.accent : LoopColors.surface,
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        key: const ValueKey('filters-button'),
        borderRadius: BorderRadius.circular(kRadius),
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(
              color: active ? LoopColors.accent : LoopColors.surfaceHover,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune,
                color: active ? LoopColors.onAccent : LoopColors.textPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                active ? '${t('Filteri')} ($count)' : t('Filteri'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: active ? LoopColors.onAccent : LoopColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vodoravno pomični red čipova. Čipova je malo, pa se grade svi odjednom
/// (Row umjesto ListView).
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: children),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.selected,
    required this.onTap,
    this.small = false,
  });

  final bool small;
  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(
              horizontal: small ? 12 : 14,
              vertical: small ? 5 : 8,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? color.withValues(alpha: 0.2)
                  : LoopColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? color : LoopColors.surfaceHover,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? color : LoopColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? LoopColors.textPrimary
                        : LoopColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? color : LoopColors.surfaceHover,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : LoopColors.textSecondary,
                    ),
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

/// Odabir redoslijeda — prikazuje trenutni izbor.
class _SortChip extends StatelessWidget {
  const _SortChip({required this.value, required this.onChanged});
  final MarketSort value;
  final ValueChanged<MarketSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MarketSort>(
      key: const ValueKey('sort-button'),
      tooltip: t('Sortiraj'),
      initialValue: value,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
      ),
      itemBuilder: (_) => [
        for (final s in MarketSort.values)
          CheckedPopupMenuItem(
            value: s,
            checked: s == value,
            child: Text(s.label),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert, size: 18, color: LoopColors.accent),
            const SizedBox(width: 4),
            Text(
              value.label,
              style: TextStyle(
                color: LoopColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            Icon(Icons.arrow_drop_down, color: LoopColors.accent),
          ],
        ),
      ),
    );
  }
}
