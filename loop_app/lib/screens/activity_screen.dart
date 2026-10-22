import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/loop_transaction.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../l10n/tr.dart';

/// Povijest transakcija kao zaseban ekran (Profil → Novac i kupnje).
class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ActivityPage()));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Povijest transakcija'))),
    body: const ActivityScreen(),
  );
}

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
    final me = ref.watch(appProvider.select((s) => s.currentUserId)) ?? '';

    if (all.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: t('Još nema aktivnosti'),
        message: t('Kupnje i prodaje pojavit će se ovdje.'),
      );
    }

    double sum(TransactionType t) => all
        .where((tx) => tx.typeFor(me) == t)
        .fold(0.0, (acc, tx) => acc + tx.amountFor(me));
    final txs = _type == null
        ? all
        : all.where((tx) => tx.typeFor(me) == _type).toList();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SummaryTile(
                  icon: Icons.north_east,
                  label: t('Zarađeno prodajom'),
                  value: formatCredits(sum(TransactionType.sell)),
                  color: LoopColors.success,
                ),
                _SummaryTile(
                  icon: Icons.south_west,
                  label: t('Potrošeno na kupnje'),
                  value: formatCredits(sum(TransactionType.buy)),
                  color: LoopColors.accent,
                ),
                _SummaryTile(
                  icon: Icons.account_balance_outlined,
                  label: t('Isplaćeno na račun'),
                  value: formatCredits(sum(TransactionType.payout)),
                  color: LoopColors.admin,
                ),
              ],
            ),
            SizedBox(height: 16),
            SegmentedButton<TransactionType?>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: null, label: Text(t('Sve'))),
                ButtonSegment(
                  value: TransactionType.buy,
                  label: Text(t('Kupnje')),
                  icon: Icon(Icons.south_west, size: 16),
                ),
                ButtonSegment(
                  value: TransactionType.sell,
                  label: Text(t('Prodaje')),
                  icon: Icon(Icons.north_east, size: 16),
                ),
                ButtonSegment(
                  value: TransactionType.payout,
                  label: Text(t('Isplate')),
                  icon: Icon(Icons.account_balance_outlined, size: 16),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (sel) => setState(() => _type = sel.first),
            ),
            const SizedBox(height: 16),
            if (txs.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(
                  child: Text(
                    t('Nema transakcija ovog tipa.'),
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
                  child: TransactionTile(tx: txs[i], viewerId: me),
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
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
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
  const TransactionTile({super.key, required this.tx, required this.viewerId});

  /// Korisnik iz čije se perspektive prikazuje (kupnja ili prodaja).
  final String viewerId;
  final LoopTransaction tx;

  @override
  Widget build(BuildContext context) {
    final type = tx.typeFor(viewerId);
    // Priljev (prodaja, dopuna) je zelen i s "+"; kupnja je neutralna —
    // kupnja je normalan dio tržnice, ne "gubitak".
    final isSell =
        type == TransactionType.sell ||
        type == TransactionType.topUp ||
        // Zamjena: nadoplatu dobiva vlasnik traženog predmeta.
        (type == TransactionType.swap && tx.sellerId == viewerId);
    final color = isSell ? LoopColors.success : LoopColors.textPrimary;
    final icon = switch (type) {
      TransactionType.sell => Icons.north_east,
      TransactionType.buy => Icons.shopping_bag_outlined,
      TransactionType.topUp => Icons.add_card,
      TransactionType.payout => Icons.account_balance_outlined,
      TransactionType.auctionFee => Icons.gavel,
      TransactionType.delivery => Icons.local_shipping_outlined,
      TransactionType.swap => Icons.swap_horiz,
      TransactionType.promotion => Icons.campaign_outlined,
    };
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
              child: Icon(icon, color: color),
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
                    '${tx.isAuction ? t('Aukcija · ') : ''}${type.label} · '
                    '${formatDateTime(tx.createdAt)}',
                    style: TextStyle(
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
                  '${isSell ? '+' : '−'}${formatCredits(tx.amountFor(viewerId))}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
                Text(
                  switch (type) {
                    TransactionType.topUp => t('plaćeno {0}', [
                      formatEuro(tx.price),
                    ]),
                    TransactionType.auctionFee => t('naknada za objavu'),
                    TransactionType.delivery => t('trošak dostave'),
                    TransactionType.promotion => t('isticanje'),
                    TransactionType.sell => t('bez naknade'),
                    TransactionType.payout => t('na bankovni račun'),
                    TransactionType.buy ||
                    TransactionType.swap => t('plaćeno karticom'),
                  },
                  style: TextStyle(
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
