import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/seller_info.dart';
import '../providers/app_providers.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';
import 'legal_screen.dart';

/// Prije objave u Marketu ili na aukciji: ako podaci prodavatelja nedostaju,
/// objasni zašto ih tražimo i otvori obrazac. Vraća `true` ako ih ima.
Future<bool> ensureSellerInfo(BuildContext context) async {
  final user = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appProvider).currentUser;
  if (user == null || user.isGuest) return false;
  if (user.seller != null) return true;
  final go = await confirmDialog(
    context,
    title: t('Podaci prodavatelja'),
    message: t(
      'Prije prve objave zakon traži tvoje podatke: ime ili naziv, OIB, adresu i IBAN za isplatu (EU pravila DAC7 i DSA). Kupci vide samo je li prodavatelj privatna osoba ili trgovac.',
    ),
    confirmLabel: t('Ispuni podatke'),
  );
  if (!go || !context.mounted) return false;
  return SellerInfoScreen.open(context);
}

/// Isplata zarade na IBAN (uz potvrdu).
Future<void> showPayoutDialog(BuildContext context, WidgetRef ref) async {
  if (!await ensureSellerInfo(context) || !context.mounted) return;
  final user = ref.read(appProvider).currentUser!;
  if (user.credits <= 0) {
    showLoopSnackBar(t('Nemaš zarade za isplatu.'), error: true);
    return;
  }
  final ok = await confirmDialog(
    context,
    title: t('Isplatiti zaradu?'),
    message: t(
      '{0} ide na račun {1}. Isplatu obrađuje pružatelj plaćanja (obično 1–2 radna dana).',
      [formatCredits(user.credits), user.seller!.maskedIban],
    ),
    confirmLabel: t('Isplati'),
  );
  if (!ok || !context.mounted) return;
  await runWithLoading(
    context,
    () => ref.read(appProvider.notifier).payout(),
    successMessage: t('Isplata je poslana na tvoj račun.'),
  );
}

/// Obrazac: vrsta prodavatelja, ime/naziv, OIB, datum rođenja, adresa, IBAN.
class SellerInfoScreen extends ConsumerStatefulWidget {
  const SellerInfoScreen({super.key});

  static Future<bool> open(BuildContext context) async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const SellerInfoScreen()));
    return saved ?? false;
  }

  @override
  ConsumerState<SellerInfoScreen> createState() => _SellerInfoScreenState();
}

class _SellerInfoScreenState extends ConsumerState<SellerInfoScreen> {
  late final SellerInfo? _old = ref.read(appProvider).currentUser?.seller;
  late SellerType _type = _old?.type ?? SellerType.private;
  late final _name = TextEditingController(text: _old?.legalName ?? '');
  late final _oib = TextEditingController(text: _old?.oib ?? '');
  late final _address = TextEditingController(text: _old?.address ?? '');
  late final _iban = TextEditingController(text: _old?.iban ?? '');
  late final _registry = TextEditingController(text: _old?.registry ?? '');
  late DateTime? _birth = _old?.birthDate;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _oib, _address, _iban, _registry]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _birth = picked);
  }

  Future<void> _save() async {
    final info = SellerInfo(
      type: _type,
      legalName: _name.text.trim(),
      oib: _oib.text.trim(),
      birthDate: _type == SellerType.private ? _birth : null,
      address: _address.text.trim(),
      iban: _iban.text.replaceAll(' ', '').toUpperCase(),
      registry: _type == SellerType.trader ? _registry.text.trim() : '',
      updatedAt: DateTime.now(),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(appProvider.notifier).saveSellerInfo(info);
      if (!mounted) return;
      showLoopSnackBar(t('Podaci prodavatelja su spremljeni.'));
      Navigator.pop(context, true);
    } on TradeException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trader = _type == SellerType.trader;
    return Scaffold(
      appBar: AppBar(title: Text(t('Podaci prodavatelja'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                t(
                  'Platforma ih mora prikupiti prije prve objave (DAC7: izvještaj Poreznoj upravi za prodavatelje s 30+ prodaja ili više od 2.000 € godišnje; DSA: provjera trgovaca). Javno se prikazuje samo vrsta prodavatelja, a kod trgovca i podaci o trgovcu.',
                ),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              SegmentedButton<SellerType>(
                key: const ValueKey('seller-type'),
                segments: [
                  ButtonSegment(
                    value: SellerType.private,
                    label: Text(t('Privatna osoba')),
                    icon: const Icon(Icons.person_outline),
                  ),
                  ButtonSegment(
                    value: SellerType.trader,
                    label: Text(t('Trgovac')),
                    icon: const Icon(Icons.storefront_outlined),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(height: 6),
              Text(
                trader
                    ? t(
                        'Obrt ili tvrtka: kupci imaju pravo na povrat u 14 dana i jamstvo.',
                      )
                    : t(
                        'Prodaješ svoje stvari povremeno: kupci nemaju zakonsko pravo na povrat od 14 dana.',
                      ),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('seller-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: trader
                      ? t('Naziv obrta ili tvrtke')
                      : t('Ime i prezime'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('seller-oib'),
                controller: _oib,
                keyboardType: TextInputType.number,
                maxLength: 11,
                decoration: InputDecoration(labelText: t('OIB')),
              ),
              if (trader)
                TextField(
                  key: const ValueKey('seller-registry'),
                  controller: _registry,
                  decoration: InputDecoration(
                    labelText: t('Registar i broj (neobavezno)'),
                    hintText: t('npr. Obrtni registar, MBS'),
                  ),
                )
              else
                ListTile(
                  key: const ValueKey('seller-birth'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cake_outlined),
                  title: Text(t('Datum rođenja')),
                  subtitle: Text(
                    _birth == null ? t('Odaberi') : formatDate(_birth!),
                  ),
                  onTap: _pickBirth,
                ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('seller-address'),
                controller: _address,
                decoration: InputDecoration(
                  labelText: trader ? t('Sjedište') : t('Adresa prebivališta'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('seller-iban'),
                controller: _iban,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: t('IBAN za isplatu'),
                  hintText: 'HR12 3456 7890 1234 5678 9',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: LoopColors.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('seller-save'),
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.lock_outline),
                label: Text(t('Spremi')),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => LegalScreen.open(context, LegalDoc.privacy),
                child: Text(t('Kako čuvamo podatke (Pravila privatnosti)')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Podaci o trgovcu za kupce (DSA, čl. 30–31): naziv, adresa, OIB,
/// registar i kontakt.
Future<void> showTraderInfo(BuildContext context, AppUser trader) {
  final s = trader.seller!;
  Widget row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(k, style: TextStyle(color: LoopColors.textSecondary)),
        ),
        Expanded(
          child: SelectableText(
            v,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('trader-info'),
      title: Text(t('Podaci o trgovcu')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row(t('Naziv'), s.legalName),
            row(t('Adresa'), s.address),
            row(t('OIB'), s.oib),
            if (s.registry.isNotEmpty) row(t('Registar'), s.registry),
            row(
              t('Kontakt'),
              trader.email.isEmpty ? trader.handle : trader.email,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t('Zatvori')),
        ),
      ],
    ),
  );
}
