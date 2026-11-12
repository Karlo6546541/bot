import '../config/features.dart';
import 'dart:async';

import 'device_detail_screen.dart';
import 'shipping_profiles_screen.dart';
import '../services/storage_service.dart';
import '../services/app_location/app_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delivery.dart' show ParcelSize;
import '../models/shipping_profile.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/file_store.dart';
import '../services/image_store.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/trade_actions.dart';
import '../l10n/tr.dart';
import 'create_auction_screen.dart';
import 'live_screens.dart';
import 'seller_screens.dart';
import 'sell_screens.dart';

/// Kako se novi predmet prodaje (jedan predmet, tri načina).
enum SellMode {
  buyNow('🏷️', 'Kupi odmah', 'Fiksna cijena · provizija 5 %'),
  auction('⏱️', 'Aukcija', '1–7 dana · 10 % od razlike'),
  live('🔴', 'Live', 'Licitacija uživo · 10 % od razlike'),
  keep('📦', 'Samo spremi', 'Odlučit ću kasnije');

  const SellMode(this.emoji, this._label, this._hint);
  final String emoji;
  final String _label;
  final String _hint;
  String get label => t(_label);
  String get hint => t(_hint);
}

/// Forma za dodavanje uređaja u portfolio. Sva polja su obavezna.
class AddDeviceScreen extends ConsumerStatefulWidget {
  const AddDeviceScreen({super.key});

  static Future<void> open(BuildContext context) async {
    if (blockGuest(context, place: 'new=item')) return;
    // Predmet ide u "Moje predmete"; podaci prodavatelja traže se tek za
    // aukciju ili isplatu.
    // Samo aukcije: jedna jednostavna stranica za objavu (kao Vinted).
    if (!kLiveEnabled) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const AppPlace('new=item').settings,
          builder: (_) => const SellAuctionScreen(),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const AppPlace('new=item').settings,
        builder: (_) => const AddDeviceScreen(),
      ),
    );
  }

  @override
  ConsumerState<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends ConsumerState<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _model = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _description = TextEditingController();
  DeviceCondition? _condition = DeviceCondition.good;

  /// Veličina paketa (cijena dostave za kupca).
  ParcelSize _size = ParcelSize.small;

  /// Odabrani profil dostave (veličina paketa se računa iz njega).
  String? _profileId;
  ItemSection _section = ItemSection.electronics;
  DeviceCategory? _category;

  /// Kategorija je odabrana rukom (prijedlog iz naziva je više ne mijenja).
  bool _categoryManual = false;

  /// Prikazan je izbornik kategorija (inače samo predložena kategorija).
  bool _pickCategory = false;

  /// Kategorija iz naziva (npr. "iPhone" → Mobitel) dok je korisnik sam
  /// ne odabere.
  void _suggest(String name) {
    if (_categoryManual) return;
    final c = suggestCategory(name);
    if (c == null) return;
    _category = c;
    _section = c.section;
  }

  /// Kako se predmet prodaje nakon spremanja.
  SellMode _mode = kBuyNowEnabled ? SellMode.buyNow : SellMode.auction;
  bool get _listOnMarket => _mode == SellMode.buyNow;

  /// Datoteka digitalnog proizvoda (3D model, softver…).
  PickedFile? _file;

  bool get _digital => _section == ItemSection.digital;

  /// Digitalni proizvod ide u Kupi odmah samo kad je on uključen; inače se
  /// prodaje preko livea (pobjednik dobiva datoteku), a ne preko aukcije.
  bool get _digitalMarket => _digital && kBuyNowEnabled;

  /// Način prodaje (digitalno: live ili samo spremi).
  SellMode get _effMode =>
      _digital && !kBuyNowEnabled && _mode == SellMode.auction
      ? SellMode.live
      : _mode;

  Future<void> _pickFile(FormFieldState<PickedFile> field) async {
    final store = ref.read(fileStoreProvider);
    try {
      final f = await store.pick();
      if (f == null) return;
      final error = store.validate(f);
      if (error != null) {
        showLoopSnackBar(error, error: true);
        return;
      }
      setState(() => _file = f);
      field.didChange(f);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } catch (e) {
      showLoopSnackBar(t('Greška: {0}', [e]), error: true);
    }
  }

  /// Fotografije odabrane prije spremanja (već kopirane u mapu aplikacije).
  final _photos = <String>[];
  bool _saved = false;
  late final ImageStore _store;

  /// Skica (osvježavanje stranice ne briše uneseno).
  Timer? _draftTimer;
  bool _restoring = false;
  late final StorageService _drafts;

  void _restoreDraft() {
    final d = _drafts.addDraft;
    if (d == null) return;
    _restoring = true;
    _name.text = d['name'] as String? ?? '';
    _model.text = d['model'] as String? ?? '';
    _price.text = d['price'] as String? ?? '';
    _quantity.text = d['quantity'] as String? ?? '1';
    _description.text = d['description'] as String? ?? '';
    _condition =
        DeviceCondition.values
            .where((c) => c.name == d['condition'])
            .firstOrNull ??
        _condition;
    _size = ParcelSize.fromName(d['size'] as String?);
    _profileId = d['profile'] as String?;
    final cat = DeviceCategory.values
        .where((c) => c.name == d['category'])
        .firstOrNull;
    if (cat != null) {
      _category = cat;
      _section = cat.section;
      _categoryManual = d['categoryManual'] == true;
    }
    _mode =
        SellMode.values
            .where(
              (m) =>
                  m.name == d['mode'] &&
                  (kBuyNowEnabled || m != SellMode.buyNow),
            )
            .firstOrNull ??
        _mode;
    _photos.addAll([for (final p in (d['photos'] as List? ?? [])) '$p']);
    _restoring = false;
  }

  void _saveDraft() {
    if (_restoring || _saved) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), () {
      if (_saved) return;
      final empty =
          _name.text.trim().isEmpty &&
          _price.text.trim().isEmpty &&
          _description.text.trim().isEmpty &&
          _photos.isEmpty;
      _drafts.setAddDraft(
        empty
            ? null
            : {
                'name': _name.text,
                'model': _model.text,
                'price': _price.text,
                'quantity': _quantity.text,
                'description': _description.text,
                'condition': _condition?.name,
                'size': _size.name,
                'profile': _profileId,
                'category': _category?.name,
                'categoryManual': _categoryManual,
                'mode': _mode.name,
                'photos': List.of(_photos),
              },
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _store = ref.read(imageStoreProvider);
    _drafts = ref.read(storageProvider);
    _restoreDraft();
    for (final c in [_name, _model, _price, _quantity, _description]) {
      c.addListener(_saveDraft);
    }
  }

  @override
  void dispose() {
    // Odustao je (Natrag): skica i kopije fotografija se brišu. Osvježavanje
    // stranice ne zove dispose, pa skica tada ostaje.
    _draftTimer?.cancel();
    _drafts.setAddDraft(null);
    if (!_saved && _photos.isNotEmpty) {
      _store.delete(_photos);
    }
    _name.dispose();
    _model.dispose();
    _price.dispose();
    _quantity.dispose();
    _description.dispose();
    super.dispose();
  }

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

  ShippingProfile? get _profile => ref
      .read(appProvider)
      .currentUser
      ?.shippingProfiles
      .where((p) => p.id == _profileId)
      .firstOrNull;

  /// Spremi kao skicu (u Moje predmete, bez objave).
  Future<void> _saveAsDraft() async {
    setState(() => _mode = SellMode.keep);
    await _submit();
  }

  /// Prihvaća i decimalni zarez i točku.
  double? _parsePrice(String? v) =>
      double.tryParse((v ?? '').trim().replaceAll(',', '.'));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Kupi odmah traži podatke prodavatelja (DAC7/DSA).
    if ((_digitalMarket || _listOnMarket) &&
        (!await ensureSellerInfo(context) || !mounted)) {
      return;
    }
    Device? saved;
    final ok = await runWithLoading(
      context,
      () async {
        final app = ref.read(appProvider.notifier);
        saved = await app.addDevice(
          name: _name.text,
          model: _model.text.trim(),
          condition: _digital ? DeviceCondition.brandNew : _condition!,
          price: _parsePrice(_price.text)!,
          category: _category!,
          imagePaths: List.of(_photos),
          description: _description.text,
          listOnMarket: _digitalMarket || _listOnMarket,
          quantity: _digital ? 1 : int.tryParse(_quantity.text.trim()) ?? 1,
          file: _digital ? _file : null,
          parcelSize: _size.name,
        );
        final profile = _profile;
        if (profile != null && !_digital) {
          await app.setDeviceShipping(saved!.id, profile);
        }
      },
      successMessage: _digitalMarket || _listOnMarket
          ? t('Predmet je na prodaji')
          : t('Predmet dodan u Moje predmete'),
    );
    if (ok) {
      _saved = true;
      _draftTimer?.cancel();
      await ref.read(storageProvider).setAddDraft(null);
    }
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    final d = saved;
    if (d == null) return;
    if (_digitalMarket) {
      await DeviceDetailScreen.open(nav.context, d);
      return;
    }
    // Nastavak prema odabranom načinu prodaje.
    switch (_effMode) {
      case SellMode.auction:
        await CreateAuctionScreen.open(nav.context, deviceId: d.id);
      case SellMode.live:
        await addToLive(nav.context, ref, d);
      case SellMode.buyNow:
        // Odmah vidiš svoj oglas (ne feed).
        await DeviceDetailScreen.open(nav.context, d);
      case SellMode.keep:
        break;
    }
  }

  /// Odabir kategorije u listiću (odjeljak pa kategorija) — ne zauzima
  /// ekran obrasca dok nije potreban.
  Future<void> _chooseCategory(FormFieldState<DeviceCategory> field) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: SingleChildScrollView(
              key: const ValueKey('add-category-sheet'),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('Odaberi kategoriju'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final sec in ItemSection.active)
                        ChoiceChip(
                          avatar: Icon(sec.icon, size: 18),
                          label: Text(sec.label),
                          selected: _section == sec,
                          onSelected: (_) {
                            setState(() {
                              _section = sec;
                              _category = null;
                            });
                            field.didChange(null);
                            setSheet(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in _section.categories)
                        _CategoryTile(
                          category: c,
                          selected: _category == c,
                          onTap: () {
                            setState(() {
                              _category = c;
                              _categoryManual = true;
                              _pickCategory = false;
                            });
                            field.didChange(c);
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? t('Obavezno polje') : null;

  /// Dostava: profil dostave (težina, dimenzije, paketi) ili ručno
  /// odabrana veličina paketa. O njoj ovisi cijena dostave za kupca.
  Widget _shippingSection() {
    final profiles =
        ref.watch(appProvider).currentUser?.shippingProfiles ??
        const <ShippingProfile>[];
    final profile = profiles.where((p) => p.id == _profileId).firstOrNull;
    final size = profile?.parcelSize ?? _size;
    return Container(
      key: const ValueKey('add-shipping'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Dostava'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('add-profile-${profile?.id}'),
            initialValue: profile?.id ?? '',
            isExpanded: true,
            decoration: InputDecoration(labelText: t('Profil dostave')),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(t('Bez profila (odaberi veličinu)')),
              ),
              for (final p in profiles)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    '${p.name} · ${p.weightLabel}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              DropdownMenuItem(
                value: '+new',
                child: Text(
                  '+ ${t('Novi profil dostave')}',
                  style: TextStyle(
                    color: LoopColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            onChanged: (v) async {
              if (v == '+new') {
                final created = await ShippingProfileForm.open(context);
                if (!mounted) return;
                setState(() => _profileId = created?.id ?? _profileId);
                return;
              }
              setState(() => _profileId = v == '' ? null : v);
            },
          ),
          const SizedBox(height: 10),
          if (profile != null)
            Text(
              '${profile.summary} · ${t('Veličina paketa: {0}', [size.label])}',
              key: const ValueKey('add-profile-summary'),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final z in ParcelSize.values)
                  ChoiceChip(
                    key: ValueKey('parcel-${z.name}'),
                    label: Text(z.label),
                    selected: _size == z,
                    onSelected: (_) => setState(() => _size = z),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_size.hint}${_size.extra > 0 ? ' · ${t('+{0} na dostavu', [formatCredits(_size.extra)])}' : ''}${_size.index > ParcelSize.medium.index ? ' · ${t('bez paketomata')}' : ''}',
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  /// Ima li unesenih podataka koji bi se izgubili izlaskom.
  bool get _dirty =>
      !_saved &&
      (_name.text.trim().isNotEmpty ||
          _price.text.trim().isNotEmpty ||
          _description.text.trim().isNotEmpty ||
          _photos.isNotEmpty);

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).maybePop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Odbaciti promjene?')),
        content: Text(t('Ako sada izađeš, promjene će biti izgubljene.')),
        actions: [
          TextButton(
            key: const ValueKey('add-keep'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Odustani')),
          ),
          FilledButton(
            key: const ValueKey('add-discard'),
            style: FilledButton.styleFrom(backgroundColor: LoopColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Odbaci')),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Widget _head(String title, [String? subtitle]) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 14),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Svaka promjena (odabir stanja, veličine, kategorije…) ide u skicu.
    _saveDraft();
    const gap = SizedBox(height: 14);
    const divider = Padding(
      padding: EdgeInsets.symmetric(vertical: 22),
      child: Divider(height: 1),
    );
    final canDraft = _effMode != SellMode.keep && !_digitalMarket;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            key: const ValueKey('add-close'),
            tooltip: t('Zatvori'),
            onPressed: _close,
            icon: const Icon(Icons.close),
          ),
          title: Text(
            t('Dodaj proizvod'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                key: const ValueKey('add-form'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // Kategorija se bira dodirom na polje.
                  FormField<DeviceCategory>(
                    key: ValueKey('cat-${_category?.name}'),
                    initialValue: _category,
                    validator: (v) =>
                        v == null ? t('Odaberi kategoriju') : null,
                    builder: (field) => InkWell(
                      key: ValueKey(
                        !_pickCategory && _category != null
                            ? 'add-category'
                            : 'add-category-pick',
                      ),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _chooseCategory(field),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: '${t('Kategorija')} *',
                          errorText: field.errorText,
                          suffixIcon: const Icon(Icons.keyboard_arrow_down),
                        ),
                        child: Text(
                          _category?.singular ?? t('Odaberi kategoriju'),
                          style: TextStyle(
                            color: _category == null
                                ? LoopColors.textSecondary
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_category != null && !_categoryManual)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const ValueKey('add-category-change'),
                        onPressed: () => setState(() => _pickCategory = true),
                        child: Text(t('Promijeni kategoriju')),
                      ),
                    ),
                  gap,
                  if (_store.supported) ...[
                    PhotoPickerRow(
                      photos: _photos,
                      canUseCamera: ref.read(imageStoreProvider).canUseCamera,
                      onPick: _pickPhotos,
                      onRemove: (path) {
                        setState(() => _photos.remove(path));
                        ref.read(imageStoreProvider).delete([path]);
                      },
                    ),
                    gap,
                  ],
                  if (!_digital) ...[
                    _head(t('Stanje')),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in DeviceCondition.values)
                          ChoiceChip(
                            key: ValueKey('condition-${c.name}'),
                            showCheckmark: false,
                            avatar: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: c.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            label: Text(c.label),
                            selected: _condition == c,
                            onSelected: (_) => setState(() => _condition = c),
                          ),
                      ],
                    ),
                    gap,
                  ],
                  TextFormField(
                    key: const ValueKey('add-name'),
                    controller: _name,
                    maxLength: Device.maxName,
                    onChanged: (v) => setState(() => _suggest(v)),
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: '${t('Naslov')} *',
                      hintText: t('npr. iPhone 15 Pro, LEGO set, radionica…'),
                    ),
                    validator: _required,
                  ),
                  gap,
                  TextFormField(
                    key: const ValueKey('add-description'),
                    controller: _description,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: Device.maxDescription,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: t('Opis'),
                      hintText: t(
                        'Stanje, oštećenja, što dolazi u paketu, razlog prodaje…',
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (!_digital) ...[
                    gap,
                    _QuantityStepper(
                      controller: _quantity,
                      onChanged: () => setState(() {}),
                    ),
                  ],
                  gap,
                  TextFormField(
                    key: const ValueKey('add-price'),
                    controller: _price,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      LengthLimitingTextInputFormatter(9),
                    ],
                    decoration: InputDecoration(
                      labelText: '${t('Cijena')} *',
                      suffixText: t('€'),
                    ),
                    validator: (v) {
                      final p = _parsePrice(v);
                      if (p == null) return t('Unesi ispravnu cijenu');
                      if (p <= 0) return t('Cijena mora biti veća od 0');
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),
                  // Dodatno (neobavezno).
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: const ValueKey('add-more'),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text(
                        t('Više detalja'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        t('Model, godina, veličina, termin…'),
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      children: [
                        TextFormField(
                          key: const ValueKey('add-model'),
                          controller: _model,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: t('Model / detalji'),
                            hintText: t(
                              'npr. 256GB Titanium, godina, veličina, termin…',
                            ),
                          ),
                        ),
                        gap,
                      ],
                    ),
                  ),
                  if (!_digital) ...[
                    divider,
                    _head(t('Dostava')),
                    _shippingSection(),
                  ],
                  if (_digital) ...[
                    gap,
                    FormField<PickedFile>(
                      key: const ValueKey('digital-file'),
                      initialValue: _file,
                      validator: (v) => v == null
                          ? t('Dodaj datoteku koju kupac preuzima.')
                          : null,
                      builder: (field) => _FilePickerCard(
                        file: _file,
                        error: field.errorText,
                        onPick: () => _pickFile(field),
                        maxMb:
                            ref.read(fileStoreProvider).maxBytes ~/
                            (1024 * 1024),
                      ),
                    ),
                  ],
                  divider,
                  if (_digitalMarket)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: LoopColors.mint,
                        borderRadius: BorderRadius.circular(kRadius),
                      ),
                      child: Text(
                        t(
                          'Digitalni proizvod odmah ide u Kupi odmah i možeš ga prodati više puta. Dobivaš cijenu umanjenu za 5 % provizije, a kupac odmah preuzima datoteku.',
                        ),
                      ),
                    )
                  else ...[
                    if (_digital) ...[
                      Container(
                        key: const ValueKey('digital-live-note'),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: LoopColors.mint,
                          borderRadius: BorderRadius.circular(kRadius),
                        ),
                        child: Text(
                          t(
                            'Digitalni proizvod prodaješ u liveu: pobjednik licitacije odmah dobiva datoteku za preuzimanje, bez dostave. Predmet ostaje tebi pa ga možeš prodati i u sljedećem liveu.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _head(t('Kako prodaješ?')),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in SellMode.values)
                          if ((kBuyNowEnabled || m != SellMode.buyNow) &&
                              !(_digital && m == SellMode.auction))
                            ChoiceChip(
                              key: ValueKey('sell-${m.name}'),
                              label: Text(m.label),
                              selected: _effMode == m,
                              onSelected: (_) => setState(() => _mode = m),
                            ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _effMode.hint,
                      key: const ValueKey('sell-hint'),
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Stalna donja traka: Spremi skicu / glavna radnja.
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: LoopColors.background,
            border: Border(
              top: BorderSide(
                color: LoopColors.textPrimary.withValues(alpha: .1),
              ),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Row(
                    children: [
                      if (canDraft) ...[
                        Expanded(
                          child: FilledButton.tonal(
                            key: const ValueKey('add-save-draft'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 52),
                            ),
                            onPressed: _saveAsDraft,
                            child: Text(t('Spremi skicu')),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: canDraft ? 1 : 2,
                        child: FilledButton(
                          key: const ValueKey('add-submit'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 52),
                          ),
                          onPressed: _submit,
                          child: Text(switch (_effMode) {
                            _ when _digitalMarket => t('Objavi za Kupi odmah'),
                            SellMode.buyNow => t('Objavi'),
                            SellMode.auction => t('Dalje'),
                            SellMode.live => t('Dalje'),
                            SellMode.keep => t('Spremi'),
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final DeviceCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = category.color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected ? category.gradient : null,
            color: selected ? null : LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(
              color: selected ? c : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                category.icon,
                color: selected ? c : LoopColors.textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                category.singular,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? LoopColors.textPrimary
                      : LoopColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhotoPickerRow extends StatelessWidget {
  const PhotoPickerRow({
    super.key,
    required this.photos,
    required this.canUseCamera,
    required this.onPick,
    required this.onRemove,
  });

  final List<String> photos;
  final bool canUseCamera;
  final Future<void> Function({bool camera}) onPick;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final full = photos.length >= maxImages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('Fotografije ({0}/{1}) · neobavezno', [photos.length, maxImages]),
          style: TextStyle(color: LoopColors.textSecondary),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final path in photos)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 88,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () => PhotoViewer.open(
                              context,
                              photos,
                              initial: photos.indexOf(path),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(kRadius),
                              child: LocalPhoto(
                                path: path,
                                cacheWidth: 264,
                                fallback: Container(color: LoopColors.surface),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => onRemove(path),
                              child: const Padding(
                                padding: EdgeInsets.all(3),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!full && canUseCamera)
                _PickTile(
                  icon: Icons.photo_camera_outlined,
                  label: t('Uslikaj'),
                  onTap: () => onPick(camera: true),
                ),
              if (!full)
                _PickTile(
                  icon: Icons.add_photo_alternate_outlined,
                  label: t('Galerija'),
                  onTap: () => onPick(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadius),
        child: Container(
          width: 88,
          decoration: BoxDecoration(
            color: LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(color: LoopColors.surfaceHover, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: LoopColors.textSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: LoopColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Odabir datoteke digitalnog proizvoda.
class _FilePickerCard extends StatelessWidget {
  const _FilePickerCard({
    required this.file,
    required this.onPick,
    required this.maxMb,
    this.error,
  });

  final PickedFile? file;
  final VoidCallback onPick;
  final int maxMb;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final f = file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: LoopColors.surface,
          borderRadius: BorderRadius.circular(kRadius),
          child: InkWell(
            key: const ValueKey('pick-file'),
            borderRadius: BorderRadius.circular(kRadius),
            onTap: onPick,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kRadius),
                border: Border.all(
                  color: error != null
                      ? LoopColors.error
                      : f != null
                      ? LoopColors.success
                      : LoopColors.surfaceHover,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    f == null ? Icons.upload_file : Icons.insert_drive_file,
                    size: 32,
                    color: f == null ? LoopColors.accent : LoopColors.success,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f == null ? t('Dodaj datoteku') : f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          f == null
                              ? t(
                                  'STL, OBJ, 3MF, ZIP, PDF, EPUB, PNG, SVG, MP3… · najviše {0} MB',
                                  [maxMb],
                                )
                              : DigitalFile(
                                  ref: '',
                                  name: f.name,
                                  size: f.size,
                                  uploadedAt: DateTime(2000),
                                ).sizeLabel,
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (f != null)
                    Text(
                      t('Promijeni'),
                      style: TextStyle(
                        color: LoopColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              error!,
              style: TextStyle(color: LoopColors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// Količina na zalihi s − i + (kao Whatnot "Quantity Available").
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final q = int.tryParse(controller.text.trim()) ?? 1;
    void set(int v) {
      controller.text = '${v.clamp(1, Device.maxQuantity)}';
      onChanged();
    }

    return Row(
      key: const ValueKey('quantity-field'),
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('Količina na zalihi'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                t('Svaka kupnja skida jedan komad.'),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('quantity-minus'),
          onPressed: q > 1 ? () => set(q - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: LoopColors.surfaceHover,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$q',
            key: const ValueKey('quantity-value'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        IconButton(
          key: const ValueKey('quantity-plus'),
          onPressed: q < Device.maxQuantity ? () => set(q + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
