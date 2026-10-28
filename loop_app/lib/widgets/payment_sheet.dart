import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/tr.dart';
import '../services/payments.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';

/// Dodavanje načina plaćanja: Apple Pay, Google Pay ili kartica (testni
/// način). Vraća oznaku za spremanje ("Visa •••• 4242") ili null.
Future<String?> addPaymentMethod(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: LoopColors.background,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => appThemed(const _PaymentSheet()),
    );

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet();

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _number = TextEditingController();
  final _expiry = TextEditingController();
  final _cvc = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    _expiry.dispose();
    _cvc.dispose();
    super.dispose();
  }

  CardBrand get _brand => CardBrand.of(_number.text);

  void _fill(String number) {
    final next = DateTime.now().year % 100 + 3;
    setState(() {
      _number.text = number;
      _expiry.text = '12/$next';
      _cvc.text = CardBrand.of(number) == CardBrand.amex ? '1234' : '123';
      _error = null;
    });
  }

  Future<void> _saveCard() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    // Kratka "provjera kod banke" kao u pravoj blagajni.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    try {
      final label = TestPayments.tokenize(
        _number.text,
        _expiry.text,
        _cvc.text,
      );
      Navigator.pop(context, label);
    } on TradeException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _wallet(WalletKind kind) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => appThemed(_WalletSheet(kind: kind)),
    );
    if (ok == true && mounted) {
      Navigator.pop(context, TestPayments.wallet(kind));
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = _brand;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('Način plaćanja'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: LoopColors.sunny,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    t('TESTNI NAČIN'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'Spremljeni način plaćanja koristi se automatski: kad pobijediš na aukciji ili u liveu, naplata ide sama.',
              ),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            _WalletButton(
              key: const ValueKey('pay-apple'),
              kind: WalletKind.applePay,
              onTap: () => _wallet(WalletKind.applePay),
            ),
            const SizedBox(height: 8),
            _WalletButton(
              key: const ValueKey('pay-google'),
              kind: WalletKind.googlePay,
              onTap: () => _wallet(WalletKind.googlePay),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    t('ili karticom'),
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('pay-number'),
              controller: _number,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.creditCardNumber],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(19),
                _CardNumberFormatter(),
              ],
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: t('Broj kartice'),
                hintText: '1234 5678 9012 3456',
                prefixIcon: const Icon(Icons.credit_card),
                suffixIcon: _number.text.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.all(10),
                        child: _BrandBadge(brand),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('pay-expiry'),
                    controller: _expiry,
                    keyboardType: TextInputType.number,
                    autofillHints: const [
                      AutofillHints.creditCardExpirationDate,
                    ],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                      _ExpiryFormatter(),
                    ],
                    decoration: InputDecoration(
                      labelText: t('Vrijedi do'),
                      hintText: t('MM/GG'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('pay-cvc'),
                    controller: _cvc,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    autofillHints: const [AutofillHints.creditCardSecurityCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: InputDecoration(
                      labelText: 'CVC',
                      hintText: brand == CardBrand.amex ? '1234' : '123',
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('pay-error'),
                style: TextStyle(
                  color: LoopColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Testne kartice (kao u Stripeovom testnom načinu).
            Text(
              t('Testne kartice:'),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  key: const ValueKey('pay-test-fill'),
                  label: Text(t('✓ Visa 4242')),
                  onPressed: () => _fill(TestCards.success),
                ),
                ActionChip(
                  label: Text(t('✓ Mastercard 4444')),
                  onPressed: () => _fill(TestCards.mastercard),
                ),
                ActionChip(
                  key: const ValueKey('pay-test-declined'),
                  label: Text(t('✗ Odbijena 0002')),
                  onPressed: () => _fill(TestCards.declined),
                ),
                ActionChip(
                  label: Text(t('✗ Nema sredstava 9995')),
                  onPressed: () => _fill(TestCards.insufficient),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('pay-card-save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: _busy ? null : _saveCard,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_outline),
              label: Text(t('Spremi karticu')),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'Broj kartice i CVC ne spremamo — pružatelj plaćanja vraća samo token. U testnom načinu ništa se stvarno ne naplaćuje.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Crni gumb novčanika (izgled kao službeni Apple Pay / Google Pay).
class _WalletButton extends StatelessWidget {
  const _WalletButton({super.key, required this.kind, required this.onTap});
  final WalletKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (kind == WalletKind.applePay)
                const Icon(Icons.apple, color: Colors.white, size: 26)
              else
                const _GoogleG(),
              const SizedBox(width: 4),
              Text(
                kind == WalletKind.applePay ? 'Pay' : ' Pay',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Višebojno "G" (bez slike, za testni gumb).
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: (r) => const SweepGradient(
      colors: [
        Color(0xFF4285F4),
        Color(0xFF34A853),
        Color(0xFFFBBC05),
        Color(0xFFEA4335),
        Color(0xFF4285F4),
      ],
    ).createShader(r),
    child: const Text(
      'G',
      style: TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

/// Testni prozor novčanika (kao sistemski Apple Pay / Google Pay list).
class _WalletSheet extends StatefulWidget {
  const _WalletSheet({required this.kind});
  final WalletKind kind;

  @override
  State<_WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends State<_WalletSheet> {
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final apple = widget.kind == WalletKind.applePay;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        decoration: BoxDecoration(
          color: apple ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  widget.kind.label,
                  style: TextStyle(
                    color: apple ? Colors.white : Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  t('TEST'),
                  style: TextStyle(
                    color: apple ? Colors.white54 : Colors.black45,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: apple
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const _BrandBadge(CardBrand.visa),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      cardLabel(TestCards.success),
                      style: TextStyle(
                        color: apple ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.check_circle,
                    color: apple ? Colors.white : const Color(0xFF1A73E8),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              t('Subhasto sprema token kartice za automatsku naplatu.'),
              style: TextStyle(
                color: apple ? Colors.white60 : Colors.black54,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('wallet-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: apple ? Colors.white : const Color(0xFF1A73E8),
                foregroundColor: apple ? Colors.black : Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: _busy ? null : _confirm,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(apple ? Icons.face : Icons.fingerprint),
              label: Text(apple ? t('Potvrdi s Face ID') : t('Nastavi')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mala oznaka marke kartice.
class _BrandBadge extends StatelessWidget {
  const _BrandBadge(this.brand);
  final CardBrand brand;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (brand) {
      CardBrand.visa => ('VISA', const Color(0xFF1A1F71)),
      CardBrand.mastercard => ('MC', const Color(0xFFEB001B)),
      CardBrand.amex => ('AMEX', const Color(0xFF2E77BC)),
      CardBrand.maestro => ('MAESTRO', const Color(0xFF0099DF)),
      CardBrand.unknown => ('CARD', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

/// "4242424242424242" → "4242 4242 4242 4242" (Amex: 4-6-5).
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final d = digitsOnly(newValue.text);
    final groups = CardBrand.of(d) == CardBrand.amex
        ? const [4, 6, 5]
        : const [4, 4, 4, 4, 3];
    final parts = <String>[];
    var i = 0;
    for (final g in groups) {
      if (i >= d.length) break;
      final end = (i + g).clamp(0, d.length);
      parts.add(d.substring(i, end));
      i = end;
    }
    final text = parts.join(' ');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// "1229" → "12/29".
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final d = digitsOnly(newValue.text);
    final text = d.length <= 2 ? d : '${d.substring(0, 2)}/${d.substring(2)}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
