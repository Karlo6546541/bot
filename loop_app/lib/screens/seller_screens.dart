import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
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
      'Prije prve objave zakon traži tvoje podatke: ime ili naziv tvrtke, OIB, adresu i IBAN za isplatu (EU pravila DAC7 i DSA). Prodaješ kao privatna osoba ili kao obrt/tvrtka — kupci vide samo tu oznaku (a kod trgovca i podatke za kontakt).',
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

/// Obrazac: ime i prezime, OIB, datum rođenja, adresa, IBAN.
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
  late final TextEditingController _name;
  late final TextEditingController _oib;
  late final TextEditingController _address;
  late final TextEditingController _iban;
  late DateTime? _birth = _old?.birthDate;
  late SellerKind _kind = _old?.kind ?? SellerKind.private;
  late LegalForm _form = _old?.legalForm ?? LegalForm.obrt;
  late final TextEditingController _company;
  late final TextEditingController _vat;
  late final TextEditingController _registry;
  late final TextEditingController _email;
  late final TextEditingController _phone;

  @override
  void initState() {
    super.initState();
    // Odmah (ne lijeno): dispose ne smije čitati ref.
    final old = _old;
    _name = TextEditingController(text: old?.legalName ?? '');
    _oib = TextEditingController(text: old?.oib ?? '');
    _address = TextEditingController(text: old?.address ?? '');
    _iban = TextEditingController(text: old?.iban ?? '');
    _company = TextEditingController(text: old?.companyName ?? '');
    _vat = TextEditingController(text: old?.vatId ?? '');
    _registry = TextEditingController(text: old?.registryNumber ?? '');
    // Kontakt za kupce: zadano e-mail računa.
    final email = old?.contactEmail ?? '';
    _email = TextEditingController(
      text: email.isNotEmpty
          ? email
          : ref.read(appProvider).currentUser?.email ?? '',
    );
    _phone = TextEditingController(text: old?.contactPhone ?? '');
  }

  late bool _certified = _old?.isBusiness ?? false;

  bool get _business => _kind == SellerKind.business;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _oib,
      _address,
      _iban,
      _company,
      _vat,
      _registry,
      _email,
      _phone,
    ]) {
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
    if (_business && !_certified) {
      setState(
        () => _error = t(
          'Potvrdi da prodaješ u skladu s propisima (trgovac odgovara za proizvode i prava kupaca).',
        ),
      );
      return;
    }
    final info = SellerInfo(
      kind: _kind,
      legalName: _name.text.trim(),
      oib: _oib.text.trim(),
      birthDate: _business ? null : _birth,
      address: _address.text.trim(),
      iban: _iban.text.replaceAll(' ', '').toUpperCase(),
      updatedAt: DateTime.now(),
      companyName: _business ? _company.text.trim() : '',
      legalForm: _form,
      vatId: _business ? _vat.text.replaceAll(' ', '').toUpperCase() : '',
      registryNumber: _business ? _registry.text.trim() : '',
      contactEmail: _business ? _email.text.trim() : '',
      contactPhone: _business ? _phone.text.trim() : '',
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
    return Scaffold(
      appBar: AppBar(title: Text(t('Podaci prodavatelja'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // Kako prodaješ: kao privatna osoba ili kao obrt/tvrtka.
              SegmentedButton<SellerKind>(
                key: const ValueKey('seller-kind'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: SellerKind.private,
                    icon: const Icon(Icons.person_outline),
                    label: Text(t('Privatna osoba')),
                  ),
                  ButtonSegment(
                    value: SellerKind.business,
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(
                      t('Obrt / tvrtka'),
                      key: const ValueKey('seller-kind-business'),
                    ),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() {
                  _kind = v.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 10),
              Text(
                _business
                    ? t(
                        'Trgovac prodaje kao djelatnost — može prodavati više predmeta (veća ograničenja za aukcije i live). Kupci vide naziv tvrtke i imaju pravo na povrat u 14 dana. Platforma mora prikupiti ove podatke (DSA čl. 30, DAC7).',
                      )
                    : t(
                        'Privatna osoba prodaje svoje rabljene stvari. Platforma mora prikupiti ove podatke prije prve isplate (DAC7: izvještaj Poreznoj upravi za prodavatelje s 30+ prodaja ili više od 2.000 € godišnje). Kupci ih ne vide. Ako prodaješ redovito radi zarade, odaberi Obrt / tvrtka.',
                      ),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (_business) ...[
                TextField(
                  key: const ValueKey('seller-company'),
                  controller: _company,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: t('Naziv obrta ili tvrtke'),
                    hintText: t('npr. Retro Kutak j.d.o.o.'),
                    prefixIcon: const Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<LegalForm>(
                  key: const ValueKey('seller-form'),
                  initialValue: _form,
                  decoration: InputDecoration(labelText: t('Pravni oblik')),
                  items: [
                    for (final f in LegalForm.values)
                      DropdownMenuItem(value: f, child: Text(f.label)),
                  ],
                  onChanged: (v) => setState(() => _form = v!),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                key: const ValueKey('seller-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: _business
                      ? t('Odgovorna osoba (ime i prezime)')
                      : t('Ime i prezime'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('seller-oib'),
                controller: _oib,
                keyboardType: TextInputType.number,
                maxLength: 11,
                decoration: InputDecoration(
                  labelText: _business ? t('OIB obrta / tvrtke') : t('OIB'),
                ),
              ),
              if (_business) ...[
                TextField(
                  key: const ValueKey('seller-vat'),
                  controller: _vat,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: t('PDV broj (neobavezno)'),
                    hintText: 'HR12345678901',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('seller-registry'),
                  controller: _registry,
                  decoration: InputDecoration(
                    labelText: t('MBS / MBO (neobavezno)'),
                  ),
                ),
              ] else
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
                  labelText: _business
                      ? t('Adresa sjedišta')
                      : t('Adresa prebivališta'),
                ),
              ),
              if (_business) ...[
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('seller-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: t('E-mail za kupce'),
                    prefixIcon: const Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('seller-phone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: t('Telefon za kupce'),
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
              ],
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
              if (_business)
                CheckboxListTile(
                  key: const ValueKey('seller-certify'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _certified,
                  onChanged: (v) => setState(() => _certified = v ?? false),
                  title: Text(
                    t(
                      'Potvrđujem da prodajem samo proizvode u skladu s propisima EU i da kupcima osiguravam pravo na povrat u 14 dana i jamstvo.',
                    ),
                    style: const TextStyle(fontSize: 13),
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
