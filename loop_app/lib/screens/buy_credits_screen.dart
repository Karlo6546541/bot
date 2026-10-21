import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/credit_shop.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';
import '../l10n/tr.dart';

/// Kupnja LOOP kredita: paketi s bonusom ili vlastiti iznos, odabir načina
/// plaćanja i (simulirana) obrada. Demo ništa ne naplaćuje i ne traži
/// podatke kartice.
class BuyCreditsScreen extends ConsumerStatefulWidget {
  const BuyCreditsScreen({super.key, this.needed});

  /// Koliko kredita nedostaje (npr. za kupnju) — predlaže odgovarajući paket.
  final double? needed;

  /// Otvara ekran; vraća `true` ako je kupnja uspjela.
  static Future<bool> open(BuildContext context, {double? needed}) async {
    if (blockGuest(context)) return false;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BuyCreditsScreen(needed: needed)),
    );
    return ok ?? false;
  }

  @override
  ConsumerState<BuyCreditsScreen> createState() => _BuyCreditsScreenState();
}

class _BuyCreditsScreenState extends ConsumerState<BuyCreditsScreen> {
  /// Odabrani iznos (bez bonusa).
  late int _credits;
  bool _custom = false;
  final _customCtrl = TextEditingController();
  PaymentMethod _method = PaymentMethod.card;
  String? _error;

  @override
  void initState() {
    super.initState();
    final need = widget.needed;
    if (need != null && need > 0) {
      // Najmanji paket koji pokriva manjak, inače vlastiti iznos.
      final fit = CreditShop.packages.where((p) => p.total >= need);
      if (fit.isNotEmpty) {
        _credits = fit.first.credits;
      } else {
        _custom = true;
        _credits = need.ceil().clamp(
          CreditShop.minAmount,
          CreditShop.maxSingle,
        );
        _customCtrl.text = '$_credits';
      }
    } else {
      _credits = CreditShop.packages.firstWhere((p) => p.popular).credits;
    }
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  int get _bonus => CreditShop.bonusFor(_credits);

  Future<void> _pay() async {
    final user = ref.read(appProvider).currentUser;
    if (user == null) return;
    if (_credits < CreditShop.minAmount || _credits > CreditShop.maxSingle) {
      setState(
        () => _error = t('Iznos od {0} do {1}', [
          CreditShop.minAmount,
          CreditShop.maxSingle,
        ]),
      );
      return;
    }

    // Simulirana obrada plaćanja.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  t('Obrada plaćanja ({0})…', [_method.label]),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await ref.read(appProvider.notifier).buyCredits(_credits, _method);
      if (!mounted) return;
      Navigator.of(context).pop(); // obrada
      await showDialog<void>(
        context: context,
        builder: (_) => _SuccessDialog(credits: _credits + _bonus),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on TradeException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showLoopSnackBar(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final user = s.currentUser;
    final left = user == null
        ? 0.0
        : ref.read(creditShopProvider).remainingToday(user.id);

    return Scaffold(
      appBar: AppBar(title: Text(t('Uplati novac'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              _Header(credits: user?.credits ?? 0, needed: widget.needed),
              const SizedBox(height: 20),
              _sectionTitle(t('Odaberi paket')),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in CreditShop.packages)
                    _PackageTile(
                      package: p,
                      selected: !_custom && _credits == p.credits,
                      onTap: () => setState(() {
                        _custom = false;
                        _credits = p.credits;
                        _error = null;
                      }),
                    ),
                  _CustomTile(
                    selected: _custom,
                    onTap: () => setState(() {
                      _custom = true;
                      _credits = int.tryParse(_customCtrl.text) ?? 0;
                    }),
                  ),
                ],
              ),
              if (_custom) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _customCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: t('Vlastiti iznos'),
                    suffixText: t('€'),
                    helperText: t('Od {0} do {1} €', [
                      CreditShop.minAmount,
                      CreditShop.maxSingle,
                    ]),
                    errorText: _error,
                  ),
                  onChanged: (v) => setState(() {
                    _credits = int.tryParse(v) ?? 0;
                    _error = null;
                  }),
                ),
              ],
              const SizedBox(height: 22),
              _sectionTitle(t('Način plaćanja')),
              const SizedBox(height: 10),
              for (final m in PaymentMethod.values)
                _MethodTile(
                  method: m,
                  selected: _method == m,
                  onTap: () => setState(() => _method = m),
                ),
              const SizedBox(height: 18),
              _Summary(credits: _credits, bonus: _bonus),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _credits > 0 ? _pay : null,
                icon: const Icon(Icons.lock_outline),
                label: Text(t('Plati {0}', [formatEuro(_credits.toDouble())])),
              ),
              const SizedBox(height: 14),
              Text(
                t(
                  'Demo verzija: ništa se stvarno ne naplaćuje i ne unose se podaci kartice. Dnevni limit uplata: {0} € (danas još {1}).',
                  [CreditShop.dailyLimit, formatCredits(left)],
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: LoopColors.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(
    t,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.credits, this.needed});
  final double credits;
  final double? needed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius * 1.4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [LoopColors.sunny, LoopColors.peach],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: LoopColors.surface,
              shape: BoxShape.circle,
              boxShadow: LoopColors.softShadow,
            ),
            child: const Center(
              child: Text('🪙', style: TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Trenutno imaš'),
                  style: TextStyle(color: LoopColors.textSecondary),
                ),
                Text(
                  formatCredits(credits),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (needed != null && needed! > 0)
                  Text(
                    t('Nedostaje ti {0}', [formatCredits(needed!)]),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  final CreditPackage package;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 140,
        maxWidth: 140,
        minHeight: 140,
      ),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.10) : LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kRadius),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(
                color: selected ? accent : LoopColors.surfaceHover,
                width: selected ? 2 : 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 22,
                  child: package.popular
                      ? _Ribbon(text: t('Najpopularnije'), color: accent)
                      : package.bonus > 0
                      ? _Ribbon(
                          text: t('+{0} bonus', [package.bonus]),
                          color: LoopColors.success,
                        )
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  formatNumber(package.credits.toDouble()),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  package.bonus > 0
                      ? t('+ {0} bonus kredita', [package.bonus])
                      : t('€'),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatEuro(package.priceEur),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomTile extends StatelessWidget {
  const _CustomTile({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 140,
      height: 140,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.10) : LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(
                color: selected ? accent : LoopColors.surfaceHover,
                width: selected ? 2 : 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.edit_outlined, color: LoopColors.textSecondary),
                const SizedBox(height: 6),
                Text(
                  t('Vlastiti iznos'),
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: LoopColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (method) {
    PaymentMethod.card => Icons.credit_card,
    PaymentMethod.applePay => Icons.phone_iphone,
    PaymentMethod.googlePay => Icons.android,
    PaymentMethod.paypal => Icons.account_balance_wallet_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kRadius),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(
                color: selected ? accent : LoopColors.surfaceHover,
                width: selected ? 2 : 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: LoopColors.peach,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_icon, color: LoopColors.textPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        method.label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        method.subtitle,
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? accent : LoopColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.credits, required this.bonus});
  final int credits;
  final int bonus;

  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            row(t('Uplata'), formatCredits(credits.toDouble())),
            if (bonus > 0)
              row(t('Bonus'), '+ ${formatCredits(bonus.toDouble())}'),
            const Divider(height: 16),
            row(
              t('Dobivaš'),
              formatCredits((credits + bonus).toDouble()),
              bold: true,
            ),
            row(t('Plaćaš'), formatEuro(credits.toDouble()), bold: true),
          ],
        ),
      ),
    );
  }
}

/// Potvrda uspješne kupnje s animiranom kvačicom.
class _SuccessDialog extends StatelessWidget {
  const _SuccessDialog({required this.credits});
  final int credits;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.3, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: LoopColors.mint,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check, size: 44, color: LoopColors.success),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t('Plaćanje uspješno! 🎉'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            t('Na račun ti je dodano {0}.', [
              formatCredits(credits.toDouble()),
            ]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(minimumSize: const Size(120, 46)),
          child: Text(t('Super')),
        ),
      ],
    );
  }
}
