import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/report.dart';
import '../models/review.dart';
import '../providers/app_providers.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import 'formatters.dart';
import 'loop_snackbar.dart';

const _starColor = Color(0xFFF5A623);

/// "★ 4,7 (12)" — prosjek ocjena prodavatelja.
class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.rating, this.compact = false});

  final Rating rating;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (rating.count == 0) {
      return Text(
        t('Još nema ocjena'),
        style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
      );
    }
    final avg = formatNumber((rating.average * 10).round() / 10);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, color: _starColor, size: compact ? 16 : 20),
        const SizedBox(width: 2),
        Text(
          compact ? avg : t('{0} ({1} ocjena)', [avg, rating.count]),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: compact ? 13 : 14,
          ),
        ),
      ],
    );
  }
}

/// Niz zvjezdica (prikaz ili odabir).
class StarRow extends StatelessWidget {
  const StarRow({
    super.key,
    required this.stars,
    this.onSelect,
    this.size = 18,
  });

  final int stars;
  final ValueChanged<int>? onSelect;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++)
        onSelect == null
            ? Icon(
                i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _starColor,
                size: size,
              )
            : IconButton(
                key: ValueKey('star-$i'),
                tooltip: '$i',
                visualDensity: VisualDensity.compact,
                onPressed: () => onSelect!(i),
                icon: Icon(
                  i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: _starColor,
                  size: size,
                ),
              ),
    ],
  );
}

/// Jedna ocjena u popisu.
class ReviewTile extends StatelessWidget {
  const ReviewTile({super.key, required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StarRow(stars: review.stars, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${review.buyerLabel} · ${formatDate(review.createdAt)}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
        if (review.comment.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(review.comment),
        ],
        Text(
          review.deviceName,
          style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
        ),
      ],
    ),
  );
}

/// Ocjena prodavatelja nakon primljene pošiljke. Vraća `true` ako je
/// ocjena spremljena.
Future<bool> showReviewDialog(
  BuildContext context,
  WidgetRef ref, {
  required String deliveryId,
  required String sellerLabel,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _ReviewDialog(deliveryId: deliveryId, sellerLabel: sellerLabel),
  );
  return saved ?? false;
}

class _ReviewDialog extends ConsumerStatefulWidget {
  const _ReviewDialog({required this.deliveryId, required this.sellerLabel});
  final String deliveryId;
  final String sellerLabel;

  @override
  ConsumerState<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends ConsumerState<_ReviewDialog> {
  int _stars = 0;
  final _comment = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_stars == 0) {
      setState(() => _error = t('Odaberi od 1 do 5 zvjezdica.'));
      return;
    }
    try {
      await ref
          .read(appProvider.notifier)
          .reviewSeller(widget.deliveryId, _stars, _comment.text);
      if (mounted) Navigator.pop(context, true);
      showLoopSnackBar(t('Hvala na ocjeni! ⭐'));
    } on TradeException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t('Ocijeni prodavatelja {0}', [widget.sellerLabel])),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: StarRow(
              stars: _stars,
              size: 34,
              onSelect: (s) => setState(() {
                _stars = s;
                _error = null;
              }),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            maxLength: Review.maxComment,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(
              labelText: t('Komentar (neobavezno)'),
              hintText: t('npr. Sve kao u opisu, brza dostava.'),
            ),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: LoopColors.error)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(t('Kasnije')),
      ),
      FilledButton(onPressed: _save, child: Text(t('Pošalji ocjenu'))),
    ],
  );
}

/// Prijava oglasa ili korisnika adminu.
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String targetType,
  required String targetId,
  required String targetLabel,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ReportSheet(
    targetType: targetType,
    targetId: targetId,
    targetLabel: targetLabel,
  ),
);

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    required this.targetLabel,
  });
  final String targetType;
  final String targetId;
  final String targetLabel;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  ReportReason? _reason;
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
    try {
      await ref
          .read(appProvider.notifier)
          .report(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: reason,
            note: _note.text,
          );
      if (mounted) Navigator.pop(context);
      showLoopSnackBar(t('Prijava poslana. Admin će je pregledati.'));
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.targetType == 'device'
                  ? t('Prijavi oglas')
                  : t('Prijavi korisnika'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            Text(
              widget.targetLabel,
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            const SizedBox(height: 12),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (r) => setState(() => _reason = r),
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(
                      value: r,
                      title: Text(r.label),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            TextField(
              controller: _note,
              maxLength: Report.maxNote,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: t('Opis (neobavezno)')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _reason == null || _busy ? null : _send,
              icon: const Icon(Icons.flag_outlined),
              label: Text(t('Pošalji prijavu')),
            ),
          ],
        ),
      ),
    );
  }
}
