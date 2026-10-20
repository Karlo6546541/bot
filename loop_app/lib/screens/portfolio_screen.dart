import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../models/portfolio_point.dart';
import '../models/user_status.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/device_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/portfolio_chart.dart';
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
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: PortfolioChart(
              history: state.myHistory,
              current: PortfolioPoint(
                time: DateTime.now(),
                credits: user.credits,
                portfolio: portfolioValue,
              ),
            ),
          ),
        ),
        if (devices.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _Breakdown.of(devices),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Moji predmeti',
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
              message: 'Dodaj svoj predmet ili kupi nešto u Marketu.',
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
                    _Stat(label: 'Predmeti', value: '$deviceCount'),
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

class _Slice {
  const _Slice(this.label, this.icon, this.color, this.value);
  final String label;
  final IconData icon;
  final Color color;
  final double value;
}

/// Raspodjela vrijednosti portfolija (segmentirana traka). Grupira po
/// odjeljcima; ako su svi predmeti u jednom odjeljku, po kategorijama.
/// Redoslijed segmenata prati fiksni red odjeljaka/kategorija, pa boja
/// uvijek pripada istom entitetu.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.title, required this.slices});

  factory _Breakdown.of(List<Device> devices) {
    final bySection = AppState.valueBySection(devices);
    if (bySection.length > 1) {
      return _Breakdown(
        title: 'Raspodjela po odjeljcima',
        slices: [
          for (final sec in ItemSection.values)
            if (bySection[sec] != null)
              _Slice(sec.label, sec.icon, sec.color, bySection[sec]!),
        ],
      );
    }
    final byCat = AppState.valueByCategory(devices);
    return _Breakdown(
      title: 'Raspodjela po kategorijama',
      slices: [
        for (final c in DeviceCategory.values)
          if (byCat[c] != null) _Slice(c.label, c.icon, c.color, byCat[c]!),
      ],
    );
  }

  final String title;
  final List<_Slice> slices;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold(0.0, (sum, x) => sum + x.value);
    String pct(_Slice x) => '${(x.value / total * 100).round()}%';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (var i = 0; i < slices.length; i++) ...[
                      // 2px razmak u boji pozadine između segmenata.
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        // flex mora biti cijeli broj; promili su dovoljno precizni.
                        flex: (slices[i].value / total * 1000).round().clamp(
                          1,
                          1000,
                        ),
                        child: Tooltip(
                          message:
                              '${slices[i].label}: ${formatCredits(slices[i].value)} (${pct(slices[i])})',
                          child: Container(color: slices[i].color),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Legenda: obojena oznaka uz tekst u neutralnoj boji.
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final x in slices)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: x.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(x.icon, size: 14, color: LoopColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '${x.label} · ${pct(x)}',
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
