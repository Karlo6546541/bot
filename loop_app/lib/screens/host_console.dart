import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/live_show.dart';
import '../providers/app_providers.dart';
import '../services/live_service.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../widgets/loop_snackbar.dart';
import '../services/trade_service.dart' show TradeException;
import 'live_screens.dart';
import 'seller_finance_screens.dart';

/// Širina od koje domaćin dobiva pult u tri stupca (predmeti, video,
/// statistika i gledatelji) umjesto mobilnog rasporeda.
const double kHostConsoleWidth = 1100;

const _panel = Color(0xFF17120F);
const _card = Color(0xFF26272C);

/// Lijevi stupac pulta: predmeti showa s filterom po vrsti i radnjama.
class HostLotsPanel extends ConsumerStatefulWidget {
  const HostLotsPanel({super.key, required this.showId});
  final String showId;

  @override
  ConsumerState<HostLotsPanel> createState() => _HostLotsPanelState();
}

class _HostLotsPanelState extends ConsumerState<HostLotsPanel> {
  /// all | auction | dutch | giveaway | sold
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final show = s.liveShowById(widget.showId);
    if (show == null) return const SizedBox.shrink();
    final st = s.liveStateOf(show, DateTime.now());
    final lots = [
      for (final l in st.lots)
        if (switch (_filter) {
          'auction' => l.mode == LotMode.auction,
          'dutch' => l.mode == LotMode.dutch,
          'giveaway' => l.mode == LotMode.giveaway,
          'sold' => l.status == LotStatus.sold,
          _ => true,
        })
          l,
    ];
    Widget chip(String id, String label) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        key: ValueKey('console-filter-$id'),
        label: Text(label),
        selected: _filter == id,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = id),
      ),
    );
    return ColoredBox(
      color: _panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    show.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton.filled(
                  key: const ValueKey('console-add'),
                  tooltip: t('Dodaj predmet'),
                  onPressed: () => showAddToShowSheet(context, ref, show),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                chip('all', t('Sve')),
                chip('auction', t('Aukcija')),
                chip('dutch', t('Pada cijena')),
                chip('giveaway', t('Nagradna igra')),
                chip('sold', t('Prodano')),
              ],
            ),
          ),
          Expanded(
            child: lots.isEmpty
                ? Center(
                    child: Text(
                      t('Nema predmeta u ovom prikazu.'),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: lots.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _LotRow(
                      showId: show.id,
                      lot: lots[i],
                      canStart:
                          st.canStart && lots[i].status == LotStatus.upcoming,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LotRow extends ConsumerWidget {
  const _LotRow({
    required this.showId,
    required this.lot,
    required this.canStart,
  });
  final String showId;
  final LotState lot;
  final bool canStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (label, color) = switch (lot.status) {
      LotStatus.running => (t('Licitira se'), LoopColors.live),
      LotStatus.sold => (t('Prodano'), LoopColors.buyNow),
      LotStatus.unsold => (t('Neprodano'), Colors.white54),
      LotStatus.skipped => (t('Preskočeno'), Colors.white54),
      LotStatus.upcoming => (t('Na redu'), Colors.white70),
    };
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lot.lot.deviceName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${lot.mode.label} · ${formatCredits(lot.price)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (canStart)
              FilledButton(
                key: ValueKey('console-start-${lot.index}'),
                style: FilledButton.styleFrom(
                  backgroundColor: LoopColors.live,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(64, 40),
                ),
                onPressed: () async {
                  try {
                    await ref
                        .read(appProvider.notifier)
                        .liveStartLot(showId, index: lot.index);
                  } on TradeException catch (e) {
                    showLoopSnackBar(e.message, error: true);
                  }
                },
                child: Text(t('Pokreni')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Desni stupac pulta: statistika uživo te gledatelji i aktivnost.
class HostStatsPanel extends ConsumerWidget {
  const HostStatsPanel({super.key, required this.showId});
  final String showId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final show = s.liveShowById(showId);
    if (show == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final events = ref.read(storageProvider).liveEventsOf(showId);
    final a = ShowAnalytics.of(s, show, events, now);
    final st = s.liveStateOf(show, now);

    Widget stat(String key, String label, String value) => Expanded(
      child: Container(
        key: ValueKey(key),
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
    return ColoredBox(
      color: _panel,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    stat('console-sales', t('Prodaja'), formatCredits(a.sales)),
                    stat('console-orders', t('Narudžbe'), '${a.orders}'),
                  ],
                ),
                Row(
                  children: [
                    stat(
                      'console-sph',
                      t('Prodaja / sat'),
                      formatCredits(a.salesPerHour),
                    ),
                    stat(
                      'console-aov',
                      t('Prosj. narudžba'),
                      formatCredits(a.averageOrder),
                    ),
                  ],
                ),
                Row(
                  children: [
                    stat(
                      'console-viewers',
                      t('Gledatelji sada'),
                      '${st.viewers}',
                    ),
                    stat('console-bids', t('Ponude'), '${a.bids}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: ViewersPanel(showId: showId)),
        ],
      ),
    );
  }
}
