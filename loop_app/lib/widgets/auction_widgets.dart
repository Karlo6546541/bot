import 'package:flutter/material.dart';
import 'trust_widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/auction.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'countdown.dart';
import 'trade_actions.dart';

/// Jednostavno licitiranje u jednom listu: brzi iznosi, vlastiti iznos,
/// automatska ponuda ("licitiraj umjesto mene do…") i "Kupi odmah".
Future<void> showBidSheet(
  BuildContext context,
  WidgetRef ref,
  String auctionId,
) async {
  if (blockGuest(context)) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: LoopColors.background,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => _BidSheet(auctionId: auctionId),
  );
}

class _BidSheet extends ConsumerStatefulWidget {
  const _BidSheet({required this.auctionId});
  final String auctionId;

  @override
  ConsumerState<_BidSheet> createState() => _BidSheetState();
}

class _BidSheetState extends ConsumerState<_BidSheet> {
  final _amount = TextEditingController();
  final _max = TextEditingController();
  bool _auto = false;
  String? _error;
  bool _busy = false;
  bool _init = false;

  @override
  void dispose() {
    _amount.dispose();
    _max.dispose();
    super.dispose();
  }

  static double? _parse(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on TradeException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bid(Auction a, bool leading) async {
    final c = ref.read(appProvider.notifier);
    final amount = leading ? a.currentPrice : _parse(_amount.text);
    final max = _auto || leading ? _parse(_max.text) : null;
    if (amount == null || ((_auto || leading) && max == null)) {
      setState(() => _error = t('Unesi iznos'));
      return;
    }
    await _run(() async {
      final lead = await c.placeBid(a.id, amount, maxAmount: max);
      if (!mounted) return;
      Navigator.pop(context);
      showLoopSnackBar(
        leading
            ? t('Automatska ponuda je povišena na {0}', [formatCredits(max!)])
            : lead
            ? t('Ponuda prihvaćena — vodiš!')
            : t('Netko ima višu automatsku ponudu — nadmašen si. Probaj više.'),
        error: !lead && !leading,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final a = s.auctionById(widget.auctionId);
    final me = s.currentUser;
    if (a == null || me == null || !a.isActive) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(t('Aukcija je završila.')),
      );
    }
    final leading = a.highestBid?.userId == me.id;
    final min = a.minNextBid;
    if (!_init) {
      _init = true;
      _amount.text = _fmt(min);
      final myMax = a.autoMaxOf(me.id);
      _max.text = _fmt(
        roundCredits((myMax ?? (leading ? a.currentPrice : min)) * 1.25),
      );
    }
    final quick = <double>{
      min,
      roundCredits(min + a.minIncrement),
      roundCredits(min + a.minIncrement * 3),
    }.toList();
    final bold = const TextStyle(fontWeight: FontWeight.w800);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              a.deviceName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    a.bids.isEmpty
                        ? t('Početna cijena {0}', [
                            formatCredits(a.currentPrice),
                          ])
                        : t('Trenutno {0} · {1} ponuda', [
                            formatCredits(a.currentPrice),
                            '${a.bids.length}',
                          ]),
                    style: bold,
                  ),
                ),
                const Icon(Icons.timer_outlined, size: 18),
                const SizedBox(width: 4),
                AuctionCountdown(
                  endsAt: a.endsAt,
                  showIcon: false,
                  style: bold,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Pobjedniku se naplaćuje automatski s ove kartice.
            const Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [BuyerProtectionBadge(compact: true), WalletChip()],
            ),
            const SizedBox(height: 14),
            if (leading) ...[
              _Note(
                icon: Icons.emoji_events_outlined,
                text: a.autoMaxOf(me.id) == null
                    ? t(
                        'Vodiš s {0}. Možeš postaviti automatsku ponudu — licitirat ćemo umjesto tebe ako te netko pokuša nadmašiti.',
                        [formatCredits(a.currentPrice)],
                      )
                    : t('Vodiš s {0}. Automatski licitiramo za tebe do {1}.', [
                        formatCredits(a.currentPrice),
                        formatCredits(a.autoMaxOf(me.id)!),
                      ]),
              ),
              const SizedBox(height: 12),
              _field(
                _max,
                t('Licitiraj automatski najviše do'),
                key: const ValueKey('bid-max'),
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in quick)
                    ChoiceChip(
                      label: Text(formatCredits(v)),
                      selected: _parse(_amount.text) == v,
                      onSelected: (_) => setState(() {
                        _amount.text = _fmt(v);
                        _error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _field(
                _amount,
                t('Tvoja ponuda (najmanje {0})', [formatCredits(min)]),
                key: const ValueKey('bid-amount'),
              ),
              SwitchListTile(
                key: const ValueKey('bid-auto'),
                contentPadding: EdgeInsets.zero,
                value: _auto,
                onChanged: (v) => setState(() => _auto = v),
                title: Text(t('Automatska ponuda')),
                subtitle: Text(
                  t(
                    'Licitiramo umjesto tebe najmanjim korakom do iznosa koji odabereš.',
                  ),
                ),
              ),
              if (_auto)
                _field(_max, t('Najviše do'), key: const ValueKey('bid-max')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: LoopColors.error)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('bid-submit'),
              onPressed: _busy ? null : () => _bid(a, leading),
              icon: const Icon(Icons.gavel),
              label: Text(
                leading
                    ? t('Spremi automatsku ponudu')
                    : t('Licitiraj {0}', [
                        formatCredits(_parse(_amount.text) ?? min),
                      ]),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              t(
                'Ponude su obvezujuće. Pobjednik plaća karticom tek kad aukcija završi — ništa se ne blokira unaprijed.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {Key? key}) => TextField(
    key: key,
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    onChanged: (_) => setState(() => _error = null),
    decoration: InputDecoration(labelText: label, suffixText: '€'),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: LoopColors.surfaceHover,
      borderRadius: BorderRadius.circular(kRadius),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: LoopColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

/// Zvono: prati aukciju (podsjetnik 10 minuta prije kraja).
class WatchAuctionButton extends ConsumerWidget {
  const WatchAuctionButton({super.key, required this.auctionId, this.color});
  final String auctionId;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final a = s.auctionById(auctionId);
    final me = s.currentUserId;
    if (a == null || me == null || a.sellerId == me || !a.isActive) {
      return const SizedBox.shrink();
    }
    final on = a.watchers.contains(me);
    return IconButton(
      key: const ValueKey('watch-auction'),
      tooltip: on ? t('Ne prati aukciju') : t('Prati aukciju'),
      icon: Icon(
        on ? Icons.notifications_active : Icons.notifications_none,
        color: color ?? (on ? LoopColors.accent : null),
      ),
      onPressed: () async {
        if (blockGuest(context)) return;
        final now = await ref
            .read(appProvider.notifier)
            .toggleWatchAuction(auctionId);
        showLoopSnackBar(
          now
              ? t('Pratiš aukciju — javit ćemo ti 10 minuta prije kraja.')
              : t('Više ne pratiš aukciju.'),
        );
      },
    );
  }
}
