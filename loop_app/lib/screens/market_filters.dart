import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/fee.dart';
import '../services/market_filter.dart' show normalizeSearch;
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/formatters.dart';

/// Redoslijed predmeta u Marketu.
enum MarketSort {
  recommended('Preporučeno'),
  newest('Najnovije'),
  priceAsc('Cijena: niža prvo'),
  priceDesc('Cijena: viša prvo'),
  name('Naziv A–Ž');

  const MarketSort(this._label);
  final String _label;
  String get label => t(_label);

  int compare(Device a, Device b) => switch (this) {
    // Objavljeni predmet je "nov" od trenutka objave.
    MarketSort.newest || MarketSort.recommended =>
      (b.listedAt ?? b.createdAt).compareTo(a.listedAt ?? a.createdAt),
    MarketSort.priceAsc => a.askPrice.compareTo(b.askPrice),
    MarketSort.priceDesc => b.askPrice.compareTo(a.askPrice),
    MarketSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  };
}

/// Tko prodaje: svi, platforma (LOOP Market) ili korisnici.
enum SellerFilter {
  all('Svi prodavatelji'),
  loop('LOOP Market'),
  users('Korisnici');

  const SellerFilter(this._label);
  final String _label;
  String get label => t(_label);
}

/// Odabrani filteri Marketa (nepromjenjivo). Čuva se u provideru, pa
/// preživi promjenu taba, teme i jezika.
class MarketFilter {
  const MarketFilter({
    this.query = '',
    this.section,
    this.category,
    this.conditions = const {},
    this.minPrice,
    this.maxPrice,
    this.seller = SellerFilter.all,
    this.onlyFavorites = false,
    this.withPhotos = false,
    this.onlyAffordable = false,
    this.onlyDiscounted = false,
    this.sort = MarketSort.recommended,
  });

  final String query;
  final ItemSection? section;
  final DeviceCategory? category;
  final Set<DeviceCondition> conditions;
  final double? minPrice;
  final double? maxPrice;
  final SellerFilter seller;
  final bool onlyFavorites;
  final bool withPhotos;

  /// Samo predmeti za koje imam dovoljno novca (cijena + 2% naknade).
  final bool onlyAffordable;

  /// Samo predmeti na popustu.
  final bool onlyDiscounted;
  final MarketSort sort;

  /// Broj aktivnih filtera (bez pretrage i sortiranja) — za značku.
  int get activeCount =>
      (section != null ? 1 : 0) +
      (category != null ? 1 : 0) +
      (conditions.isNotEmpty ? 1 : 0) +
      (minPrice != null || maxPrice != null ? 1 : 0) +
      (seller != SellerFilter.all ? 1 : 0) +
      (onlyFavorites ? 1 : 0) +
      (withPhotos ? 1 : 0) +
      (onlyAffordable ? 1 : 0) +
      (onlyDiscounted ? 1 : 0);

  bool get isEmpty => activeCount == 0 && query.trim().isEmpty;

  MarketFilter copyWith({
    String? query,
    ItemSection? section,
    bool clearSection = false,
    DeviceCategory? category,
    bool clearCategory = false,
    Set<DeviceCondition>? conditions,
    double? minPrice,
    double? maxPrice,
    bool clearPrice = false,
    SellerFilter? seller,
    bool? onlyFavorites,
    bool? withPhotos,
    bool? onlyAffordable,
    bool? onlyDiscounted,
    MarketSort? sort,
  }) => MarketFilter(
    query: query ?? this.query,
    section: clearSection ? null : section ?? this.section,
    category: clearCategory || clearSection ? null : category ?? this.category,
    conditions: conditions ?? this.conditions,
    minPrice: clearPrice ? null : minPrice ?? this.minPrice,
    maxPrice: clearPrice ? null : maxPrice ?? this.maxPrice,
    seller: seller ?? this.seller,
    onlyFavorites: onlyFavorites ?? this.onlyFavorites,
    withPhotos: withPhotos ?? this.withPhotos,
    onlyAffordable: onlyAffordable ?? this.onlyAffordable,
    onlyDiscounted: onlyDiscounted ?? this.onlyDiscounted,
    sort: sort ?? this.sort,
  );

  /// Svi filteri osim pretrage i sortiranja vraćeni na početno.
  MarketFilter cleared() => MarketFilter(query: query, sort: sort);

  /// Primjenjuje filtere i sortiranje.
  List<Device> apply(List<Device> devices, AppState state) {
    // Više riječi, bez obzira na dijakritiku ("citac knjiga" = "Čitač…").
    final terms = normalizeSearch(
      query,
    ).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final credits = state.currentUser?.credits ?? 0;
    return devices.where((d) {
      if (section != null && d.section != section) return false;
      if (category != null && d.category != category) return false;
      if (conditions.isNotEmpty && !conditions.contains(d.condition)) {
        return false;
      }
      if (minPrice != null && d.askPrice < minPrice!) return false;
      if (maxPrice != null && d.askPrice > maxPrice!) return false;
      if (seller == SellerFilter.loop && !d.isOnMarket) return false;
      if (seller == SellerFilter.users && !d.isListed) return false;
      if (onlyFavorites && !state.isFavorite(d.id)) return false;
      if (withPhotos && d.imagePaths.isEmpty) return false;
      if (onlyAffordable && buyTotal(state.priceForMe(d)) > credits) {
        return false;
      }
      if (onlyDiscounted && !d.hasDiscount) return false;
      if (terms.isNotEmpty) {
        final text = normalizeSearch(
          [
            d.name,
            d.model,
            d.description,
            d.category.label,
            d.category.singular,
            d.section.label,
            d.condition.label,
          ].join(' '),
        );
        if (!terms.every(text.contains)) return false;
      }
      return true;
    }).toList()..sort((a, b) {
      if (sort == MarketSort.recommended) {
        // Istaknuti računi (plaćeno isticanje) prvi, zatim popusti.
        final p = _rank(state, b).compareTo(_rank(state, a));
        if (p != 0) return p;
      }
      return sort.compare(a, b);
    });
  }

  static int _rank(AppState state, Device d) =>
      (state.isPromotedItem(d) ? 2 : 0) + (d.hasDiscount ? 1 : 0);
}

final marketFilterProvider =
    NotifierProvider<MarketFilterNotifier, MarketFilter>(
      MarketFilterNotifier.new,
    );

class MarketFilterNotifier extends Notifier<MarketFilter> {
  @override
  MarketFilter build() => const MarketFilter();

  void set(MarketFilter f) => state = f;
  void update(MarketFilter Function(MarketFilter) f) => state = f(state);
}

/// Raspon cijena u Marketu (za klizač), zaokružen na desetice.
(double, double) priceBounds(List<Device> devices) {
  if (devices.isEmpty) return (0, 100);
  var lo = devices.first.askPrice;
  var hi = lo;
  for (final d in devices) {
    if (d.askPrice < lo) lo = d.askPrice;
    if (d.askPrice > hi) hi = d.askPrice;
  }
  lo = (lo / 10).floorToDouble() * 10;
  hi = (hi / 10).ceilToDouble() * 10;
  if (hi <= lo) hi = lo + 10;
  return (lo, hi);
}

/// Otvara list sa svim filterima. Promjene se vide odmah u broju
/// rezultata; "Prikaži" zatvara list.
Future<void> showMarketFilterSheet(
  BuildContext context, {
  required List<Device> all,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _FilterSheet(all: all),
);

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet({required this.all});
  final List<Device> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(marketFilterProvider);
    final notifier = ref.read(marketFilterProvider.notifier);
    final state = ref.watch(appProvider);
    final results = f.apply(all, state).length;
    final (lo, hi) = priceBounds(all);
    final range = RangeValues(
      (f.minPrice ?? lo).clamp(lo, hi),
      (f.maxPrice ?? hi).clamp(lo, hi),
    );

    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
      ),
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('Filteri'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('filters-clear'),
                  onPressed: f.activeCount == 0
                      ? null
                      : () => notifier.set(f.cleared()),
                  child: Text(t('Očisti')),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('filters-list'),
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                title(t('Odjeljak')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in ItemSection.values)
                      FilterChip(
                        avatar: Icon(s.icon, size: 18, color: s.color),
                        label: Text(s.label),
                        selected: f.section == s,
                        onSelected: (on) => notifier.update(
                          (f) => on
                              ? f.copyWith(section: s, clearCategory: true)
                              : f.copyWith(clearSection: true),
                        ),
                      ),
                  ],
                ),
                if (f.section != null) ...[
                  title(t('Kategorija')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in f.section!.categories)
                        FilterChip(
                          avatar: Icon(c.icon, size: 18, color: c.color),
                          label: Text(c.label),
                          selected: f.category == c,
                          onSelected: (on) => notifier.update(
                            (f) => on
                                ? f.copyWith(category: c)
                                : f.copyWith(clearCategory: true),
                          ),
                        ),
                    ],
                  ),
                ],
                title(t('Stanje')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in DeviceCondition.values)
                      FilterChip(
                        label: Text(c.label),
                        selected: f.conditions.contains(c),
                        onSelected: (on) => notifier.update(
                          (f) => f.copyWith(
                            conditions: on
                                ? {...f.conditions, c}
                                : ({...f.conditions}..remove(c)),
                          ),
                        ),
                      ),
                  ],
                ),
                title(t('Cijena')),
                Row(
                  children: [
                    Text(
                      formatCredits(range.start),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      formatCredits(range.end),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final limit in const [100.0, 250.0, 500.0, 1000.0])
                      ChoiceChip(
                        label: Text(t('do {0}', [formatNumber(limit)])),
                        selected: f.minPrice == null && f.maxPrice == limit,
                        onSelected: (on) => notifier.update(
                          (f) => on
                              ? f
                                    .copyWith(clearPrice: true)
                                    .copyWith(maxPrice: limit)
                              : f.copyWith(clearPrice: true),
                        ),
                      ),
                  ],
                ),
                RangeSlider(
                  key: const ValueKey('price-range'),
                  values: range,
                  min: lo,
                  max: hi,
                  divisions: ((hi - lo) / 10).round().clamp(1, 500),
                  onChanged: (v) => notifier.update(
                    (f) => f.copyWith(
                      // Krajnje vrijednosti = bez ograničenja.
                      minPrice: v.start <= lo ? null : v.start,
                      maxPrice: v.end >= hi ? null : v.end,
                      clearPrice: v.start <= lo && v.end >= hi,
                    ),
                  ),
                ),
                title(t('Prodavatelj')),
                SegmentedButton<SellerFilter>(
                  showSelectedIcon: false,
                  segments: [
                    for (final s in SellerFilter.values)
                      ButtonSegment(
                        value: s,
                        label: Text(s == SellerFilter.all ? t('Svi') : s.label),
                      ),
                  ],
                  selected: {f.seller},
                  onSelectionChanged: (s) =>
                      notifier.update((f) => f.copyWith(seller: s.first)),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: f.onlyFavorites,
                  onChanged: (v) =>
                      notifier.update((f) => f.copyWith(onlyFavorites: v)),
                  secondary: const Icon(
                    Icons.favorite,
                    color: Color(0xFFFF5C8A),
                  ),
                  title: Text(t('Samo favoriti')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: f.onlyAffordable,
                  onChanged: (v) =>
                      notifier.update((f) => f.copyWith(onlyAffordable: v)),
                  secondary: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(t('Mogu kupiti')),
                  subtitle: Text(
                    t('Imam dovoljno novca (s 2% naknade): {0}', [
                      formatCredits(state.currentUser?.credits ?? 0),
                    ]),
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('discounted-switch'),
                  contentPadding: EdgeInsets.zero,
                  value: f.onlyDiscounted,
                  onChanged: (v) =>
                      notifier.update((f) => f.copyWith(onlyDiscounted: v)),
                  secondary: const Icon(Icons.local_offer_outlined),
                  title: Text(t('Samo na popustu')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: f.withPhotos,
                  onChanged: (v) =>
                      notifier.update((f) => f.copyWith(withPhotos: v)),
                  secondary: const Icon(Icons.photo_outlined),
                  title: Text(t('Samo s fotografijom')),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('filters-apply'),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    results == 0
                        ? t('Nema rezultata')
                        : t('Prikaži {0} rezultata', [results]),
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

/// Uklonjivi čipovi aktivnih filtera + "Očisti sve".
class ActiveFilterChips extends ConsumerWidget {
  const ActiveFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(marketFilterProvider);
    final n = ref.read(marketFilterProvider.notifier);
    if (f.activeCount == 0) return const SizedBox.shrink();
    final chips = <Widget>[
      if (f.section != null)
        _chip(
          f.section!.label,
          () => n.update((f) => f.copyWith(clearSection: true)),
        ),
      if (f.category != null)
        _chip(
          f.category!.label,
          () => n.update((f) => f.copyWith(clearCategory: true)),
        ),
      for (final c in f.conditions)
        _chip(
          c.label,
          () => n.update(
            (f) => f.copyWith(conditions: {...f.conditions}..remove(c)),
          ),
        ),
      if (f.minPrice != null || f.maxPrice != null)
        _chip(
          f.minPrice != null && f.maxPrice != null
              ? '${formatNumber(f.minPrice!)}–${formatNumber(f.maxPrice!)}'
              : f.minPrice != null
              ? t('od {0}', [formatNumber(f.minPrice!)])
              : t('do {0}', [formatNumber(f.maxPrice!)]),
          () => n.update((f) => f.copyWith(clearPrice: true)),
        ),
      if (f.seller != SellerFilter.all)
        _chip(
          f.seller.label,
          () => n.update((f) => f.copyWith(seller: SellerFilter.all)),
        ),
      if (f.onlyFavorites)
        _chip(
          t('Favoriti'),
          () => n.update((f) => f.copyWith(onlyFavorites: false)),
        ),
      if (f.onlyAffordable)
        _chip(
          t('Mogu kupiti'),
          () => n.update((f) => f.copyWith(onlyAffordable: false)),
        ),
      if (f.onlyDiscounted)
        _chip(
          t('Na popustu'),
          () => n.update((f) => f.copyWith(onlyDiscounted: false)),
        ),
      if (f.withPhotos)
        _chip(
          t('S fotografijom'),
          () => n.update((f) => f.copyWith(withPhotos: false)),
        ),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final c in chips)
            Padding(padding: const EdgeInsets.only(right: 6), child: c),
          TextButton(
            key: const ValueKey('filters-clear-all'),
            onPressed: () => n.set(f.cleared()),
            child: Text(t('Očisti sve')),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, VoidCallback onRemove) => InputChip(
    label: Text(label),
    onDeleted: onRemove,
    deleteIcon: const Icon(Icons.close, size: 16),
    visualDensity: VisualDensity.compact,
    side: BorderSide(color: LoopColors.accent.withValues(alpha: 0.5)),
    backgroundColor: LoopColors.accent.withValues(alpha: 0.08),
  );
}
