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
import '../l10n/tr.dart';

/// Redoslijed uređaja u Marketu.
enum MarketSort {
  newest('Najnovije'),
  priceAsc('Cijena: niža prvo'),
  priceDesc('Cijena: viša prvo'),
  name('Naziv A–Ž');

  const MarketSort(this._label);
  final String _label;
  String get label => t(_label);

  int compare(Device a, Device b) => switch (this) {
    // Objavljeni predmet je "nov" od trenutka objave.
    MarketSort.newest => (b.listedAt ?? b.createdAt).compareTo(
      a.listedAt ?? a.createdAt,
    ),
    MarketSort.priceAsc => a.askPrice.compareTo(b.askPrice),
    MarketSort.priceDesc => b.askPrice.compareTo(a.askPrice),
    MarketSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  };
}

class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  final _search = TextEditingController();

  /// `null` = svi odjeljci / sve kategorije odjeljka.
  ItemSection? _section;
  DeviceCategory? _category;
  bool _onlyFavorites = false;
  MarketSort _sort = MarketSort.newest;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final all = state.marketDevices;
    final counts = AppState.countByCategory(all);
    final query = _search.text.trim().toLowerCase();

    final devices =
        all
            .where((d) => _section == null || d.section == _section)
            .where((d) => _category == null || d.category == _category)
            .where((d) => !_onlyFavorites || state.isFavorite(d.id))
            .where(
              (d) =>
                  query.isEmpty ||
                  d.name.toLowerCase().contains(query) ||
                  d.model.toLowerCase().contains(query) ||
                  d.description.toLowerCase().contains(query),
            )
            .toList()
          ..sort(_sort.compare);
    final credits = state.currentUser?.credits ?? 0;
    final favCount = all.where((d) => state.isFavorite(d.id)).length;
    final sectionCounts = <ItemSection, int>{};
    for (final d in all) {
      sectionCounts[d.section] = (sectionCounts[d.section] ?? 0) + 1;
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Dostupno: {0} · fee 5% na kupnju', [
                    formatCredits(credits),
                  ]),
                  style: TextStyle(color: LoopColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: t('Pretraži po nazivu…'),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () =>
                                        setState(() => _search.clear()),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SortButton(
                      value: _sort,
                      onChanged: (s) => setState(() => _sort = s),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // 1. red: odjeljci (+ favoriti).
        SliverToBoxAdapter(
          child: _ChipRow(
            children: [
              _CategoryChip(
                label: t('Sve'),
                icon: Icons.apps,
                color: Theme.of(context).colorScheme.primary,
                count: all.length,
                selected: _section == null && !_onlyFavorites,
                onTap: () => setState(() {
                  _section = null;
                  _category = null;
                  _onlyFavorites = false;
                }),
              ),
              for (final sec in ItemSection.values)
                _CategoryChip(
                  label: sec.label,
                  icon: sec.icon,
                  color: sec.color,
                  count: sectionCounts[sec] ?? 0,
                  selected: _section == sec,
                  onTap: () => setState(() {
                    _section = _section == sec ? null : sec;
                    _category = null;
                  }),
                ),
              _CategoryChip(
                label: t('Favoriti'),
                icon: Icons.favorite,
                color: const Color(0xFFFF5C8A),
                count: favCount,
                selected: _onlyFavorites,
                onTap: () => setState(() => _onlyFavorites = !_onlyFavorites),
              ),
            ],
          ),
        ),
        // 2. red: kategorije odabranog odjeljka.
        if (_section != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _ChipRow(
                children: [
                  for (final c in _section!.categories)
                    if ((counts[c] ?? 0) > 0)
                      _CategoryChip(
                        label: c.label,
                        icon: c.icon,
                        color: c.color,
                        count: counts[c]!,
                        selected: _category == c,
                        small: true,
                        onTap: () => setState(
                          () => _category = _category == c ? null : c,
                        ),
                      ),
                ],
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        if (devices.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: _onlyFavorites ? Icons.favorite_border : Icons.search_off,
              title: all.isEmpty
                  ? t('Market je trenutno prazan')
                  : _onlyFavorites && favCount == 0
                  ? t('Još nemaš favorita')
                  : t('Nema rezultata'),
              message: all.isEmpty
                  ? t('Prodani predmeti pojavljuju se ovdje.')
                  : _onlyFavorites && favCount == 0
                  ? t('Dodirni ♥ na predmetu da ga spremiš ovdje.')
                  : t('Promijeni pretragu, odjeljak ili kategoriju.'),
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

class _SortButton extends StatelessWidget {
  const _SortButton({required this.value, required this.onChanged});
  final MarketSort value;
  final ValueChanged<MarketSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MarketSort>(
      tooltip: t('Sortiraj'),
      initialValue: value,
      onSelected: onChanged,
      color: LoopColors.surfaceHover,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
      ),
      itemBuilder: (_) => [
        for (final s in MarketSort.values)
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                Icon(
                  s == value
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: s == value
                      ? Theme.of(context).colorScheme.primary
                      : LoopColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(s.label),
              ],
            ),
          ),
      ],
      child: Container(
        height: 52,
        width: 52,
        decoration: BoxDecoration(
          color: LoopColors.surface,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: const Icon(Icons.sort),
      ),
    );
  }
}
