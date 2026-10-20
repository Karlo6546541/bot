import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/device_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/status_badge.dart';
import '../widgets/trade_actions.dart';

/// Početna stranica: krediti, status, vrijednost i uređaji korisnika.
class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key, required this.onGoToMarket});

  final VoidCallback onGoToMarket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final user = state.currentUser;
    if (user == null) return const SizedBox.shrink();

    final devices = state.myDevices;
    final portfolioValue = state.portfolioValueOf(user.id);
    final total = state.totalValueOf(user);
    final status = state.statusOf(user);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _CreditsHero(
              credits: user.credits,
              badge: StatusBadge(status: status),
              portfolioValue: portfolioValue,
              totalValue: total,
              deviceCount: devices.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Moji uređaji',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (devices.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Portfolio je prazan',
              message: 'Dodaj svoj uređaj ili kupi nešto u Marketu.',
              action: OutlinedButton.icon(
                onPressed: onGoToMarket,
                icon: const Icon(Icons.storefront),
                label: const Text('Otvori Market'),
              ),
            ),
          )
        else
          DeviceGrid(
            devices: devices,
            itemBuilder: (context, d) => DeviceCard(
              device: d,
              actionLabel: 'Prodaj odmah',
              actionIcon: Icons.sell_outlined,
              onAction: () => confirmAndSell(context, ref, d),
            ),
          ),
      ],
    );
  }
}

class _CreditsHero extends StatelessWidget {
  const _CreditsHero({
    required this.credits,
    required this.badge,
    required this.portfolioValue,
    required this.totalValue,
    required this.deviceCount,
  });

  final double credits;
  final Widget badge;
  final double portfolioValue;
  final double totalValue;
  final int deviceCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LoopColors.accent.withValues(alpha: 0.22),
            LoopColors.surface,
          ],
        ),
        border: Border.all(color: LoopColors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'LOOP krediti',
                  style: TextStyle(color: LoopColors.textSecondary),
                ),
              ),
              badge,
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatNumber(credits),
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'LC',
                  style: TextStyle(
                    fontSize: 18,
                    color: LoopColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _Stat(
                label: 'Ukupna vrijednost',
                value: formatCredits(totalValue),
              ),
              _Stat(label: 'Portfolio', value: formatCredits(portfolioValue)),
              _Stat(label: 'Uređaji', value: '$deviceCount'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: LoopColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ],
    );
  }
}
