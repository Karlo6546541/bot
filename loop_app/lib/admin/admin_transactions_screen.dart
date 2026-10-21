import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/loop_transaction.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import 'admin_shell.dart';

class AdminTransactionsScreen extends ConsumerWidget {
  const AdminTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(appProvider.select((s) => s.transactions));
    if (txs.isEmpty) {
      return const EmptyState(
        icon: Icons.swap_horiz,
        title: 'Još nema transakcija',
      );
    }
    return AdminList(
      itemCount: txs.length,
      itemBuilder: (context, i) => _TxCard(tx: txs[i]),
    );
  }
}

class _TxCard extends StatelessWidget {
  const _TxCard({required this.tx});
  final LoopTransaction tx;

  @override
  Widget build(BuildContext context) {
    final isSell = tx.type == TransactionType.sell;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (isSell ? LoopColors.success : LoopColors.admin)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${tx.isAuction ? 'Aukcija · ' : ''}${tx.type.label}',
                    style: TextStyle(
                      color: isSell ? LoopColors.success : LoopColors.admin,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tx.deviceName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  formatDateTime(tx.createdAt),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 28,
              runSpacing: 8,
              children: [
                _Field('Buyer', tx.buyerLabel),
                _Field('Seller', tx.sellerLabel),
                if (tx.type == TransactionType.topUp) ...[
                  _Field('Plaćeno', formatEuro(tx.price)),
                  _Field('Krediti', formatCredits(tx.amount)),
                ] else if (tx.type == TransactionType.auctionFee) ...[
                  _Field('Naknada za objavu', formatCredits(tx.fee)),
                ] else ...[
                  _Field('Cijena', formatCredits(tx.price)),
                  _Field('Iznos', formatCredits(tx.amount)),
                  _Field('Fee', formatCredits(tx.fee)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
