import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../services/stripe_backend.dart';
import '../models/seller_info.dart';
import '../providers/seller_account_provider.dart';
import '../widgets/quiet_ui.dart';
export '../providers/seller_account_provider.dart'
    show sellerOnboardingProvider, sellerPreparationProvider;
import '../providers/app_providers.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';

/// Prije objave u Marketu ili na aukciji: ako podaci prodavatelja nedostaju,
/// objasni zašto ih tražimo i otvori obrazac. Vraća `true` ako ih ima.
Future<bool> ensureSellerInfo(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final user = container.read(appProvider).currentUser;
  if (user == null || user.isGuest) return false;
  if (user.seller != null) {
    try {
      return await container.read(sellerOnboardingProvider)(
        user.seller!,
        user.country,
      );
    } catch (_) {
      if (context.mounted) {
        showLoopSnackBar(
          t(
            'Podaci su spremljeni. Povezivanje isplata trenutačno nije dostupno.',
          ),
          error: true,
        );
      }
      return false;
    }
  }
  final go = await confirmDialog(
    context,
    title: t('Podaci prodavatelja'),
    message: t(
      'Prije prve objave zakon traži tvoje podatke: ime ili naziv tvrtke, OIB, adresu i IBAN za isplatu (EU pravila DAC7 i DSA). Prodaješ kao privatna osoba ili kao obrt/tvrtka — kupci vide samo tu oznaku (a kod trgovca i podatke za kontakt).',
    ),
    confirmLabel: t('Ispuni podatke'),
  );
  if (!go || !context.mounted) return false;
  final saved = await SellerInfoScreen.open(context);
  if (!saved || !context.mounted) return false;
  return ensureSellerInfo(context);
}

/// Isplata zarade na IBAN (uz potvrdu).
Future<void> showPayoutDialog(BuildContext context, WidgetRef ref) async {
  if (!await ensureSellerInfo(context) || !context.mounted) return;
  final user = ref.read(appProvider).currentUser!;
  final held = ref.read(appProvider).heldEarnings(user.id);
  final amount = user.credits - held;
  if (amount <= 0) {
    showLoopSnackBar(
      held > 0
          ? t('Zarada se oslobađa kad paket stigne kupcu ili kad se riješi spor.')
          : t('Nemaš zarade za isplatu.'),
      error: true,
    );
    return;
  }
  final ok = await confirmDialog(
    context,
    title: t('Isplatiti zaradu?'),
    message: t(
      '{0} ide na račun {1}. Isplatu obrađuje pružatelj plaćanja (obično 1–2 radna dana).',
      [formatCredits(amount), user.seller!.maskedIban],
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
  const SellerInfoScreen({super.key, this.embedded = false});
  final bool embedded;

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
  final _scroll = ScrollController();
  final _formKey = GlobalKey<FormState>();

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
    _scroll.dispose();
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
    if (picked != null && mounted) setState(() => _birth = picked);
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
      return;
    }
    final owner = ref.read(appProvider).currentUser;
    if (owner == null || owner.isGuest) return;
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
      final synced = await ref.read(appProvider.notifier).saveSellerInfo(info);
      if (!mounted || ref.read(appProvider).currentUser?.id != owner.id) return;
      ref.invalidate(sellerAccountStatusProvider(owner.id));
      if (synced) {
        // Saving is durable before preparation and never waits for Stripe.
        unawaited(
          ref
              .read(sellerAccountStatusProvider(owner.id).future)
              .then<void>((_) {}, onError: (_) {}),
        );
      }
      showLoopSnackBar(
        synced
            ? t('Podaci prodavatelja su spremljeni.')
            : t(
                'Podaci su spremljeni na uređaju. Poslat ćemo ih kad se veza vrati.',
              ),
      );
      if (!widget.embedded) Navigator.pop(context, true);
    } on TradeException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    } catch (error) {
      if (mounted) setState(() => _error = paymentActionErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget gap() => const SizedBox(height: 16);
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 14),
      child: Text(
        label,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    );
    InputDecoration field(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      counterText: '',
      filled: false,
      border: const UnderlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
    );
    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(t('Podaci prodavatelja'))),
      bottomNavigationBar: AppBottomAction(
        child: FilledButton(
          key: const ValueKey('seller-save'),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('Spremi podatke')),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                ScreenHeading(
                  title: t('Prodaja počinje ovdje.'),
                  subtitle: t(
                    'Unesi podatke jednom. Čuvamo ih u tvojem privatnom računu.',
                  ),
                ),
                if (_error != null) ...[
                  AppStatusCard(
                    title: _error!,
                    icon: Icons.error_outline,
                    color: LoopColors.error,
                  ),
                  gap(),
                ],
                Wrap(
                  key: const ValueKey('seller-kind'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('seller-kind-private'),
                      avatar: const Icon(Icons.person_outline, size: 18),
                      label: Text(t('Privatna osoba')),
                      selected: !_business,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _kind = SellerKind.private;
                              _error = null;
                            }),
                    ),
                    ChoiceChip(
                      avatar: const Icon(Icons.storefront_outlined, size: 18),
                      label: Text(
                        t('Obrt / tvrtka'),
                        key: const ValueKey('seller-kind-business'),
                      ),
                      selected: _business,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _kind = SellerKind.business;
                              _error = null;
                            }),
                    ),
                  ],
                ),
                heading(_business ? t('Podaci tvrtke') : t('Osobni podaci')),
                if (_business) ...[
                  TextFormField(
                    key: const ValueKey('seller-company'),
                    controller: _company,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v?.trim().length ?? 0) < 3
                        ? t('Upiši naziv obrta ili tvrtke.')
                        : null,
                    decoration: field(t('Naziv obrta ili tvrtke')),
                  ),
                  gap(),
                  DropdownButtonFormField<LegalForm>(
                    key: const ValueKey('seller-form'),
                    initialValue: _form,
                    isExpanded: true,
                    decoration: field(t('Pravni oblik')),
                    items: [
                      for (final form in LegalForm.values)
                        DropdownMenuItem(value: form, child: Text(form.label)),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _form = value ?? _form),
                  ),
                  gap(),
                ],
                TextFormField(
                  key: const ValueKey('seller-name'),
                  controller: _name,
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v?.trim().length ?? 0) < 3
                      ? t('Upiši ime i prezime.')
                      : null,
                  decoration: field(
                    _business
                        ? t('Odgovorna osoba (ime i prezime)')
                        : t('Ime i prezime'),
                  ),
                ),
                gap(),
                TextFormField(
                  key: const ValueKey('seller-oib'),
                  controller: _oib,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 11,
                  validator: (v) => SellerInfo.validOib(v ?? '')
                      ? null
                      : t('OIB nije ispravan (11 znamenki).'),
                  decoration: field(
                    _business ? t('OIB obrta / tvrtke') : t('OIB'),
                  ),
                ),
                if (!_business) ...[
                  gap(),
                  Material(
                    color: LoopColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      key: const ValueKey('seller-birth'),
                      leading: const Icon(
                        Icons.calendar_today_outlined,
                        size: 21,
                      ),
                      title: Text(t('Datum rođenja')),
                      subtitle: Text(
                        _birth == null ? t('Odaberi') : formatDate(_birth!),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : _pickBirth,
                    ),
                  ),
                ],
                heading(t('Adresa i isplate')),
                TextFormField(
                  key: const ValueKey('seller-address'),
                  controller: _address,
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.fullStreetAddress],
                  textCapitalization: TextCapitalization.words,
                  maxLines: 2,
                  minLines: 1,
                  validator: (v) =>
                      (v?.trim().length ?? 0) < 5 ? t('Upiši adresu.') : null,
                  decoration: field(
                    _business ? t('Adresa sjedišta') : t('Adresa prebivališta'),
                  ),
                ),
                gap(),
                TextFormField(
                  key: const ValueKey('seller-iban'),
                  controller: _iban,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) => SellerInfo.validIban(v ?? '')
                      ? null
                      : t('IBAN nije ispravan.'),
                  decoration: field(
                    t('IBAN za isplatu'),
                    hint: 'HR12 3456 7890 1234 5678 9',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('IBAN je privatan. Kupci ga ne vide.'),
                  style: TextStyle(
                    fontSize: 12,
                    color: LoopColors.textSecondary,
                  ),
                ),
                if (_business) ...[
                  heading(t('Kontakt za kupce')),
                  TextFormField(
                    key: const ValueKey('seller-email'),
                    controller: _email,
                    enabled: !_busy,
                    autofillHints: const [AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(v?.trim() ?? '')
                        ? null
                        : t('Upiši e-mail za kupce.'),
                    decoration: field(t('E-mail za kupce')),
                  ),
                  gap(),
                  TextFormField(
                    key: const ValueKey('seller-phone'),
                    controller: _phone,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    validator: (v) =>
                        (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 6
                        ? t('Upiši telefon za kupce.')
                        : null,
                    decoration: field(t('Telefon za kupce')),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(t('Dodatni podaci')),
                    children: [
                      TextField(
                        key: const ValueKey('seller-vat'),
                        controller: _vat,
                        textCapitalization: TextCapitalization.characters,
                        decoration: field(
                          t('PDV broj (neobavezno)'),
                          hint: 'HR12345678901',
                        ),
                      ),
                      gap(),
                      TextField(
                        key: const ValueKey('seller-registry'),
                        controller: _registry,
                        decoration: field(t('MBS / MBO (neobavezno)')),
                      ),
                      gap(),
                    ],
                  ),
                  CheckboxListTile(
                    key: const ValueKey('seller-certify'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _certified,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _certified = v ?? false),
                    title: Text(
                      t(
                        'Potvrđujem da prodajem samo proizvode u skladu s propisima EU i da kupcima osiguravam pravo na povrat u 14 dana i jamstvo.',
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    t('Zašto tražimo ove podatke?'),
                    style: TextStyle(
                      fontSize: 13,
                      color: LoopColors.textSecondary,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        t(
                          'Podaci su potrebni za prodaju, isplate i zakonske obveze platforme. Spremanje podataka i dovršetak Stripe računa odvojeni su koraci.',
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: LoopColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
