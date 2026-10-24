import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../screens/seller_screens.dart';
import '../services/delivery_service.dart';
import '../screens/login_screen.dart';
import 'celebration.dart';
import 'delivery_picker.dart';
import 'payment_sheet.dart';
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
  required String? successMessage,
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
    if (successMessage != null) showLoopSnackBar(successMessage);
    return true;
  } catch (e) {
    navigator.pop();
    final msg = e is TradeException ? e.message : t('Greška: {0}', [e]);
    showLoopSnackBar(msg, error: true);
    return false;
  }
}

/// Prava kupca ovise o vrsti prodavatelja: od trgovca (obrt, tvrtka)
/// kupac ima pravo na povrat u 14 dana i zakonsko jamstvo, od privatne
/// osobe nema.
String buyerRightsText(AppUser? seller) {
  final info = seller?.seller;
  if (info != null && info.isBusiness) {
    return t(
      'Prodavatelj je trgovac ({0}): imaš pravo na povrat u 14 dana od primitka i zakonsko jamstvo.',
      [info.tradeName],
    );
  }
  return t(
    'Prodavatelj je privatna osoba: zakonsko pravo na povrat od 14 dana ne vrijedi.',
  );
}

/// Gost samo razgledava: kupnja, prodaja, licitiranje i ostale radnje
/// otvaraju prijavu/registraciju preko trenutnog ekrana — nakon prijave
/// korisnik ostaje gdje je bio. Vraća `true` ako je akcija blokirana.
bool blockGuest(BuildContext context, {String? reason}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final user = container.read(appProvider).currentUser;
  if (user == null || !user.isGuest) return false;
  LoginScreen.open(context, reason: reason);
  return true;
}

/// Kao na Whatnotu: prije prve ponude traže se kartica i adresa za
/// dostavu — pobjedniku se naplaćuje automatski, a paket kreće sam. U demo
/// verziji kartica je testna (ne unose se pravi podaci). Vraća `true` kad
/// je sve spremno.
///
/// [force]: prikaži i kad je sve spremno (Novčanik — promjena adrese).
Future<bool> ensureCheckout(
  BuildContext context,
  WidgetRef ref, {
  bool force = false,
}) async {
  final user = ref.read(appProvider).currentUser;
  if (user == null || user.isGuest) return false;
  if (user.checkoutReady && !force) return true;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: LoopColors.background,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _CheckoutSetupSheet(
      address: user.address ?? '',
      card: user.paymentCard,
    ),
  );
  return ok == true;
}

class _CheckoutSetupSheet extends ConsumerStatefulWidget {
  const _CheckoutSetupSheet({required this.address, this.card});
  final String address;

  /// Spremljeni način plaćanja (oznaka) ili null.
  final String? card;

  @override
  ConsumerState<_CheckoutSetupSheet> createState() =>
      _CheckoutSetupSheetState();
}

class _CheckoutSetupSheetState extends ConsumerState<_CheckoutSetupSheet> {
  late final _address = TextEditingController(text: widget.address);
  late String? _card = widget.card;
  bool _busy = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(appProvider.notifier)
          .saveCheckout(address: _address.text, card: _card);
      if (mounted) Navigator.pop(context, true);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Spremni za licitiranje?'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            t(
              'Kad pobijediš, naplata ide automatski s kartice, a paket kreće na tvoju adresu. Sve što osvojiš u istom liveu stiže u jednom paketu.',
            ),
            style: TextStyle(color: LoopColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Material(
            color: _card != null ? LoopColors.mint : LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            child: ListTile(
              key: const ValueKey('checkout-card'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kRadius),
              ),
              leading: const Icon(Icons.credit_card),
              title: Text(
                _card ?? t('Dodaj karticu, Google Pay ili Apple Pay'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                _card == null
                    ? t('Testni način — koristi testnu karticu 4242.')
                    : t('Dodirni za promjenu'),
              ),
              trailing: Icon(
                _card != null ? Icons.check_circle : Icons.add_circle_outline,
                color: _card != null ? LoopColors.success : null,
              ),
              onTap: () async {
                final card = await addPaymentMethod(context);
                if (card != null && mounted) setState(() => _card = card);
              },
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('checkout-address'),
            controller: _address,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: t('Adresa za dostavu'),
              hintText: t('Ulica i broj, poštanski broj i mjesto'),
              prefixIcon: const Icon(Icons.home_outlined),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            t(
              'Ponude su obvezujuće. Za demo upiši izmišljenu adresu — testna baza je otvorena.',
            ),
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('checkout-save'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _card == null || _busy ? null : _save,
            child: Text(t('Spremi i nastavi')),
          ),
        ],
      ),
    ),
  );
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

  if (device.isDigital) {
    // Digitalno: treba samo način plaćanja (bez adrese).
    if (user.paymentCard == null) {
      final card = await addPaymentMethod(context);
      if (card == null || !context.mounted) return false;
      await ref.read(appProvider.notifier).savePaymentMethod(card);
      if (!context.mounted) return false;
    }
    return _buyDigital(context, ref, device, price);
  }

  // Prvo se bira način dostave (ništa nije unaprijed odabrano), a
  // spremljena kartica i adresa koriste se automatski.
  final picked = await showModalBottomSheet<DeliveryChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: LoopColors.background,
    constraints: BoxConstraints(maxWidth: 560),
    builder: (_) => _CheckoutSheet(device: device, price: price),
  );
  if (picked == null || !context.mounted) return false;
  // Gumb kupnje nestaje čim predmet ode (npr. objava u swipe feedu), pa
  // slavlje ide preko navigatora, ne preko gumba.
  final nav = Navigator.of(context, rootNavigator: true).context;
  final ok = await runWithLoading(
    context,
    () => ref
        .read(appProvider.notifier)
        .buy(device.id, method: picked.method, destination: picked.destination),
    successMessage: null,
  );
  if (ok && nav.mounted) {
    await showCelebration(
      nav,
      title: t('Kupljeno! 🎉'),
      subtitle: t('Paket pratiš u Moje → Kupljeno'),
      device: device,
      amount: buyTotal(price) + picked.method.cost,
    );
  }
  return ok;
}

/// Blagajna: odabir dostave i ukupan iznos (predmet + fee + dostava).
class _CheckoutSheet extends ConsumerStatefulWidget {
  const _CheckoutSheet({required this.device, required this.price});
  final Device device;
  final double price;

  @override
  ConsumerState<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<_CheckoutSheet> {
  /// Dodaje ili mijenja način plaćanja (sprema se korisniku).
  Future<void> _changeCard() async {
    final card = await addPaymentMethod(context);
    if (card == null || !mounted) return;
    await ref.read(appProvider.notifier).savePaymentMethod(card);
    setState(() => _error = null);
  }

  DeliveryChoice? _choice;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(
      appProvider.select((s) => s.currentUser?.paymentCard),
    );
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
                          card ?? t('Način plaćanja nije dodan'),
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
                  TextButton(
                    key: ValueKey('checkout-pay-change'),
                    onPressed: _changeCard,
                    child: Text(card == null ? t('Dodaj') : t('Promijeni')),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
            // Prava potrošača ovise o vrsti prodavatelja.
            Text(
              buyerRightsText(
                ref.read(appProvider).userById(widget.device.ownerId),
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
              key: ValueKey('checkout-pay'),
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
                      if (card == null) {
                        _changeCard();
                        return;
                      }
                      Navigator.pop(context, _choice);
                    },
              icon: Icon(Icons.lock_outline),
              label: Text(
                _choice == null
                    ? t('Prvo odaberi način dostave')
                    : t('Plati {0} i potvrdi kupnju', [formatCredits(total)]),
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
  if (context != null && blockGuest(context)) return;
  final bool added;
  try {
    added = await ref.read(appProvider.notifier).toggleFavorite(device.id);
  } on TradeException catch (e) {
    showLoopSnackBar(e.message, error: true);
    return;
  }
  // Jedno srce = spremljeno (bez lista želja).
  showLoopSnackBar(
    added
        ? t('Sviđa ti se: {0}', [device.name])
        : t('{0} uklonjen iz favorita', [device.name]),
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
    successMessage: t('Na prodaji je 🏷️'),
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
        widget.device.isListed
            ? t('Promijeni cijenu')
            : t('Objavi za Kupi odmah'),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t(
                'Predmet ostaje tvoj dok ga netko ne kupi. Možeš ga maknuti iz prodaje kad god želiš.',
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
