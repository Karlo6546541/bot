import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../screens/buy_credits_screen.dart';
import '../services/delivery_service.dart';
import 'delivery_picker.dart';
import 'formatters.dart';
import 'loop_snackbar.dart';
import '../l10n/tr.dart';

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
    builder: (_) => PopScope(
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
    final msg = e is TradeException ? e.message : t('Greška: {0}', [e]);
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
    title: t('Prodaj odmah'),
    device: device,
    rows: [
      _Row(t('Originalna cijena'), formatCredits(device.price)),
      _Row(
        t('Fee (5%)'),
        '− ${formatCredits(feeFor(device.price))}',
        color: LoopColors.error,
      ),
      _Row(
        t('Dobivaš'),
        formatCredits(sellPayout(device.price)),
        highlight: true,
      ),
    ],
    note: t(
      'Dobivaš LOOP kredite koje možeš potrošiti samo unutar aplikacije.',
    ),
    confirmLabel: t('Potvrdi prodaju'),
  );
  if (!ok || !context.mounted) return false;
  return runWithLoading(
    context,
    () => ref.read(appProvider.notifier).sell(device.id),
    successMessage: t('Uspješno prodano'),
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
      title: t('Nemaš dovoljno kredita'),
      message:
          t('Za "{0}" treba {1} (s feejem), a imaš {2}.\nNedostaje ti {3}.', [
            device.name,
            formatCredits(total),
            formatCredits(user.credits),
            formatCredits(missing),
          ]),
      confirmLabel: t('Kupi kredite'),
    );
    if (!topUp || !context.mounted) return false;
    final bought = await BuyCreditsScreen.open(context, needed: missing);
    if (!bought || !context.mounted) return false;
    // Nakon dopune nastavi s kupnjom.
    return confirmAndBuy(context, ref, device);
  }

  // Blagajna: dostava + pregled iznosa.
  final choice = await showModalBottomSheet<DeliveryChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: LoopColors.background,
    constraints: BoxConstraints(maxWidth: 560),
    builder: (_) => _CheckoutSheet(device: device, credits: user.credits),
  );
  if (choice == null || !context.mounted) return false;
  return runWithLoading(
    context,
    () => ref
        .read(appProvider.notifier)
        .buy(device.id, method: choice.method, destination: choice.destination),
    successMessage: t('Uspješno kupljeno — prati dostavu u "Moje dostave"'),
  );
}

/// Blagajna: odabir dostave i ukupan iznos (predmet + fee + dostava).
class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({required this.device, required this.credits});
  final Device device;
  final double credits;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  DeliveryChoice? _choice;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final shipping = _choice?.method.cost ?? 0;
    final total = buyTotal(d.price) + shipping;
    final enough = widget.credits >= total;

    Widget row(String k, String v, {bool bold = false}) => Padding(
      padding: EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                color: bold ? LoopColors.textPrimary : LoopColors.textSecondary,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            v,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              fontSize: bold ? 17 : 14,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              d.name,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            Text(
              '${d.model} · ${d.condition.label}',
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            SizedBox(height: 16),
            Text(
              t('Dostava'),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            SizedBox(height: 8),
            Consumer(
              builder: (context, ref, _) => DeliveryPicker(
                methods: DeliveryService.methodsFor(d),
                savedAddress: ref.read(appProvider).currentUser?.address,
                onChanged: (c) => setState(() {
                  _choice = c;
                  _error = null;
                }),
              ),
            ),
            SizedBox(height: 12),
            Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Column(
                  children: [
                    row(t('Cijena'), formatCredits(d.price)),
                    row(t('Fee (5%)'), '+ ${formatCredits(feeFor(d.price))}'),
                    row(
                      t('Dostava'),
                      shipping == 0
                          ? t('besplatno')
                          : '+ ${formatCredits(shipping)}',
                    ),
                    Divider(height: 16),
                    row(t('Ukupno'), formatCredits(total), bold: true),
                    row(
                      t('Krediti nakon kupnje'),
                      formatCredits(widget.credits - total),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: LoopColors.error)),
            ],
            SizedBox(height: 14),
            if (enough)
              FilledButton.icon(
                onPressed: _choice == null
                    ? null
                    : () {
                        final err = DeliveryService.validate(
                          _choice!.method,
                          _choice!.destination,
                        );
                        if (err != null) {
                          setState(() => _error = err);
                          return;
                        }
                        Navigator.pop(context, _choice);
                      },
                icon: Icon(Icons.lock_outline),
                label: Text(t('Potvrdi kupnju')),
              )
            else
              FilledButton.icon(
                onPressed: () async {
                  final ok = await BuyCreditsScreen.open(
                    context,
                    needed: total - widget.credits,
                  );
                  if (ok && context.mounted) Navigator.pop(context);
                },
                icon: Icon(Icons.add_card),
                label: Text(
                  t('Nedostaje {0} — kupi kredite', [
                    formatCredits(total - widget.credits),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Srce na uređaju: dodaje/uklanja iz favorita uz kratku poruku.
Future<void> toggleFavorite(WidgetRef ref, Device device) async {
  final added = await ref.read(appProvider.notifier).toggleFavorite(device.id);
  showLoopSnackBar(
    added
        ? t('{0} dodan u favorite', [device.name])
        : t('{0} uklonjen iz favorita', [device.name]),
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
        constraints: BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.name,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              '${device.model} · ${device.condition.label}',
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            SizedBox(height: 16),
            for (final r in rows)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
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
              SizedBox(height: 12),
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
          child: Text(t('Odustani')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(minimumSize: Size(0, 44)),
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
  String? confirmLabel,
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
          child: Text(t('Odustani')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: destructive ? LoopColors.error : null,
            foregroundColor: destructive ? Colors.white : null,
          ),
          child: Text(confirmLabel ?? t('Potvrdi')),
        ),
      ],
    ),
  );
  return result ?? false;
}
