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
import 'add_device_screen.dart';
import 'auction_detail_screen.dart';
import 'buy_credits_screen.dart';
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
              held: state.heldCreditsOf(user.id),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _QuickActions(),
          ),
        ),
        if (state.showHowItWorks)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _HowItWorks(),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: PortfolioChart(
              history: state.myHistory,
              current: PortfolioPoint(
                time: DateTime.now(),
                credits: user.credits + state.heldCreditsOf(user.id),
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
            itemBuilder: (context, d) {
              final auction = state.activeAuctionFor(d.id);
              // Predmet na aukciji: umjesto prodaje vodi na aukciju.
              return DeviceCard(
                device: d,
                actionLabel: auction != null ? 'Na aukciji' : 'Prodaj odmah',
                actionIcon: auction != null ? Icons.gavel : Icons.sell_outlined,
                onAction: auction != null
                    ? () => AuctionDetailScreen.open(context, auction.id)
                    : () => confirmAndSell(context, ref, d),
                onTap: () => DeviceDetailScreen.open(context, d),
              );
            },
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
    required this.held,
  });

  final double held;
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
        borderRadius: BorderRadius.circular(kRadius * 1.6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [LoopColors.peach, LoopColors.sunny],
        ),
        boxShadow: LoopColors.softShadow,
      ),
      child: Stack(
        children: [
          // Razigrani dekorativni oblici u pozadini.
          Positioned(
            right: -40,
            top: -50,
            child: _Glow(color: LoopColors.lilac, size: 200),
          ),
          Positioned(
            right: 120,
            bottom: -70,
            child: _Glow(color: LoopColors.mint, size: 160),
          ),
          const Positioned(
            right: 24,
            top: 64,
            child: Text('🛍️', style: TextStyle(fontSize: 44)),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
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
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    StatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Tvoji krediti',
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
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
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          creditsWord(credits),
                          style: TextStyle(
                            fontSize: 20,
                            color: LoopColors.textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => BuyCreditsScreen.open(context),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Dopuni kredite'),
                    ),
                    _Pill(
                      icon: Icons.stacked_line_chart,
                      text: 'Ukupno ${formatCredits(totalValue)}',
                    ),
                    _Pill(
                      icon: Icons.inventory_2_outlined,
                      text:
                          '$deviceCount ${deviceCount == 1 ? 'predmet' : 'predmeta'}'
                          ' · ${formatCredits(portfolioValue)}',
                    ),
                    if (held > 0)
                      _Pill(
                        icon: Icons.lock_outline,
                        text: 'Blokirano ${formatCredits(held)}',
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _StatusProgress(status: status, total: totalValue),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bijela "tableta" s ikonom i tekstom na pastelnoj pozadini.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: LoopColors.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: LoopColors.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brze akcije: pastelne pločice prema glavnim radnjama.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.read(homeTabProvider.notifier);
    final actions = [
      (
        '🪙',
        'Kupi kredite',
        LoopColors.sunny,
        () => BuyCreditsScreen.open(context),
      ),
      (
        '📦',
        'Dodaj predmet',
        LoopColors.mint,
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AddDeviceScreen()),
        ),
      ),
      ('🛒', 'Istraži Market', LoopColors.sky, () => tabs.select(1)),
      ('🔨', 'Aukcije', LoopColors.lilac, () => tabs.select(2)),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final perRow = box.maxWidth > 640 ? 4 : 2;
        final w = (box.maxWidth - 10 * (perRow - 1)) / perRow;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (emoji, label, color, onTap) in actions)
              SizedBox(
                width: w,
                child: Material(
                  color: color,
                  borderRadius: BorderRadius.circular(kRadius),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(kRadius),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 26)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: LoopColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Kratko objašnjenje kako LOOP radi (može se zatvoriti).
class _HowItWorks extends ConsumerWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const steps = [
      ('1', '📸', 'Dodaj predmet', 'Uslikaj stvar koju više ne koristiš.'),
      (
        '2',
        '🔁',
        'Prodaj ili licitiraj',
        'Prodaj odmah ili na aukciji — dobivaš LOOP kredite.',
      ),
      (
        '3',
        '🎁',
        'Uzmi nešto novo',
        'Kredite troši na druge stvari u LOOP-u. Bez novca, samo razmjena.',
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Kako LOOP radi',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Sakrij',
                  onPressed: () =>
                      ref.read(appProvider.notifier).dismissHowItWorks(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (final (n, emoji, title, text) in steps)
                  SizedBox(
                    width: 250,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: LoopColors.peach,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$n. $title',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                text,
                                style: TextStyle(
                                  color: LoopColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: TextStyle(
                color: LoopColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
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
                        style: TextStyle(
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
