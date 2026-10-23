import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/file_store.dart';
import '../services/image_store.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/item_image.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/trade_actions.dart';
import '../l10n/tr.dart';
import 'create_auction_screen.dart';
import 'live_screens.dart';
import 'seller_screens.dart';

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
    if (blockGuest(context)) return;
    // Predmet ide u "Moje predmete"; podaci prodavatelja traže se tek za
    // aukciju ili isplatu.
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AddDeviceScreen()));
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
  SellMode _mode = SellMode.buyNow;
  bool get _listOnMarket => _mode == SellMode.buyNow;

  /// Datoteka digitalnog proizvoda (3D model, softver…).
  PickedFile? _file;

  bool get _digital => _section == ItemSection.digital;

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

  @override
  void initState() {
    super.initState();
    _store = ref.read(imageStoreProvider);
  }

  @override
  void dispose() {
    // Odustao je: obriši kopije fotografija koje nisu spremljene uz predmet.
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

  /// Prihvaća i decimalni zarez i točku.
  double? _parsePrice(String? v) =>
      double.tryParse((v ?? '').trim().replaceAll(',', '.'));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Kupi odmah traži podatke prodavatelja (DAC7/DSA).
    if ((_digital || _listOnMarket) &&
        (!await ensureSellerInfo(context) || !mounted)) {
      return;
    }
    Device? saved;
    final ok = await runWithLoading(
      context,
      () async => saved = await ref
          .read(appProvider.notifier)
          .addDevice(
            name: _name.text,
            model: _model.text.trim(),
            condition: _digital ? DeviceCondition.brandNew : _condition!,
            price: _parsePrice(_price.text)!,
            category: _category!,
            imagePaths: List.of(_photos),
            description: _description.text,
            listOnMarket: _digital || _listOnMarket,
            quantity: _digital ? 1 : int.tryParse(_quantity.text.trim()) ?? 1,
            file: _digital ? _file : null,
          ),
      successMessage: _digital || _listOnMarket
          ? t('Predmet je na prodaji 🏷️')
          : t('Predmet dodan u Moje predmete'),
    );
    if (ok) _saved = true;
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    final d = saved;
    if (d == null || _digital) return;
    // Nastavak prema odabranom načinu prodaje.
    switch (_mode) {
      case SellMode.auction:
        await CreateAuctionScreen.open(nav.context, deviceId: d.id);
      case SellMode.live:
        await addToLive(nav.context, ref, d);
      case SellMode.buyNow || SellMode.keep:
        break;
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? t('Obavezno polje') : null;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: Text(t('Dodaj predmet'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_store.supported) ...[
                      _PhotoPicker(
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
                    TextFormField(
                      controller: _name,
                      onChanged: (v) => setState(() => _suggest(v)),
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: t('Naziv'),
                        hintText: t('npr. iPhone 15 Pro, LEGO set, radionica…'),
                      ),
                      validator: _required,
                    ),
                    gap,
                    TextFormField(
                      controller: _price,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: InputDecoration(
                        labelText: t('Cijena'),
                        suffixText: t('€'),
                      ),
                      validator: (v) {
                        final p = _parsePrice(v);
                        if (p == null) return t('Unesi ispravnu cijenu');
                        if (p <= 0) return t('Cijena mora biti veća od 0');
                        return null;
                      },
                    ),
                    gap,
                    // Kategorija se bira dodirom na pločicu.
                    FormField<DeviceCategory>(
                      key: ValueKey('cat-${_category?.name}'),
                      initialValue: _category,
                      validator: (v) =>
                          v == null ? t('Odaberi kategoriju') : null,
                      builder: (field) => !_pickCategory && _category != null
                          ? ListTile(
                              key: const ValueKey('add-category'),
                              contentPadding: EdgeInsets.zero,
                              leading: CategoryAvatar(
                                category: _category!,
                                size: 40,
                              ),
                              title: Text(
                                _category!.singular,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                _categoryManual
                                    ? t('Kategorija')
                                    : t('Kategorija · predloženo iz naziva'),
                              ),
                              trailing: TextButton(
                                key: const ValueKey('add-category-change'),
                                onPressed: () =>
                                    setState(() => _pickCategory = true),
                                child: Text(t('Promijeni')),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t('Odjeljak'),
                                  style: TextStyle(
                                    color: LoopColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final sec in ItemSection.values)
                                      if (sec != ItemSection.digital)
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
                                          },
                                        ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  t('Kategorija'),
                                  style: TextStyle(
                                    color: LoopColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
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
                                        },
                                      ),
                                  ],
                                ),
                                if (field.hasError)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 6,
                                      left: 12,
                                    ),
                                    child: Text(
                                      field.errorText!,
                                      style: TextStyle(
                                        color: LoopColors.error,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 8),
                    // Sve ostalo je neobavezno — skriveno dok se ne zatraži.
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        key: const ValueKey('add-more'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: Text(
                          t('Više detalja (neobavezno)'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          t('Model, opis, stanje, količina'),
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        children: [
                          TextFormField(
                            controller: _model,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: t('Model / detalji (neobavezno)'),
                              hintText: t(
                                'npr. 256GB Titanium, godina, veličina, termin…',
                              ),
                            ),
                          ),
                          gap,
                          // Opis: neobavezan, do 500 znakova (brojač ispod polja).
                          TextFormField(
                            controller: _description,
                            minLines: 3,
                            maxLines: 6,
                            maxLength: Device.maxDescription,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              labelText: t('Opis (neobavezno)'),
                              hintText: t(
                                'Stanje, oštećenja, što dolazi u paketu, razlog prodaje…',
                              ),
                              alignLabelWithHint: true,
                            ),
                          ),
                          if (!_digital) ...[
                            gap,
                            DropdownButtonFormField<DeviceCondition>(
                              initialValue: _condition,
                              decoration: InputDecoration(
                                labelText: t('Stanje'),
                              ),
                              items: [
                                for (final c in DeviceCondition.values)
                                  DropdownMenuItem(
                                    value: c,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: c.color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(c.label),
                                      ],
                                    ),
                                  ),
                              ],
                              onChanged: (c) => setState(() => _condition = c),
                              validator: (v) =>
                                  v == null ? t('Odaberi stanje') : null,
                            ),
                            gap,
                            TextFormField(
                              key: const ValueKey('quantity-field'),
                              controller: _quantity,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: t('Količina na zalihi'),
                                suffixText: t('kom'),
                                helperText: t(
                                  'Imaš više istih komada? Svaka kupnja skida jedan s zalihe.',
                                ),
                              ),
                              validator: (v) {
                                final q = int.tryParse((v ?? '').trim());
                                if (q == null ||
                                    q < 1 ||
                                    q > Device.maxQuantity) {
                                  return t('Od 1 do {0}', [
                                    '${Device.maxQuantity}',
                                  ]);
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
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
                    const SizedBox(height: 12),
                    if (_digital)
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
                      Text(
                        t('Kako prodaješ?'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.3,
                        children: [
                          for (final m in SellMode.values)
                            _SellModeTile(
                              mode: m,
                              selected: _mode == m,
                              onTap: () => setState(() => _mode = m),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('add-submit'),
                      onPressed: _submit,
                      icon: Icon(
                        _digital || _listOnMarket
                            ? Icons.sell_outlined
                            : Icons.arrow_forward,
                      ),
                      label: Text(switch (_mode) {
                        _ when _digital => t('Objavi za Kupi odmah'),
                        SellMode.buyNow => t('Objavi za Kupi odmah'),
                        SellMode.auction => t('Dalje: aukcija'),
                        SellMode.live => t('Dalje: live'),
                        SellMode.keep => t('Spremi u Moje predmete'),
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SellModeTile extends StatelessWidget {
  const _SellModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final SellMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? LoopColors.lilac : LoopColors.surface,
    borderRadius: BorderRadius.circular(kRadius),
    child: InkWell(
      key: ValueKey('sell-${mode.name}'),
      borderRadius: BorderRadius.circular(kRadius),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(
            color: selected ? LoopColors.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(mode.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    mode.hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
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

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
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
