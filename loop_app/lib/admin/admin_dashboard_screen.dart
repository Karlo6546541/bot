import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../widgets/category_style.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final onMarket = s.devices.where((d) => d.isOnMarket).length;

    final tiles = [
      _Tile(Icons.group, 'Korisnici', '${s.users.length}'),
      _Tile(
        Icons.devices,
        'Predmeti',
        '${s.devices.length}',
        sub: '$onMarket u Marketu',
      ),
      _Tile(
        Icons.gavel,
        'Aukcije',
        '${s.activeAuctions.length}',
        sub: 'aktivnih · ${s.auctions.length} ukupno',
      ),
      _Tile(
        Icons.local_shipping_outlined,
        'Dostave',
        '${s.deliveries.where((d) => !d.isDelivered(DateTime.now())).length}',
        sub: 'u tijeku · ${s.deliveries.length} ukupno',
      ),
      _Tile(Icons.swap_horiz, 'Transakcije', '${s.transactions.length}'),
      _Tile(
        Icons.stacked_line_chart,
        'Ukupni volume',
        formatCredits(s.totalVolume),
      ),
      _Tile(Icons.percent, 'Prihod od fee-a (5%)', formatCredits(s.totalFees)),
      _Tile(Icons.add_card, 'Prodano kredita', formatEuro(s.totalTopUpEur)),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final t in tiles)
                SizedBox(
                  width: 260,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(t.icon, color: LoopColors.admin),
                          const SizedBox(height: 12),
                          Text(
                            t.label,
                            style: TextStyle(color: LoopColors.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t.value,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (t.sub != null)
                            Text(
                              t.sub!,
                              style: TextStyle(
                                color: LoopColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 804),
            child: _CategoryStats(devices: s.devices),
          ),
        ],
      ),
    );
  }
}

/// Broj i vrijednost predmeta po odjeljku, kao vodoravni stupci.
class _CategoryStats extends StatelessWidget {
  const _CategoryStats({required this.devices});
  final List<Device> devices;

  @override
  Widget build(BuildContext context) {
    final counts = <ItemSection, int>{};
    for (final d in devices) {
      counts[d.section] = (counts[d.section] ?? 0) + 1;
    }
    final values = AppState.valueBySection(devices);
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxCount = entries.isEmpty ? 1 : entries.first.value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Predmeti po odjeljcima',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              Text(
                'Nema predmeta.',
                style: TextStyle(color: LoopColors.textSecondary),
              ),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(e.key.icon, color: e.key.color, size: 20),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 130,
                      child: Text(e.key.label, overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: e.value / maxCount,
                          minHeight: 10,
                          color: e.key.color,
                          backgroundColor: LoopColors.background,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 130,
                      child: Text(
                        '${e.value} · ${formatCredits(values[e.key] ?? 0)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tile {
  const _Tile(this.icon, this.label, this.value, {this.sub});
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
}
