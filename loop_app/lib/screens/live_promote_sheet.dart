import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/live_boost.dart';
import '../models/live_show.dart';
import '../providers/app_providers.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../widgets/loop_snackbar.dart';
import '../widgets/shop_widgets.dart';

/// "Promoviraj": brzi boost (15 min), promocija showa i community boost.
Future<void> showPromoteSheet(
  BuildContext context,
  WidgetRef ref,
  LiveShow show,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 520),
  builder: (_) => PromoteSheet(showId: show.id),
);

class PromoteSheet extends ConsumerStatefulWidget {
  const PromoteSheet({super.key, required this.showId});
  final String showId;

  @override
  ConsumerState<PromoteSheet> createState() => _PromoteSheetState();
}

class _PromoteSheetState extends ConsumerState<PromoteSheet> {
  BoostKind? _kind;
  double? _amount;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final show = s.liveShowById(widget.showId);
    if (show == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final st = s.liveStateOf(show, now);
    final boost = st.boost;
    final reminders = s.liveEvents
        .where((e) => e.showId == show.id && e.type == LiveEventType.remind)
        .length;
    final canQuick = st.isLive;
    final canShow = !st.isOver && boost.kind != BoostKind.show;
    final kind =
        _kind ??
        (canQuick
            ? BoostKind.quick
            : canShow
            ? BoostKind.show
            : null);
    final (low, high) = kind == BoostKind.show
        ? LiveBoost.suggestedShow(reminders)
        : LiveBoost.suggestedQuick(st.viewers);
    final min = kind == BoostKind.show ? LiveBoost.minShow : LiveBoost.minQuick;
    final amount = (_amount ?? low).clamp(min, LiveBoost.maxAmount).toDouble();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final card = Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget option(
      BoostKind k,
      IconData icon,
      String title,
      String text, {
      required bool enabled,
    }) {
      final selected = kind == k;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: card,
          borderRadius: BorderRadius.circular(kRadius),
          child: InkWell(
            key: ValueKey('promote-${k.name}'),
            borderRadius: BorderRadius.circular(kRadius),
            onTap: enabled
                ? () => setState(() {
                    _kind = k;
                    _amount = null;
                  })
                : null,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kRadius),
                border: Border.all(
                  color: selected ? LoopColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Opacity(
                opacity: enabled ? 1 : 0.45,
                child: Row(
                  children: [
                    Icon(icon, color: LoopColors.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(text, style: TextStyle(color: muted)),
                        ],
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: selected ? LoopColors.accent : muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> pay() async {
      if (kind == null) return;
      setState(() => _busy = true);
      final nav = Navigator.of(context);
      try {
        await ref.read(appProvider.notifier).liveBoost(show.id, kind, amount);
        nav.pop();
        showLoopSnackBar(
          kind == BoostKind.quick
              ? t('Boost je pokrenut na 15 minuta.')
              : t('Show je promoviran.'),
        );
      } on TradeException catch (e) {
        if (mounted) setState(() => _busy = false);
        showLoopSnackBar(e.message, error: true);
      }
    }

    final until = boost.until;
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('promote-sheet'),
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Promoviraj show'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
            ),
            const SizedBox(height: 4),
            Text(
              t('Promovirani show ide prvi na početnoj i u svojoj kategoriji.'),
              style: TextStyle(color: muted),
            ),
            if (boost.active && until != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('promote-active'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: LoopColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(kRadius),
                ),
                child: Text(
                  t('{0} traje do {1}', [
                    switch (boost.kind!) {
                      BoostKind.quick => t('Brzi boost'),
                      BoostKind.show => t('Promocija showa'),
                      BoostKind.community => t('Community boost'),
                    },
                    formatDateTime(until),
                  ]),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
            const SizedBox(height: 16),
            option(
              BoostKind.quick,
              Icons.bolt,
              t('Brzi boost · 15 min'),
              canQuick
                  ? t('Odmah na vrh, dok si uživo.')
                  : t('Dostupno kad kreneš uživo.'),
              enabled: canQuick,
            ),
            option(
              BoostKind.show,
              Icons.campaign_outlined,
              t('Promocija showa'),
              boost.kind == BoostKind.show
                  ? t('Show je već promoviran.')
                  : t('Istaknut u "Uskoro uživo" i do kraja showa.'),
              enabled: canShow,
            ),
            if (kind != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    key: const ValueKey('promote-minus'),
                    onPressed: amount > min
                        ? () => setState(() => _amount = amount - 1)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      formatCredits(amount),
                      key: const ValueKey('promote-amount'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 34,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('promote-plus'),
                    onPressed: amount < LiveBoost.maxAmount
                        ? () => setState(() => _amount = amount + 1)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  t('Predloženo {0}–{1} · oko {2} prikaza', [
                    formatCredits(low),
                    formatCredits(high),
                    '${LiveBoost.estimatedReach(amount)}',
                  ]),
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('promote-pay'),
                  onPressed: _busy ? null : pay,
                  child: Text(t('Plati {0}', [formatCredits(amount)])),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t(
                  'Plaća se karticom i vidi se u financijama. Promovirani show ima oznaku "Promovirano".',
                ),
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            _CommunityCard(show: show, boost: boost),
          ],
        ),
      ),
    );
  }
}

/// Community boost: kad [LiveBoost.communityGoal] gledatelja podijeli
/// show, dobiva 15 minuta boosta besplatno.
class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.show, required this.boost});
  final LiveShow show;
  final LiveBoost boost;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final n = boost.sharers.clamp(0, LiveBoost.communityGoal);
    return Container(
      key: const ValueKey('promote-community'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_outlined, color: LoopColors.buyNow),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('Community boost · besplatno'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '$n/${LiveBoost.communityGoal}',
                key: const ValueKey('promote-community-count'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: n / LiveBoost.communityGoal,
              minHeight: 6,
              color: LoopColors.buyNow,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            boost.communityUnlocked
                ? t('Otključano! Show dobiva 15 minuta boosta dok si uživo.')
                : t(
                    'Kad {0} gledatelja podijeli show, dobiva 15 minuta boosta besplatno.',
                    ['${LiveBoost.communityGoal}'],
                  ),
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('promote-share'),
            onPressed: () => shareLink(
              context,
              publicLink(live: show.id),
              text: t('Gledaj "{0}" uživo na Subhastu', [show.title]),
            ),
            icon: const Icon(Icons.ios_share, size: 18),
            label: Text(t('Podijeli show')),
          ),
        ],
      ),
    );
  }
}
