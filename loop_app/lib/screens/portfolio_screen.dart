import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../models/user_status.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/device_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/status_badge.dart';
import '../widgets/trade_actions.dart';
import 'device_detail_screen.dart';

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
              name: user.name,
              credits: user.credits,
              status: status,
              portfolioValue: portfolioValue,
              totalValue: total,
              deviceCount: devices.length,
            ),
          ),
        ),
        if (devices.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _CategoryBreakdown(
                values: AppState.valueByCategory(devices),
                total: portfolioValue,
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
              onTap: () => DeviceDetailScreen.open(context, d),
            ),
          ),
      ],
    );
  }
}

class _CreditsHero extends StatelessWidget {
  const _CreditsHero({
    required this.name,
    required this.credits,
    required this.status,
    required this.portfolioValue,
    required this.totalValue,
    required this.deviceCount,
  });

  final String name;
  final double credits;
  final UserStatus status;
  final double portfolioValue;
  final double totalValue;
  final int deviceCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius * 1.5),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F3D33), Color(0xFF12203A), LoopColors.surface],
          stops: [0, 0.55, 1],
        ),
        border: Border.all(color: LoopColors.accent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: LoopColors.accent.withValues(alpha: 0.14),
            blurRadius: 40,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Dekorativni krugovi u pozadini.
          Positioned(
            right: -60,
            top: -60,
            child: _Glow(color: LoopColors.accent, size: 220),
          ),
          const Positioned(
            right: 80,
            bottom: -90,
            child: _Glow(color: Color(0xFF5B8CFF), size: 200),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Bok, $name 👋',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    StatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'LOOP krediti',
                  style: TextStyle(color: LoopColors.textSecondary),
                ),
                // Broj kredita se animira pri svakoj promjeni.
                TweenAnimationBuilder<double>(
                  tween: Tween(end: credits),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          formatNumber(value),
                          style: const TextStyle(
                            fontSize: 46,
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
                    _Stat(
                      label: 'Portfolio',
                      value: formatCredits(portfolioValue),
                    ),
                    _Stat(label: 'Uređaji', value: '$deviceCount'),
                  ],
                ),
                const SizedBox(height: 18),
                _StatusProgress(status: status, total: totalValue),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Traka napretka do sljedećeg statusa.
class _StatusProgress extends StatelessWidget {
  const _StatusProgress({required this.status, required this.total});
  final UserStatus status;
  final double total;

  @override
  Widget build(BuildContext context) {
    final next = status.next;
    final threshold = status.nextThreshold;
    final progress = threshold == null
        ? 1.0
        : ((total - status.floor) / (threshold - status.floor)).clamp(0.0, 1.0);
    final color = next?.color ?? status.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                next == null
                    ? 'Najviši status — Gold 🏆'
                    : 'Još ${formatCredits(threshold! - total)} do ${next.label}',
                style: const TextStyle(
                  color: LoopColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              color: color,
              backgroundColor: LoopColors.background.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }
}

/// Raspodjela vrijednosti portfolija po kategorijama (segmentirana traka).
class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.values, required this.total});
  final Map<DeviceCategory, double> values;
  final double total;

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Raspodjela po kategorijama',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final e in entries)
                      Expanded(
                        // flex mora biti cijeli broj; promili su dovoljno precizni.
                        flex: (e.value / total * 1000).round().clamp(1, 1000),
                        child: Container(color: e.key.color),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final e in entries)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(e.key.icon, size: 16, color: e.key.color),
                      const SizedBox(width: 6),
                      Text(
                        '${e.key.label} · ${(e.value / total * 100).round()}%',
                        style: const TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ),
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
