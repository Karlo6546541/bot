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
import '../widgets/auction_kind_style.dart';
import '../widgets/trade_actions.dart';
import 'add_device_screen.dart' show PhotoPickerRow;
import 'auction_detail_screen.dart';
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
  Duration _duration = AuctionService.durations[2].$2;
  ParcelSize _size = ParcelSize.small;

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

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!await ensureSellerInfo(context) || !mounted) return;
    final start = _num(_price.text)!;
    final floor = _kind == AuctionKind.dutch ? _num(_floor.text) : null;
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
      setState(() {
        _title.clear();
        _description.clear();
        _price.clear();
        _floor.clear();
        _photos.clear();
        _category = null;
        _categoryManual = false;
        _kind = AuctionKind.classic;
      });
      await AuctionDetailScreen.open(context, created!.id);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AuctionDetailScreen(auctionId: created!.id),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 18);
    final money = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      LengthLimitingTextInputFormatter(9),
    ];
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
          widget.embedded ? t('Prodaj') : t('Nova aukcija'),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
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
                  decoration: InputDecoration(
                    labelText: t('Naslov'),
                    hintText: t('npr. Retro sat, tenisice, kamera…'),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().length < 2 ? t('Upiši naslov') : null,
                ),
                gap,
                TextFormField(
                  key: const ValueKey('sell-description'),
                  controller: _description,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: Device.maxDescription,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: t('Opis'),
                    hintText: t('Stanje, oštećenja, što dolazi u paketu…'),
                    alignLabelWithHint: true,
                  ),
                ),
                gap,
                FormField<DeviceCategory>(
                  key: ValueKey('sell-cat-field-${_category?.name}'),
                  initialValue: _category,
                  validator: (v) => v == null ? t('Odaberi kategoriju') : null,
                  builder: (field) => InkWell(
                    key: const ValueKey('sell-category'),
                    borderRadius: BorderRadius.circular(kRadiusButton),
                    onTap: () => _chooseCategory(field),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: t('Kategorija'),
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
                gap,
                _label(t('Stanje')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in DeviceCondition.values)
                      ChoiceChip(
                        key: ValueKey('sell-condition-${c.name}'),
                        label: Text(c.label),
                        selected: _condition == c,
                        onSelected: (_) => setState(() => _condition = c),
                      ),
                  ],
                ),
                gap,
                _label(t('Vrsta aukcije')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in AuctionKind.values)
                      ChoiceChip(
                        key: ValueKey('sell-kind-${k.name}'),
                        avatar: Icon(k.icon, size: 18, color: k.color),
                        label: Text(k.label),
                        selected: _kind == k,
                        onSelected: (_) => setState(() => _kind = k),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(switch (_kind) {
                  AuctionKind.classic => t(
                    'Ponude se vide, najviša pobjeđuje.',
                  ),
                  AuctionKind.dutch => t(
                    'Cijena pada od početne do najniže; tko prvi pristane — kupuje.',
                  ),
                  AuctionKind.sealed => t(
                    'Svatko pošalje jednu skrivenu ponudu; na kraju pobjeđuje najviša i plaća svoj iznos.',
                  ),
                }, style: TextStyle(color: LoopColors.textSecondary, fontSize: 13)),
                gap,
                TextFormField(
                  key: const ValueKey('sell-price'),
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: money,
                  decoration: InputDecoration(
                    labelText: _kind == AuctionKind.dutch
                        ? t('Početna (najviša) cijena')
                        : t('Početna cijena'),
                    suffixText: t('€'),
                  ),
                  validator: (v) {
                    final p = _num(v ?? '');
                    if (p == null || p <= 0) {
                      return t('Unesi početnu cijenu veću od 0');
                    }
                    return null;
                  },
                ),
                if (_kind == AuctionKind.dutch) ...[
                  gap,
                  TextFormField(
                    key: const ValueKey('sell-floor'),
                    controller: _floor,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: money,
                    decoration: InputDecoration(
                      labelText: t('Najniža cijena'),
                      suffixText: t('€'),
                      helperText: t(
                        'Ispod ove cijene ne prodaješ — cijena ne pada niže.',
                      ),
                    ),
                    validator: (v) {
                      final f = _num(v ?? '');
                      final p = _num(_price.text);
                      if (f == null || f <= 0) {
                        return t('Unesi najnižu cijenu veću od 0');
                      }
                      if (p != null && f >= p) {
                        return t('Najniža cijena mora biti manja od početne.');
                      }
                      return null;
                    },
                  ),
                ],
                gap,
                _label(t('Trajanje')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, d) in AuctionService.durations)
                      ChoiceChip(
                        label: Text(label),
                        selected: _duration == d,
                        onSelected: (_) => setState(() => _duration = d),
                      ),
                  ],
                ),
                gap,
                _label(t('Veličina paketa')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final z in ParcelSize.values)
                      ChoiceChip(
                        key: ValueKey('sell-size-${z.name}'),
                        label: Text(z.label),
                        selected: _size == z,
                        onSelected: (_) => setState(() => _size = z),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _size.hint,
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  t(
                    'Dostavu plaća kupac. Novac ti se isplaćuje nakon što kupac primi paket. Provizija je 10 % samo od razlike iznad početne cijene.',
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
              minimumSize: const Size.fromHeight(54),
            ),
            onPressed: _submit,
            child: Text(t('Objavi aukciju')),
          ),
        ),
      ),
    );
  }
}
