import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/device_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';

/// Filter kategorija u Marketu.
enum MarketFilter {
  all('Sve'),
  phones('Mobiteli'),
  laptops('Laptopi'),
  tablets('Tableti'),
  other('Ostalo');

  const MarketFilter(this.label);
  final String label;

  bool matches(DeviceCategory c) => switch (this) {
    MarketFilter.all => true,
    MarketFilter.phones => c == DeviceCategory.phone,
    MarketFilter.laptops => c == DeviceCategory.laptop,
    MarketFilter.tablets => c == DeviceCategory.tablet,
    MarketFilter.other =>
      c == DeviceCategory.audio ||
          c == DeviceCategory.console ||
          c == DeviceCategory.other,
  };
}

class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  final _search = TextEditingController();
  MarketFilter _filter = MarketFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final query = _search.text.trim().toLowerCase();
    final devices = state.marketDevices
        .where((d) => _filter.matches(d.category))
        .where(
          (d) =>
              query.isEmpty ||
              d.name.toLowerCase().contains(query) ||
              d.model.toLowerCase().contains(query),
        )
        .toList();
    final credits = state.currentUser?.credits ?? 0;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dostupno: ${formatCredits(credits)} · fee 5% na kupnju',
                  style: const TextStyle(color: LoopColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Pretraži po nazivu…',
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
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<MarketFilter>(
                        initialValue: _filter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.filter_list),
                        ),
                        borderRadius: BorderRadius.circular(kRadius),
                        dropdownColor: LoopColors.surfaceHover,
                        items: [
                          for (final f in MarketFilter.values)
                            DropdownMenuItem(value: f, child: Text(f.label)),
                        ],
                        onChanged: (f) => setState(() => _filter = f!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (devices.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off,
              title: state.marketDevices.isEmpty
                  ? 'Market je trenutno prazan'
                  : 'Nema rezultata',
              message: state.marketDevices.isEmpty
                  ? 'Prodani uređaji pojavljuju se ovdje.'
                  : 'Promijeni pretragu ili filter.',
            ),
          )
        else
          DeviceGrid(
            devices: devices,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemBuilder: (context, d) => DeviceCard(
              device: d,
              actionLabel: 'Kupi odmah',
              actionIcon: Icons.shopping_bag_outlined,
              onAction: () => confirmAndBuy(context, ref, d),
            ),
          ),
      ],
    );
  }
}
