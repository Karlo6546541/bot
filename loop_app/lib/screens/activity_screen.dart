import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/loop_transaction.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';

/// Povijest transakcija trenutnog korisnika, najnovije na vrhu,
/// sa sažetkom i filterom (Sve / Kupnje / Prodaje).
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  /// `null` = sve transakcije.
  TransactionType? _type;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(appProvider.select((s) => s.myTransactions));

    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Još nema aktivnosti',
        message: 'Kupnje i prodaje pojavit će se ovdje.',
      );
    }

    double sum(TransactionType t) =>
        all.where((tx) => tx.type == t).fold(0.0, (acc, tx) => acc + tx.amount);
    final fees = all.fold(0.0, (acc, tx) => acc + tx.fee);
    final txs = _type == null
        ? all
        : all.where((tx) => tx.type == _type).toList();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SummaryTile(
                  icon: Icons.north_east,
                  label: 'Zarađeno prodajom',
                  value: formatCredits(sum(TransactionType.sell)),
                  color: LoopColors.success,
                ),
                _SummaryTile(
                  icon: Icons.south_west,
                  label: 'Potrošeno na kupnje',
                  value: formatCredits(sum(TransactionType.buy)),
                  color: const Color(0xFF5B8CFF),
                ),
                _SummaryTile(
                  icon: Icons.percent,
                  label: 'Plaćeni fee',
                  value: formatCredits(fees),
                  color: LoopColors.error,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<TransactionType?>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: null, label: Text('Sve')),
                ButtonSegment(
                  value: TransactionType.buy,
                  label: Text('Kupnje'),
                  icon: Icon(Icons.south_west, size: 16),
                ),
                ButtonSegment(
                  value: TransactionType.sell,
                  label: Text('Prodaje'),
                  icon: Icon(Icons.north_east, size: 16),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (sel) => setState(() => _type = sel.first),
            ),
            const SizedBox(height: 16),
            if (txs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(
                  child: Text(
                    'Nema transakcija ovog tipa.',
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ),
              ),
            for (var i = 0; i < txs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FadeSlideIn(
                  key: ValueKey(txs[i].id),
                  index: i,
                  child: TransactionTile(tx: txs[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.18), LoopColors.surface],
        ),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: LoopColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.tx});
  final LoopTransaction tx;

  @override
  Widget build(BuildContext context) {
    final isSell = tx.type == TransactionType.sell;
    final color = isSell ? LoopColors.success : LoopColors.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSell ? Icons.north_east : Icons.south_west,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${tx.type.label} · ${formatDateTime(tx.createdAt)}',
                    style: const TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isSell ? '+' : '−'}${formatCredits(tx.amount)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
                Text(
                  'fee ${formatCredits(tx.fee)}',
                  style: const TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
