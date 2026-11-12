import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auction.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/countdown.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';
import 'admin_shell.dart';
import '../l10n/tr.dart';

/// Pregled svih aukcija; admin može otkazati aktivnu aukciju
/// (vodeća ponuda se vraća ponuđaču).
class AdminAuctionsScreen extends ConsumerWidget {
  const AdminAuctionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auctions = ref.watch(appProvider.select((s) => s.auctions));
    if (auctions.isEmpty) {
      return EmptyState(icon: Icons.gavel, title: t('Nema aukcija'));
    }
    // Aktivne prve, zatim završene.
    final list = [
      ...auctions.where((a) => a.isActive),
      ...auctions.where((a) => !a.isActive),
    ];
    return AdminList(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final a = list[i];
        final top = a.highestBid;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.gavel, color: LoopColors.admin),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.deviceName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t('Prodavatelj: {0} · {1} ponuda{2}', [
                          a.sellerLabel,
                          a.bids.length,
                          top != null ? t(' · vodi {0}', [top.userLabel]) : '',
                        ]),
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            formatCredits(a.currentPrice),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (a.isActive)
                            AuctionCountdown(endsAt: a.endsAt)
                          else
                            Text(
                              a.status.label,
                              style: TextStyle(color: LoopColors.textSecondary),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (a.isActive)
                  TextButton.icon(
                    onPressed: () => _cancel(context, ref, a),
                    style: TextButton.styleFrom(
                      foregroundColor: LoopColors.error,
                    ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(t('Otkaži')),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, Auction a) async {
    final ok = await confirmDialog(
      context,
      title: t('Otkazati aukciju?'),
      message: t('"{0}" ostaje prodavatelju. {1}', [
        a.deviceName,
        a.highestBid != null
            ? t('Vodeća ponuda ({0}) vraća se ponuđaču.', [
                formatCredits(a.highestBid!.amount),
              ])
            : '',
      ]),
      confirmLabel: t('Otkaži'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).adminCancelAuction(a.id),
      successMessage: t('Aukcija otkazana'),
    );
  }
}
