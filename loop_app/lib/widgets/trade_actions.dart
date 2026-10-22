import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../screens/seller_screens.dart';
import '../screens/wishlists_screen.dart';
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

/// Gost samo razgledava: umjesto akcije nudi izradu računa.
/// Vraća `true` ako je akcija blokirana.
bool blockGuest(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  final user = container.read(appProvider).currentUser;
  if (user == null || !user.isGuest) return false;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.person_add_alt_1, size: 36),
      title: Text(t('Napravi besplatan račun')),
      content: Text(
        t(
          'Gost može samo razgledavati. Napravi besplatan račun za kupnju i prodaju.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t('Nastavi razgledavati')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            container.read(appProvider.notifier).logout();
          },
          child: Text(t('Napravi račun')),
        ),
      ],
    ),
  );
  return true;
}

/// Kupnja: blagajna (dostava, iznos, plaćanje karticom), pa kupnja.
Future<bool> confirmAndBuy(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  if (blockGuest(context)) return false;
  final user = ref.read(appProvider).currentUser;
  if (user == null) return false;
  // Dogovorena cijena (prihvaćena ponuda) ili cijena oglasa s popustom.
  final price = ref.read(appProvider).priceForMe(device);
  // Već kupljen digitalni proizvod — samo preuzmi.
  if (device.isDigital && ref.read(appProvider).hasPurchased(device.id)) {
    await downloadDigital(context, ref, device);
    return false;
  }

  if (device.isDigital) return _buyDigital(context, ref, device, price);

  // Blagajna: dostava + pregled iznosa.
  final choice = await showModalBottomSheet<DeliveryChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: LoopColors.background,
    constraints: BoxConstraints(maxWidth: 560),
    builder: (_) => _CheckoutSheet(
      device: device,
      price: price,
      sellerIsTrader:
          ref.read(appProvider).userById(device.ownerId)?.isTrader ?? false,
    ),
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
  const _CheckoutSheet({
    required this.device,
    required this.price,
    required this.sellerIsTrader,
  });
  final Device device;
  final double price;
  final bool sellerIsTrader;

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
    final price = widget.price;
    final total = buyTotal(price) + shipping;

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
                    if (price < d.basePrice)
                      row(t('Redovna cijena'), formatCredits(d.shownBasePrice)),
                    row(t('Cijena'), formatCredits(buyTotal(price))),
                    row(
                      t('Dostava'),
                      shipping == 0
                          ? t('besplatno')
                          : '+ ${formatCredits(shipping)}',
                    ),
                    Divider(height: 16),
                    row(t('Ukupno'), formatCredits(total), bold: true),
                  ],
                ),
              ),
            ),
            SizedBox(height: 10),
            // Plaćanje: licencirani pružatelj (u demo verziji simulirano).
            Container(
              key: ValueKey('checkout-payment'),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LoopColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: LoopColors.surfaceHover),
              ),
              child: Row(
                children: [
                  Icon(Icons.credit_card, color: LoopColors.textSecondary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('Kartica •••• 4242 (demo)'),
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          t(
                            'Plaćanje obrađuje pružatelj plaćanja; LOOP ne drži tvoj novac.',
                          ),
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
            // Prava potrošača ovise o vrsti prodavatelja.
            Text(
              widget.sellerIsTrader
                  ? t(
                      'Prodavatelj je trgovac: imaš pravo na povrat u 14 dana od primitka.',
                    )
                  : t(
                      'Prodavatelj je privatna osoba: zakonsko pravo na povrat od 14 dana ne vrijedi.',
                    ),
              key: ValueKey('checkout-rights'),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
            if (_error != null) ...[
              SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: LoopColors.error)),
            ],
            SizedBox(height: 14),
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
              label: Text(
                t('Plati {0} i potvrdi kupnju', [formatCredits(total)]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Srce na uređaju: dodaje/uklanja iz favorita uz kratku poruku.
/// "Sviđa mi se" (srce). Nakon lajka obavijest nudi spremanje u listu
/// želja — jedan gumb umjesto zasebnih "♥" i "Spremi".
Future<void> toggleFavorite(
  WidgetRef ref,
  Device device, {
  BuildContext? context,
}) async {
  final bool added;
  try {
    added = await ref.read(appProvider.notifier).toggleFavorite(device.id);
  } on TradeException catch (e) {
    showLoopSnackBar(e.message, error: true);
    return;
  }
  final ctx = context;
  showLoopSnackBar(
    added
        ? t('Sviđa ti se: {0}', [device.name])
        : t('{0} uklonjen iz favorita', [device.name]),
    actionLabel: added && ctx != null ? t('Spremi u listu') : null,
    onAction: added && ctx != null && ctx.mounted
        ? () => showSaveToListSheet(ctx, ref, device)
        : null,
  );
}

class _Row {
  const _Row(this.label, this.value, {this.highlight = false});
  final String label;
  final String value;
  final bool highlight;
}

Future<bool> _showTradeDialog(
  BuildContext context, {
  required String title,
  required Device device,
  required List<_Row> rows,
  required String confirmLabel,
  String? note,
  String? consent,
}) async {
  var agreed = consent == null;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
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
                device.isDigital
                    ? device.model
                    : '${device.model} · ${device.condition.label}',
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
                          color: r.highlight
                              ? LoopColors.accent
                              : LoopColors.textPrimary,
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
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              // Digitalni sadržaj: izričit pristanak na gubitak prava na povrat.
              if (consent != null)
                CheckboxListTile(
                  key: ValueKey('digital-consent'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: agreed,
                  onChanged: (v) => setState(() => agreed = v ?? false),
                  title: Text(consent, style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Odustani')),
          ),
          FilledButton(
            onPressed: agreed ? () => Navigator.pop(context, true) : null,
            style: FilledButton.styleFrom(minimumSize: Size(0, 44)),
            child: Text(confirmLabel),
          ),
        ],
      ),
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

/// Objava vlastitog predmeta u Marketu: korisnik upisuje cijenu (i
/// količinu na zalihi) i vidi koliko dobiva nakon prodaje (puna cijena).
Future<bool> showListDialog(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  if (blockGuest(context)) return false;
  if (!await ensureSellerInfo(context) || !context.mounted) return false;
  final result = await showDialog<(double, int?)>(
    context: context,
    // Pri vrhu i bez pomaka za tipkovnicu (mobilni preglednik).
    builder: (ctx) => MediaQuery.removeViewInsets(
      context: ctx,
      removeBottom: true,
      child: _ListDialog(device: device),
    ),
  );
  if (result == null || !context.mounted) return false;
  final (price, quantity) = result;
  return runWithLoading(
    context,
    () => ref
        .read(appProvider.notifier)
        .listOnMarket(device.id, price, quantity: quantity),
    successMessage: t('Objavljeno u Marketu 🏷️'),
  );
}

class _ListDialog extends StatefulWidget {
  const _ListDialog({required this.device});
  final Device device;

  @override
  State<_ListDialog> createState() => _ListDialogState();
}

class _ListDialogState extends State<_ListDialog> {
  late final _price = TextEditingController(
    text: (widget.device.listPrice ?? widget.device.price).toStringAsFixed(0),
  );
  late final _qty = TextEditingController(text: '${widget.device.quantity}');
  String? _error;
  String? _qtyError;

  @override
  void dispose() {
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  double? get _value =>
      double.tryParse(_price.text.trim().replaceAll(',', '.'));

  void _submit() {
    final v = _value;
    if (v == null || v <= 0 || v > TradeService.maxListPrice) {
      setState(() => _error = t('Unesi ispravnu cijenu'));
      return;
    }
    int? q;
    if (!widget.device.isDigital) {
      q = int.tryParse(_qty.text.trim());
      if (q == null || q < 1 || q > Device.maxQuantity) {
        setState(() => _qtyError = t('Od 1 do {0}', ['${Device.maxQuantity}']));
        return;
      }
    }
    Navigator.pop(context, (v, q));
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    return AlertDialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      scrollable: true,
      title: Text(
        widget.device.isListed ? t('Promijeni cijenu') : t('Objavi u Marketu'),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t(
                'Predmet ostaje tvoj dok ga netko ne kupi. Možeš ga ukloniti iz Marketa kad god želiš.',
              ),
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _price,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: t('Cijena'),
                suffixText: t('€'),
                errorText: _error,
              ),
            ),
            if (!widget.device.isDigital) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('list-quantity'),
                controller: _qty,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _qtyError = null),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: t('Količina na zalihi'),
                  suffixText: t('kom'),
                  helperText: t('Svaka kupnja skida jedan komad.'),
                  errorText: _qtyError,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (v != null && v > 0) ...[
              Text(
                t('Kupci vide cijenu {0}', [formatCredits(buyTotal(v))]),
                style: TextStyle(color: LoopColors.textSecondary),
              ),
              Text(
                t('Ti dobivaš {0}', [formatCredits(sellPayout(v))]),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Odustani')),
        ),
        FilledButton(onPressed: _submit, child: Text(t('Objavi'))),
      ],
    );
  }
}

/// Kupnja digitalnog proizvoda: bez dostave, preuzimanje odmah.
Future<bool> _buyDigital(
  BuildContext context,
  WidgetRef ref,
  Device device,
  double price,
) async {
  final ok = await _showTradeDialog(
    context,
    title: t('Kupi i preuzmi'),
    device: device,
    rows: [_Row(t('Cijena'), formatCredits(buyTotal(price)), highlight: true)],
    note: t(
      'Digitalni proizvod: datoteka {0} ({1}) preuzima se odmah nakon plaćanja i ostaje ti u "Moje digitalne kupnje".',
      [device.file?.name ?? '', device.file?.sizeLabel ?? ''],
    ),
    confirmLabel: t('Plati i preuzmi'),
    consent: t(
      'Pristajem da preuzimanje počne odmah i znam da time gubim pravo na povrat od 14 dana.',
    ),
  );
  if (!ok || !context.mounted) return false;
  final bought = await runWithLoading(
    context,
    () => ref.read(appProvider.notifier).buy(device.id),
    successMessage: t('Kupljeno! Datoteka se preuzima…'),
  );
  if (bought && context.mounted) {
    await downloadDigital(context, ref, device);
  }
  return bought;
}

/// Preuzima datoteku digitalnog proizvoda (kupac ili vlasnik).
Future<void> downloadDigital(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  try {
    final where = await ref.read(appProvider.notifier).downloadFile(device.id);
    showLoopSnackBar(t('Preuzeto: {0}', [where]));
  } on TradeException catch (e) {
    showLoopSnackBar(e.message, error: true);
  } catch (e) {
    showLoopSnackBar(t('Preuzimanje nije uspjelo: {0}', [e]), error: true);
  }
}
