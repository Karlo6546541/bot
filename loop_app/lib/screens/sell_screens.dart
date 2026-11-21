import '../config/features.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/auction.dart';
import '../models/delivery.dart' show ParcelSize;
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/auction_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/trade_actions.dart';
import 'add_device_screen.dart' show PhotoPickerRow;
import 'auction_detail_screen.dart';
import 'device_detail_screen.dart';
import 'seller_screens.dart';

/// Objava aukcije na jednoj stranici (kao Vinted): fotografije, naslov, opis,
/// kategorija, stanje, vrsta i cijena, trajanje, dostava — i "Objavi".
class SellAuctionScreen extends ConsumerStatefulWidget {
  /// [embedded]: tab Prodaj (bez gumba za zatvaranje; nakon objave se prazni).
  const SellAuctionScreen({super.key, this.embedded = false});
  final bool embedded;

  static Future<void> open(BuildContext context) async {
    if (blockGuest(context, place: 'new=item')) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SellAuctionScreen()));
  }

  @override
  ConsumerState<SellAuctionScreen> createState() => _SellAuctionScreenState();
}

class _SellAuctionScreenState extends ConsumerState<SellAuctionScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _floor = TextEditingController();
  final _photos = <String>[];
  DeviceCategory? _category;
  bool _categoryManual = false;
  DeviceCondition _condition = DeviceCondition.good;
  AuctionKind _kind = AuctionKind.classic;

  /// Kako prodavač prodaje: aukcija ili Kupi odmah (fiksna cijena).
  bool _buyNow = kClassifiedsMode;
  Duration _duration = AuctionService.durations[2].$2;
  ParcelSize _size = ParcelSize.small;

  /// Ocjena (PSA, BGS, CGC…) ako je predmet ocijenjen; neobavezno.
  GradingCertificate? _cert;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _floor.dispose();
    super.dispose();
  }

  double? _num(String v) => double.tryParse(v.trim().replaceAll(',', '.'));

  Future<void> _pickPhotos({bool camera = false}) async {
    try {
      final paths = await ref
          .read(imageStoreProvider)
          .pick(camera: camera, limit: maxImages - _photos.length);
      if (mounted) setState(() => _photos.addAll(paths));
    } catch (e) {
      showLoopSnackBar(
        t('Fotografiju nije moguće učitati: {0}', [e]),
        error: true,
      );
    }
  }

  Future<void> _chooseCategory(FormFieldState<DeviceCategory> field) async {
    final c = await showModalBottomSheet<DeviceCategory>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .75,
          child: ListView(
            key: const ValueKey('sell-category-list'),
            children: [
              for (final section in ItemSection.active)
                if (section != ItemSection.digital &&
                    DeviceCategory.active.any((c) => c.section == section)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text(
                      section.label,
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final c in DeviceCategory.active)
                    if (c.section == section)
                      ListTile(
                        key: ValueKey('sell-cat-${c.name}'),
                        title: Text(c.singular),
                        trailing: _category == c
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(ctx, c),
                      ),
                ],
            ],
          ),
        ),
      ),
    );
    if (c == null) return;
    setState(() {
      _category = c;
      _categoryManual = true;
    });
    field.didChange(c);
  }

  void _resetForm() => setState(() {
    _title.clear();
    _description.clear();
    _price.clear();
    _floor.clear();
    _photos.clear();
    _category = null;
    _categoryManual = false;
    _cert = null;
    _kind = AuctionKind.classic;
  });

  Future<void> _submit() async {
    if (kClassifiedsMode &&
        blockGuest(context, reason: t('Za objavu oglasa prijavi se.'))) {
      return;
    }
    if (!_form.currentState!.validate()) return;
    if (!kClassifiedsMode && (!await ensureSellerInfo(context) || !mounted)) {
      return;
    }
    final start = _num(_price.text)!;
    final floor = !_buyNow && _kind == AuctionKind.dutch
        ? _num(_floor.text)
        : null;
    if (_buyNow) {
      Device? listed;
      final ok = await runWithLoading(context, () async {
        listed = await ref
            .read(appProvider.notifier)
            .addDevice(
              name: _title.text,
              model: '',
              condition: _condition,
              price: start,
              category: _category!,
              imagePaths: List.of(_photos),
              description: _description.text,
              listOnMarket: true,
              parcelSize: _size.name,
              certificate: _cert,
            );
      }, successMessage: t('Oglas je objavljen'));
      if (!ok || !mounted || listed == null) return;
      if (widget.embedded) _resetForm();
      await DeviceDetailScreen.open(context, listed!);
      if (!widget.embedded && mounted) Navigator.of(context).pop();
      return;
    }
    Auction? created;
    final ok = await runWithLoading(context, () async {
      final app = ref.read(appProvider.notifier);
      final device = await app.addDevice(
        name: _title.text,
        model: '',
        condition: _condition,
        price: start,
        category: _category!,
        imagePaths: List.of(_photos),
        description: _description.text,
        listOnMarket: false,
        parcelSize: _size.name,
        certificate: _cert,
      );
      created = await app.createAuction(
        deviceId: device.id,
        startPrice: start,
        duration: _duration,
        kind: _kind,
        floorPrice: floor,
      );
    }, successMessage: t('Aukcija je objavljena'));
    if (!ok || !mounted || created == null) return;
    if (widget.embedded) {
      // Forma se prazni, a objavljena aukcija se otvara.
      _resetForm();
      await AuctionDetailScreen.open(context, created!.id);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AuctionDetailScreen(auctionId: created!.id),
      ),
    );
  }

  /// Izbor iz kratkog popisa u donjem listu (kao Vinted).
  Future<T?> _pick<T>({
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T) label,
    String Function(T)? hint,
    required String keyPrefix,
    required String Function(T) keyOf,
  }) => showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          for (final v in values)
            ListTile(
              key: ValueKey('$keyPrefix-${keyOf(v)}'),
              title: Text(label(v)),
              subtitle: hint == null ? null : Text(hint(v)),
              trailing: v == selected
                  ? Icon(Icons.check, color: LoopColors.accent)
                  : null,
              onTap: () => Navigator.pop(ctx, v),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  /// Certifikat ocjene: kuća, ocjena i broj (za provjeru kod izdavatelja).
  Future<void> _editCertificate() async {
    var grader = _cert?.grader ?? Grader.psa;
    final grade = TextEditingController(text: _cert?.grade ?? '');
    final number = TextEditingController(text: _cert?.number ?? '');
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('Certifikat ocjene'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t(
                  'Ako je predmet ocijenjen (slabiran), upiši kuću, ocjenu i broj certifikata. Kupac ga može provjeriti kod izdavatelja.',
                ),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in Grader.values)
                    ChoiceChip(
                      key: ValueKey('sell-grader-${g.name}'),
                      label: Text(g == Grader.other ? t('Drugo') : g.label),
                      selected: grader == g,
                      onSelected: (_) => setSheet(() => grader = g),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('sell-grade'),
                controller: grade,
                maxLength: 12,
                decoration: InputDecoration(
                  labelText: t('Ocjena'),
                  hintText: t('npr. 10, 9.5, MS 65'),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('sell-cert-number'),
                controller: number,
                maxLength: 24,
                decoration: InputDecoration(
                  labelText: t('Broj certifikata'),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_cert != null)
                    TextButton(
                      key: const ValueKey('sell-cert-remove'),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(t('Ukloni')),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('sell-cert-save'),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(t('Spremi')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (result == false) {
      setState(() => _cert = null);
    } else if (result == true) {
      final g = grade.text.trim();
      if (g.isEmpty) {
        showLoopSnackBar(t('Upiši ocjenu.'), error: true);
      } else {
        setState(
          () => _cert = GradingCertificate(
            grader: grader,
            grade: g,
            number: number.text.trim(),
          ),
        );
      }
    }
    grade.dispose();
    number.dispose();
  }

  /// Redak "Naziv ... vrijednost >" kao na Vintedu.
  Widget _row(
    String key,
    String title,
    String value,
    VoidCallback onTap, {
    String? error,
  }) => InkWell(
    key: ValueKey(key),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error ?? value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: error != null
                    ? LoopColors.error
                    : LoopColors.textSecondary,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: LoopColors.textSecondary),
        ],
      ),
    ),
  );

  Widget get _divider => Divider(height: 1, color: LoopColors.glassBorder);

  Widget _section(List<Widget> children) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: LoopColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: LoopColors.glassBorder),
    ),
    child: Column(children: children),
  );

  @override
  Widget build(BuildContext context) {
    // Oglasnik: oglas može objaviti samo prijavljen korisnik.
    final me = ref.watch(appProvider.select((s) => s.currentUser));
    if (kClassifiedsMode && (me == null || me.isGuest)) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.embedded,
          title: Text(
            widget.embedded ? t('Prodaj') : t('Novi oglas'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: EmptyState(
          key: const ValueKey('sell-login-gate'),
          icon: Icons.lock_outline,
          title: t('Za objavu oglasa prijavi se'),
          message: t(
            'Prijavi se Googleom ili e-mailom da objaviš oglas. Pregledavati i pisati oglase možeš i bez računa.',
          ),
          action: FilledButton.icon(
            key: const ValueKey('sell-login'),
            onPressed: () =>
                blockGuest(context, reason: t('Za objavu oglasa prijavi se.')),
            icon: const Icon(Icons.login),
            label: Text(t('Prijavi se')),
          ),
        ),
      );
    }
    final money = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      LengthLimitingTextInputFormatter(9),
    ];
    final durationLabel = AuctionService.durations
        .firstWhere(
          (e) => e.$2 == _duration,
          orElse: () => AuctionService.durations.first,
        )
        .$1;
    final plain = InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.embedded
            ? null
            : IconButton(
                key: const ValueKey('sell-close'),
                tooltip: t('Zatvori'),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.maybePop(context),
              ),
        title: Text(
          widget.embedded ? t('Prodaj') : t('Novi oglas'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: ListView(
              key: const ValueKey('sell-form'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                // 1. Fotografije: prazno = veliko polje "Dodaj fotografije".
                if (_photos.isEmpty)
                  InkWell(
                    key: const ValueKey('sell-add-photos'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: _pickPhotos,
                    child: Container(
                      height: 132,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: LoopColors.accent.withValues(alpha: .6),
                          width: 1.4,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            color: LoopColors.accent,
                            size: 30,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t('Dodaj fotografije'),
                            style: TextStyle(
                              color: LoopColors.accent,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t('Prednja i stražnja strana, detalji i oznake'),
                            style: TextStyle(
                              color: LoopColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  PhotoPickerRow(
                    photos: _photos,
                    canUseCamera: ref.read(imageStoreProvider).canUseCamera,
                    onPick: _pickPhotos,
                    onRemove: (path) {
                      setState(() => _photos.remove(path));
                      ref.read(imageStoreProvider).delete([path]);
                    },
                  ),
                // 2. Naslov i opis.
                _section([
                  TextFormField(
                    key: const ValueKey('sell-title'),
                    controller: _title,
                    maxLength: Device.maxName,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (v) {
                      if (_categoryManual) return;
                      final c = suggestCategory(v);
                      if (c != null) setState(() => _category = c);
                    },
                    decoration: plain.copyWith(
                      labelText: t('Naslov'),
                      hintText: t('npr. Charizard Holo 1999, PSA 9'),
                      counterText: '',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().length < 2 ? t('Upiši naslov') : null,
                  ),
                  _divider,
                  TextFormField(
                    key: const ValueKey('sell-description'),
                    controller: _description,
                    minLines: 2,
                    maxLines: 6,
                    maxLength: Device.maxDescription,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: plain.copyWith(
                      labelText: t('Opis'),
                      hintText: t(
                        'Izdanje, godina, stanje, oštećenja, certifikat…',
                      ),
                      alignLabelWithHint: true,
                      counterText: '',
                    ),
                  ),
                ]),
                // 3. Kategorija i stanje.
                _section([
                  FormField<DeviceCategory>(
                    key: ValueKey('sell-cat-field-${_category?.name}'),
                    initialValue: _category,
                    validator: (v) =>
                        v == null ? t('Odaberi kategoriju') : null,
                    builder: (field) => _row(
                      'sell-category',
                      t('Kategorija'),
                      _category?.singular ?? t('Odaberi'),
                      () => _chooseCategory(field),
                      error: field.errorText,
                    ),
                  ),
                  _divider,
                  _row(
                    'sell-condition',
                    t('Stanje'),
                    _condition.label,
                    () async {
                      final c = await _pick<DeviceCondition>(
                        title: t('Stanje'),
                        values: DeviceCondition.values,
                        selected: _condition,
                        label: (c) => c.label,
                        keyPrefix: 'sell-condition',
                        keyOf: (c) => c.name,
                      );
                      if (c != null) setState(() => _condition = c);
                    },
                  ),
                  _divider,
                  _row(
                    'sell-certificate',
                    t('Certifikat'),
                    _cert == null
                        ? t('Neobavezno')
                        : [
                            _cert!.badge,
                            if (_cert!.number.isNotEmpty) '#${_cert!.number}',
                          ].join(' · '),
                    _editCertificate,
                  ),
                ]),
                // 4. Način prodaje i cijena.
                const SizedBox(height: 16),
                if (kBuyNowEnabled && !kClassifiedsMode)
                  _ModeSwitch(
                    buyNow: _buyNow,
                    onChanged: (v) => setState(() => _buyNow = v),
                  ),
                _section([
                  TextFormField(
                    key: const ValueKey('sell-price'),
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: money,
                    decoration: plain.copyWith(
                      labelText: _buyNow
                          ? t('Cijena')
                          : _kind == AuctionKind.dutch
                          ? t('Početna (najviša) cijena')
                          : t('Početna cijena'),
                      suffixText: t('€'),
                    ),
                    validator: (v) {
                      final p = _num(v ?? '');
                      if (p == null || p <= 0) {
                        return kClassifiedsMode
                            ? t('Unesi cijenu veću od 0')
                            : t('Unesi početnu cijenu veću od 0');
                      }
                      return null;
                    },
                  ),
                  if (!_buyNow) ...[
                    _divider,
                    _row(
                      'sell-duration',
                      t('Trajanje'),
                      durationLabel,
                      () async {
                        final d = await _pick<Duration>(
                          title: t('Trajanje aukcije'),
                          values: [
                            for (final e in AuctionService.durations) e.$2,
                          ],
                          selected: _duration,
                          label: (d) => AuctionService.durations
                              .firstWhere((e) => e.$2 == d)
                              .$1,
                          keyPrefix: 'sell-duration',
                          keyOf: (d) => '${d.inMinutes}',
                        );
                        if (d != null) setState(() => _duration = d);
                      },
                    ),
                  ],
                ]),
                // 5. Dostava (oglasnik: dogovor s kupcem, bez dostave u aplikaciji).
                if (!kClassifiedsMode)
                  _section([
                    _row(
                      'sell-size',
                      t('Veličina paketa'),
                      _size.label,
                      () async {
                        final z = await _pick<ParcelSize>(
                          title: t('Veličina paketa'),
                          values: ParcelSize.values,
                          selected: _size,
                          label: (z) => z.label,
                          hint: (z) => z.hint,
                          keyPrefix: 'sell-size',
                          keyOf: (z) => z.name,
                        );
                        if (z != null) setState(() => _size = z);
                      },
                    ),
                  ]),
                const SizedBox(height: 10),
                Text(
                  kClassifiedsMode
                      ? t(
                          'Oglas je aktivan 30 dana, a produljiti ga možeš kad god želiš. Cijenu, plaćanje i preuzimanje dogovaraš izravno s kupcem; kupci te kontaktiraju porukom.',
                        )
                      : _buyNow
                      ? t(
                          'Dostavu plaća kupac. Novac ti stiže na IBAN nakon što kupac primi paket. Provizija se odbija od isplate.',
                        )
                      : t(
                          'Dostavu plaća kupac. Novac ti stiže na IBAN nakon što kupac primi paket. Provizija je 10 % samo od razlike iznad početne cijene.',
                        ),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            key: const ValueKey('sell-submit'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _submit,
            child: Text(_buyNow ? t('Objavi oglas') : t('Objavi aukciju')),
          ),
        ),
      ),
    );
  }
}

/// Način prodaje: dvije kapsule (Aukcija | Kupi odmah).
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.buyNow, required this.onChanged});
  final bool buyNow;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String key, IconData icon, String text, bool on, bool v) =>
        Expanded(
          child: Semantics(
            button: true,
            selected: on,
            child: InkWell(
              key: ValueKey(key),
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: on ? LoopColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: on
                          ? LoopColors.onAccent
                          : LoopColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        text,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: on
                              ? LoopColors.onAccent
                              : LoopColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LoopColors.glassBorder),
      ),
      child: Row(
        children: [
          option(
            'sell-mode-auction',
            Icons.gavel,
            t('Aukcija'),
            !buyNow,
            false,
          ),
          const SizedBox(width: 4),
          option(
            'sell-mode-buynow',
            Icons.sell_outlined,
            t('Kupi odmah'),
            buyNow,
            true,
          ),
        ],
      ),
    );
  }
}
