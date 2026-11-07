import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'auctions_screen.dart' show BrowseItem;

/// Odabrani filteri showova (Sortiraj, Kategorija, Vrijeme showa, Format
/// showa, Ocjena prodavača).
class ShowFilters {
  const ShowFilters({
    this.sort = ShowSort.recommended,
    this.categories = const {},
    this.time,
    this.formats = const {},
    this.minRating = 0,
  });

  final ShowSort sort;
  final Set<DeviceCategory> categories;

  /// 'live' | 'soon' | null (sve).
  final String? time;
  final Set<LotMode> formats;

  /// 0 = svi; 4, 4.5 ili 5.
  final double minRating;

  bool get isDefault =>
      sort == ShowSort.recommended &&
      categories.isEmpty &&
      time == null &&
      formats.isEmpty &&
      minRating == 0;

  int get activeCount =>
      (sort == ShowSort.recommended ? 0 : 1) +
      categories.length +
      (time == null ? 0 : 1) +
      formats.length +
      (minRating == 0 ? 0 : 1);

  ShowFilters copyWith({
    ShowSort? sort,
    Set<DeviceCategory>? categories,
    Object? time = _keep,
    Set<LotMode>? formats,
    double? minRating,
  }) => ShowFilters(
    sort: sort ?? this.sort,
    categories: categories ?? this.categories,
    time: time == _keep ? this.time : time as String?,
    formats: formats ?? this.formats,
    minRating: minRating ?? this.minRating,
  );

  static const _keep = Object();

  /// Primjena filtera i sortiranja na liveove.
  List<BrowseItem> apply(List<BrowseItem> items, AppState s) {
    final list = [
      for (final i in items)
        if (i.show != null &&
            (categories.isEmpty || i.categories.any(categories.contains)) &&
            (time == null ||
                (time == 'live' && (i.live?.isLive ?? false)) ||
                (time == 'soon' && (i.live?.isScheduled ?? false))) &&
            (formats.isEmpty ||
                i.show!.lots.any((l) => formats.contains(l.mode))) &&
            (minRating == 0 ||
                (s.ratingOf(i.show!.hostId).count > 0 &&
                    s.ratingOf(i.show!.hostId).average >= minRating)))
          i,
    ];
    if (sort != ShowSort.recommended) {
      list.sort((a, b) {
        final d = (a.live?.viewers ?? 0).compareTo(b.live?.viewers ?? 0);
        return sort == ShowSort.viewersHigh ? -d : d;
      });
    }
    return list;
  }
}

enum ShowSort { recommended, viewersHigh, viewersLow }

enum _Section { sort, category, time, format, rating }

/// Veliki filter-sheet s izbornikom lijevo (kao Whatnot): vraća nove
/// filtere ili null ako je zatvoren bez primjene.
Future<ShowFilters?> showShowFilterSheet(
  BuildContext context, {
  required ShowFilters initial,
  required List<BrowseItem> items,
  required AppState state,
}) => showModalBottomSheet<ShowFilters>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: BoxConstraints(
    maxWidth: 640,
    maxHeight: MediaQuery.sizeOf(context).height * 0.9,
  ),
  builder: (_) => _FilterSheet(initial: initial, items: items, state: state),
);

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.items,
    required this.state,
  });
  final ShowFilters initial;
  final List<BrowseItem> items;
  final AppState state;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ShowFilters _f = widget.initial;
  _Section _section = _Section.sort;

  String _label(_Section s) => switch (s) {
    _Section.sort => t('Sortiraj'),
    _Section.category => t('Kategorija'),
    _Section.time => t('Vrijeme showa'),
    _Section.format => t('Format showa'),
    _Section.rating => t('Ocjena prodavača'),
  };

  Widget _radio<T>(
    String key,
    String label,
    T value,
    T group,
    ValueChanged<T> on,
  ) => InkWell(
    key: ValueKey(key),
    onTap: () => on(value),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(
            value == group
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
            color: value == group
                ? LoopColors.textPrimary
                : LoopColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
        ],
      ),
    ),
  );

  Widget _pill(String key, String label, bool on, VoidCallback tap, {int? n}) =>
      ChoiceChip(
        key: ValueKey(key),
        label: Text(n == null ? label : '$label  $n'),
        selected: on,
        onSelected: (_) => tap(),
      );

  Widget _content() {
    final lives = [
      for (final i in widget.items)
        if (i.show != null) i,
    ];
    switch (_section) {
      case _Section.sort:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _radio(
              'sort-recommended',
              t('Preporučeno'),
              ShowSort.recommended,
              _f.sort,
              (v) => setState(() => _f = _f.copyWith(sort: v)),
            ),
            _radio(
              'sort-high',
              t('Gledatelji: od najviše'),
              ShowSort.viewersHigh,
              _f.sort,
              (v) => setState(() => _f = _f.copyWith(sort: v)),
            ),
            _radio(
              'sort-low',
              t('Gledatelji: od najmanje'),
              ShowSort.viewersLow,
              _f.sort,
              (v) => setState(() => _f = _f.copyWith(sort: v)),
            ),
          ],
        );
      case _Section.category:
        final counts = <DeviceCategory, int>{};
        for (final i in lives) {
          for (final c in i.categories) {
            counts[c] = (counts[c] ?? 0) + 1;
          }
        }
        final cats = counts.keys.toList()
          ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
        return cats.isEmpty
            ? Text(
                t('Nema showova za filtriranje.'),
                style: TextStyle(color: LoopColors.textSecondary),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in cats)
                    _pill(
                      'cat-${c.name}',
                      c.label,
                      _f.categories.contains(c),
                      () => setState(() {
                        final next = {..._f.categories};
                        next.contains(c) ? next.remove(c) : next.add(c);
                        _f = _f.copyWith(categories: next);
                      }),
                      n: counts[c],
                    ),
                ],
              );
      case _Section.time:
        final live = lives.where((i) => i.live?.isLive ?? false).length;
        final soon = lives.where((i) => i.live?.isScheduled ?? false).length;
        return Wrap(
          spacing: 8,
          children: [
            _pill(
              'time-live',
              t('Uživo'),
              _f.time == 'live',
              () => setState(
                () => _f = _f.copyWith(time: _f.time == 'live' ? null : 'live'),
              ),
              n: live,
            ),
            _pill(
              'time-soon',
              t('Uskoro'),
              _f.time == 'soon',
              () => setState(
                () => _f = _f.copyWith(time: _f.time == 'soon' ? null : 'soon'),
              ),
              n: soon,
            ),
          ],
        );
      case _Section.format:
        int count(LotMode m) =>
            lives.where((i) => i.show!.lots.any((l) => l.mode == m)).length;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in LotMode.values)
              _pill(
                'format-${m.name}',
                '${m.emoji} ${m.label}',
                _f.formats.contains(m),
                () => setState(() {
                  final next = {..._f.formats};
                  next.contains(m) ? next.remove(m) : next.add(m);
                  _f = _f.copyWith(formats: next);
                }),
                n: count(m),
              ),
          ],
        );
      case _Section.rating:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _radio<double>(
              'rating-0',
              t('Sve ocjene'),
              0,
              _f.minRating,
              (v) => setState(() => _f = _f.copyWith(minRating: v)),
            ),
            _radio<double>(
              'rating-5',
              t('5 zvjezdica'),
              5,
              _f.minRating,
              (v) => setState(() => _f = _f.copyWith(minRating: v)),
            ),
            _radio<double>(
              'rating-45',
              t('4,5 i više'),
              4.5,
              _f.minRating,
              (v) => setState(() => _f = _f.copyWith(minRating: v)),
            ),
            _radio<double>(
              'rating-4',
              t('4 i više'),
              4,
              _f.minRating,
              (v) => setState(() => _f = _f.copyWith(minRating: v)),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _f.apply(widget.items, widget.state).length;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t('Filteri'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SizedBox(
              height: 420,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 150,
                    child: ListView(
                      children: [
                        for (final sec in _Section.values)
                          InkWell(
                            key: ValueKey('filter-section-${sec.name}'),
                            onTap: () => setState(() => _section = sec),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: _section == sec
                                        ? LoopColors.accent
                                        : Colors.transparent,
                                    width: 4,
                                  ),
                                ),
                              ),
                              child: Text(
                                _label(sec),
                                style: TextStyle(
                                  fontWeight: _section == sec
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  color: _section == sec
                                      ? LoopColors.textPrimary
                                      : LoopColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: LoopColors.surfaceHover),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _label(_section),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _content(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('filter-clear'),
                    onPressed: () => setState(() => _f = const ShowFilters()),
                    child: Text(t('Očisti')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('filter-apply'),
                    onPressed: () => Navigator.pop(context, _f),
                    child: Text(t('{0} rezultata', ['$results'])),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
