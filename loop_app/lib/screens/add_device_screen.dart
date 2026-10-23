import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/file_store.dart';
import '../services/image_store.dart';
import '../services/trade_service.dart';
import '../services/fee.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/trade_actions.dart';
import '../l10n/tr.dart';

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
  DeviceCondition? _condition;
  ItemSection _section = ItemSection.electronics;
  DeviceCategory? _category;

  /// Novi predmet odmah ide u Market (može se isključiti).
  /// LICIT je samo za aukcije: predmet se ne objavljuje u Marketu.
  final bool _listOnMarket = false;

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
    final ok = await runWithLoading(
      context,
      () => ref
          .read(appProvider.notifier)
          .addDevice(
            name: _name.text,
            model: _model.text,
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
          ? t('Predmet je objavljen u Marketu 🏷️')
          : t('Predmet dodan u Moje predmete'),
    );
    if (ok) _saved = true;
    if (ok && mounted) Navigator.of(context).pop();
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
                      onChanged: (_) => setState(() {}),
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: t('Naziv'),
                        hintText: t('npr. iPhone 15 Pro, LEGO set, radionica…'),
                      ),
                      validator: _required,
                    ),
                    gap,
                    TextFormField(
                      controller: _model,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: t('Model / detalji'),
                        hintText: t(
                          'npr. 256GB Titanium, godina, veličina, termin…',
                        ),
                      ),
                      validator: _required,
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
                        decoration: InputDecoration(labelText: t('Stanje')),
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
                    ],
                    gap,
                    // Kategorija se bira dodirom na pločicu.
                    FormField<DeviceCategory>(
                      initialValue: _category,
                      validator: (v) =>
                          v == null ? t('Odaberi kategoriju') : null,
                      builder: (field) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('Odjeljak'),
                            style: TextStyle(color: LoopColors.textSecondary),
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
                            style: TextStyle(color: LoopColors.textSecondary),
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
                                    setState(() => _category = c);
                                    field.didChange(c);
                                  },
                                ),
                            ],
                          ),
                          if (field.hasError)
                            Padding(
                              padding: const EdgeInsets.only(top: 6, left: 12),
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
                    if (!_digital) ...[
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
                          if (q == null || q < 1 || q > Device.maxQuantity) {
                            return t('Od 1 do {0}', ['${Device.maxQuantity}']);
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    _Preview(
                      photo: _photos.isEmpty ? null : _photos.first,
                      name: _name.text,
                      model: _model.text,
                      category: _category,
                      price: _parsePrice(_price.text),
                    ),
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
                            'Digitalni proizvod odmah ide u Market i možeš ga prodati više puta. Kupac plaća cijenu + 2%, ti dobivaš punu cijenu, a kupac odmah preuzima datoteku.',
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: LoopColors.lilac,
                          borderRadius: BorderRadius.circular(kRadius),
                        ),
                        child: Text(
                          t(
                            'Predmet ide u Moje predmete. Poslije ga stavi na aukciju ili ga pokaži u liveu.',
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('add-submit'),
                      onPressed: _submit,
                      icon: Icon(
                        _digital || _listOnMarket
                            ? Icons.storefront
                            : Icons.add,
                      ),
                      label: Text(
                        _digital || _listOnMarket
                            ? t('Objavi u Marketu')
                            : t('Spremi u Moje predmete'),
                      ),
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

/// Živi pregled kako će uređaj izgledati i koliko bi donio prodajom.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.photo,
    required this.name,
    required this.model,
    required this.category,
    required this.price,
  });

  final String? photo;
  final String name;
  final String model;
  final DeviceCategory? category;
  final double? price;

  @override
  Widget build(BuildContext context) {
    final cat = category ?? DeviceCategory.other;
    final validPrice = price != null && price! > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cat.color.withValues(alpha: 0.2), LoopColors.surface],
        ),
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: cat.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (photo == null)
            CategoryAvatar(category: cat)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: SizedBox(
                width: 48,
                height: 48,
                child: LocalPhoto(
                  path: photo!,
                  cacheWidth: 144,
                  fallback: CategoryAvatar(category: cat),
                ),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('PREGLED'),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  name.trim().isEmpty ? t('Naziv predmeta') : name.trim(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  model.trim().isEmpty ? t('Model') : model.trim(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: LoopColors.textSecondary),
                ),
              ],
            ),
          ),
          if (validPrice)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatCredits(price!),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  t('prodaja: {0}', [formatCredits(sellPayout(price!))]),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Red sličica odabranih fotografija + gumbi za galeriju/kameru.
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
