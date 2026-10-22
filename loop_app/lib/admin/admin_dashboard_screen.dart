import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/dac7.dart';
import '../services/file_saver/file_saver.dart';
import '../widgets/loop_snackbar.dart';
import '../widgets/category_style.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../l10n/tr.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final onMarket = s.devices.where((d) => d.isOnMarket).length;

    final tiles = [
      _Tile(Icons.group, t('Korisnici'), '${s.users.length}'),
      _Tile(
        Icons.devices,
        t('Predmeti'),
        '${s.devices.length}',
        sub: t('{0} u Marketu', [onMarket]),
      ),
      _Tile(
        Icons.gavel,
        t('Aukcije'),
        '${s.activeAuctions.length}',
        sub: t('aktivnih · {0} ukupno', [s.auctions.length]),
      ),
      _Tile(
        Icons.local_shipping_outlined,
        t('Dostave'),
        '${s.deliveries.where((d) => !d.isDelivered(DateTime.now())).length}',
        sub: t('u tijeku · {0} ukupno', [s.deliveries.length]),
      ),
      _Tile(Icons.swap_horiz, t('Transakcije'), '${s.transactions.length}'),
      _Tile(
        Icons.stacked_line_chart,
        t('Ukupni volume'),
        formatCredits(s.totalVolume),
      ),
      _Tile(
        Icons.percent,
        t('Prihod od naknade (2%)'),
        formatCredits(s.totalFees),
      ),
      _Tile(
        Icons.account_balance_outlined,
        t('Isplaćeno prodavateljima'),
        formatCredits(s.totalPayouts),
      ),
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
            child: _Dac7Card(state: s),
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

/// DAC7: prodavatelji koje treba prijaviti Poreznoj upravi (rok 31. 1.).
class _Dac7Card extends StatefulWidget {
  const _Dac7Card({required this.state});
  final AppState state;

  @override
  State<_Dac7Card> createState() => _Dac7CardState();
}

class _Dac7CardState extends State<_Dac7Card> {
  late int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final sellers = Dac7.sellers(s.users, s.transactions, _year);
    final reportable = sellers.where((x) => x.reportable).toList();
    final missing = reportable.where((x) => x.missingData).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('DAC7 izvještaj (Porezna uprava)'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                DropdownButton<int>(
                  value: _year,
                  items: [
                    for (var y = DateTime.now().year; y >= 2024; y--)
                      DropdownMenuItem(value: y, child: Text('$y')),
                  ],
                  onChanged: (y) => setState(() => _year = y ?? _year),
                ),
              ],
            ),
            Text(
              t(
                'Prijavljuju se prodavatelji s {0}+ prodaja ili više od {1} godišnje. Rok: 31. siječnja sljedeće godine.',
                ['${Dac7.minSales}', formatCredits(Dac7.minAmount)],
              ),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Text(
              t('{0} prodavatelja s prodajom · {1} za prijavu', [
                '${sellers.length}',
                '${reportable.length}',
              ]),
              key: const ValueKey('dac7-count'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (missing > 0)
              Text(
                t('{0} bez podataka prodavatelja — zatraži ih.', ['$missing']),
                style: TextStyle(color: LoopColors.error, fontSize: 12),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('dac7-export'),
              onPressed: () async {
                final where = await saveTextFile(
                  'dac7-$_year.csv',
                  Dac7.csv(sellers, _year),
                );
                showLoopSnackBar(t('Spremljeno: {0}', [where]));
              },
              icon: const Icon(Icons.download_outlined),
              label: Text(t('Preuzmi CSV')),
            ),
          ],
        ),
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
            Text(
              t('Predmeti po odjeljcima'),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              Text(
                t('Nema predmeta.'),
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
