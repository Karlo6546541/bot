import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
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
        'Uređaji',
        '${s.devices.length}',
        sub: '$onMarket u Marketu',
      ),
      _Tile(Icons.swap_horiz, 'Transakcije', '${s.transactions.length}'),
      _Tile(
        Icons.stacked_line_chart,
        'Ukupni volume',
        formatCredits(s.totalVolume),
      ),
      _Tile(Icons.percent, 'Prihod od fee-a (5%)', formatCredits(s.totalFees)),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
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
                        style: const TextStyle(color: LoopColors.textSecondary),
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
                          style: const TextStyle(
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
