import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../screens/buy_credits_screen.dart';
import 'formatters.dart';
import 'loop_snackbar.dart';

export 'loop_snackbar.dart';

/// Kratka pauza da korisnik vidi indikator obrade (simulira mrežni poziv).
const _fakeLatency = Duration(milliseconds: 450);

/// Pokreće [action] uz modalni loading indikator i prikazuje SnackBar.
/// Vraća `true` ako je akcija uspjela.
Future<bool> runWithLoading(
  BuildContext context,
  Future<void> Function() action, {
  required String successMessage,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    await Future.wait([action(), Future<void>.delayed(_fakeLatency)]);
    navigator.pop();
    showLoopSnackBar(successMessage);
    return true;
  } catch (e) {
    navigator.pop();
    final msg = e is TradeException ? e.message : 'Greška: $e';
    showLoopSnackBar(msg, error: true);
    return false;
  }
}

/// INSTANT SELL — dijalog s cijenom, fee-om i iznosom, pa prodaja.
Future<bool> confirmAndSell(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  final ok = await _showTradeDialog(
    context,
    title: 'Prodaj odmah',
    device: device,
    rows: [
      _Row('Originalna cijena', formatCredits(device.price)),
      _Row(
        'Fee (5%)',
        '− ${formatCredits(feeFor(device.price))}',
        color: LoopColors.error,
      ),
      _Row('Dobivaš', formatCredits(sellPayout(device.price)), highlight: true),
    ],
    note: 'Dobivaš LOOP kredite koje možeš potrošiti samo unutar aplikacije.',
    confirmLabel: 'Potvrdi prodaju',
  );
  if (!ok || !context.mounted) return false;
  return runWithLoading(
    context,
    () => ref.read(appProvider.notifier).sell(device.id),
    successMessage: 'Uspješno prodano',
  );
}

/// INSTANT BUY — provjera kredita, dijalog s fee-om, pa kupnja.
Future<bool> confirmAndBuy(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  final user = ref.read(appProvider).currentUser;
  if (user == null) return false;
  final total = buyTotal(device.price);

  if (user.credits < total) {
    // Ponudi dopunu umjesto suhe greške.
    final missing = total - user.credits;
    final topUp = await confirmDialog(
      context,
      title: 'Nemaš dovoljno kredita',
      message:
          'Za "${device.name}" treba ${formatCredits(total)} (s feejem), '
          'a imaš ${formatCredits(user.credits)}.\n'
          'Nedostaje ti ${formatCredits(missing)}.',
      confirmLabel: 'Kupi kredite',
    );
    if (!topUp || !context.mounted) return false;
    final bought = await BuyCreditsScreen.open(context, needed: missing);
    if (!bought || !context.mounted) return false;
    // Nakon dopune nastavi s kupnjom.
    return confirmAndBuy(context, ref, device);
  }

  final ok = await _showTradeDialog(
    context,
    title: 'Kupi odmah',
    device: device,
    rows: [
      _Row('Cijena', formatCredits(device.price)),
      _Row(
        'Fee (5%)',
        '+ ${formatCredits(feeFor(device.price))}',
        color: LoopColors.error,
      ),
      _Row('Ukupno plaćaš', formatCredits(total), highlight: true),
      _Row('Krediti nakon kupnje', formatCredits(user.credits - total)),
    ],
    confirmLabel: 'Potvrdi kupnju',
  );
  if (!ok || !context.mounted) return false;
  return runWithLoading(
    context,
    () => ref.read(appProvider.notifier).buy(device.id),
    successMessage: 'Uspješno kupljeno',
  );
}

/// Srce na uređaju: dodaje/uklanja iz favorita uz kratku poruku.
Future<void> toggleFavorite(WidgetRef ref, Device device) async {
  final added = await ref.read(appProvider.notifier).toggleFavorite(device.id);
  showLoopSnackBar(
    added
        ? '${device.name} dodan u favorite'
        : '${device.name} uklonjen iz favorita',
  );
}

class _Row {
  const _Row(this.label, this.value, {this.highlight = false, this.color});
  final String label;
  final String value;
  final bool highlight;
  final Color? color;
}

Future<bool> _showTradeDialog(
  BuildContext context, {
  required String title,
  required Device device,
  required List<_Row> rows,
  required String confirmLabel,
  String? note,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              '${device.model} · ${device.condition.label}',
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            const SizedBox(height: 16),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.label,
                        style: TextStyle(
                          color: r.highlight
                              ? LoopColors.textPrimary
                              : LoopColors.textSecondary,
                          fontWeight: r.highlight
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      r.value,
                      style: TextStyle(
                        color:
                            r.color ??
                            (r.highlight
                                ? LoopColors.accent
                                : LoopColors.textPrimary),
                        fontWeight: r.highlight
                            ? FontWeight.w800
                            : FontWeight.w600,
                        fontSize: r.highlight ? 17 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            if (note != null) ...[
              const SizedBox(height: 12),
              Text(
                note,
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Generički dijalog za potvrdu (npr. brisanje u admin panelu, reset).
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Potvrdi',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: destructive ? LoopColors.error : null,
            foregroundColor: destructive ? Colors.white : null,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
