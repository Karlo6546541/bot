import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/delivery.dart';
import '../providers/app_providers.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import 'formatters.dart';
import 'trade_actions.dart';

/// Kupac: "Zatraži povrat" — razlog i kratak opis.
Future<void> showDisputeForm(BuildContext context, WidgetRef ref, Delivery d) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _DisputeForm(delivery: d),
    );

class _DisputeForm extends ConsumerStatefulWidget {
  const _DisputeForm({required this.delivery});
  final Delivery delivery;

  @override
  ConsumerState<_DisputeForm> createState() => _DisputeFormState();
}

class _DisputeFormState extends ConsumerState<_DisputeForm> {
  DisputeReason? _reason;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref
          .read(appProvider.notifier)
          .openDispute(widget.delivery.id, reason, _note.text);
      nav.pop();
      showLoopSnackBar(
        t('Zahtjev je poslan. Prodavatelj ima 3 dana za odgovor.'),
      );
    } on TradeException catch (e) {
      if (mounted) setState(() => _busy = false);
      showLoopSnackBar(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        key: const ValueKey('dispute-form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Zatraži povrat'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 4),
          Text(
            widget.delivery.deviceName,
            style: TextStyle(color: LoopColors.textSecondary),
          ),
          const SizedBox(height: 12),
          for (final r in DisputeReason.values)
            ListTile(
              key: ValueKey('dispute-reason-${r.name}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _reason == r
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: _reason == r ? LoopColors.accent : null,
              ),
              title: Text(r.label),
              onTap: () => setState(() => _reason = r),
            ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('dispute-note'),
            controller: _note,
            minLines: 2,
            maxLines: 4,
            maxLength: DeliveryDispute.maxNote,
            decoration: InputDecoration(
              labelText: t('Što se dogodilo? (neobavezno)'),
              alignLabelWithHint: true,
            ),
          ),
          Text(
            t(
              'Prodavatelj ima 3 dana za odgovor. Dok zahtjev traje, njegova zarada od ove prodaje je zadržana. Ako ne odgovori, novac ti se vraća automatski.',
            ),
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('dispute-send'),
            onPressed: _reason == null || _busy ? null : _send,
            child: Text(t('Pošalji zahtjev')),
          ),
        ],
      ),
    ),
  );
}

/// Stanje zahtjeva za povrat (kupac i prodavatelj); prodavatelj ovdje
/// prihvaća ili odbija.
class DisputeCard extends ConsumerWidget {
  const DisputeCard({super.key, required this.delivery, required this.seller});
  final Delivery delivery;
  final bool seller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = delivery;
    final dispute = d.dispute!;
    final color = switch (dispute.status) {
      DisputeStatus.open || DisputeStatus.review => LoopColors.accent,
      DisputeStatus.refunded => LoopColors.success,
      DisputeStatus.rejected => LoopColors.textSecondary,
    };
    final muted = TextStyle(color: LoopColors.textSecondary, fontSize: 13);
    final s = ref.watch(appProvider);
    return Container(
      key: ValueKey('dispute-card-${d.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.undo, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  seller ? t('Zahtjev za povrat') : t('Tvoj zahtjev za povrat'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dispute.status.label,
                  key: ValueKey('dispute-status-${dispute.status.name}'),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (seller)
            Text(
              d.deviceName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          Text(
            seller
                ? '${s.userLabel(d.buyerId)}: ${dispute.reason.label}'
                : dispute.reason.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (dispute.note.isNotEmpty) Text('„${dispute.note}”', style: muted),
          const SizedBox(height: 6),
          Text(switch (dispute.status) {
            DisputeStatus.open =>
              seller
                  ? t(
                      'Odgovori do {0}, inače se novac vraća kupcu. Zarada od ove prodaje je zadržana.',
                      [formatDateTime(dispute.respondBy)],
                    )
                  : t('Prodavatelj odgovara do {0}.', [
                      formatDateTime(dispute.respondBy),
                    ]),
            DisputeStatus.review => t(
              'Prodavatelj je odbio povrat. Subhasto odlučuje u roku od 3 dana.',
            ),
            DisputeStatus.refunded => t('{0} vraćeno na karticu kupca.', [
              formatCredits(dispute.refundAmount),
            ]),
            DisputeStatus.rejected => t('Zahtjev je odbijen.'),
          }, style: muted),
          if (seller && dispute.status == DisputeStatus.open) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: ValueKey('dispute-reject-${d.id}'),
                    onPressed: () => runWithLoading(
                      context,
                      () => ref
                          .read(appProvider.notifier)
                          .respondDispute(d.id, accept: false),
                      successMessage: t('Odbijeno. Odlučuje Subhasto.'),
                    ),
                    child: Text(t('Odbij')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: ValueKey('dispute-accept-${d.id}'),
                    onPressed: () => runWithLoading(
                      context,
                      () => ref
                          .read(appProvider.notifier)
                          .respondDispute(d.id, accept: true),
                      successMessage: t('Povrat je odobren.'),
                    ),
                    child: Text(t('Prihvati povrat')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
