import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/delivery.dart';
import '../models/shipping_profile.dart';
import '../providers/app_providers.dart';
import '../services/delivery_service.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../widgets/loop_snackbar.dart';

/// Profili dostave: popis i "Novi profil".
class ShippingProfilesScreen extends ConsumerWidget {
  const ShippingProfilesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ShippingProfilesScreen()),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appProvider).currentUser;
    final profiles = user?.shippingProfiles ?? const <ShippingProfile>[];
    return Scaffold(
      appBar: AppBar(title: Text(t('Profili dostave'))),
      body: ListView(
        key: const ValueKey('shipping-profiles'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            t(
              'Profil dostave odredi težinu i veličinu paketa. Iz njih se računa cijena dostave za kupca, a otpremnica dobije težinu i dimenzije.',
            ),
            style: TextStyle(color: LoopColors.textSecondary),
          ),
          const SizedBox(height: 14),
          if (profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Icon(
                    Icons.local_shipping_outlined,
                    size: 44,
                    color: LoopColors.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t('Još nemaš profila dostave'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            )
          else
            for (final p in profiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: LoopColors.surface,
                  borderRadius: BorderRadius.circular(kRadius),
                  child: ListTile(
                    key: ValueKey('shipping-profile-${p.id}'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kRadius),
                    ),
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('${p.summary}\n${p.parcelSize.label}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => ShippingProfileForm.open(context, profile: p),
                  ),
                ),
              ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              key: const ValueKey('shipping-profile-new'),
              onPressed: () => ShippingProfileForm.open(context),
              icon: const Icon(Icons.add),
              label: Text(t('Novi profil dostave')),
            ),
          ),
        ),
      ),
    );
  }
}

/// Obrazac profila dostave (kao Whatnot "Create Shipping Profile"): naziv,
/// težina s jedinicom, dimenzije i više predmeta u jednom paketu.
class ShippingProfileForm extends ConsumerStatefulWidget {
  const ShippingProfileForm({super.key, this.profile});
  final ShippingProfile? profile;

  /// Vraća spremljeni profil (ili `null`).
  static Future<ShippingProfile?> open(
    BuildContext context, {
    ShippingProfile? profile,
  }) => Navigator.of(context).push<ShippingProfile>(
    MaterialPageRoute(builder: (_) => ShippingProfileForm(profile: profile)),
  );

  @override
  ConsumerState<ShippingProfileForm> createState() =>
      _ShippingProfileFormState();
}

class _ShippingProfileFormState extends ConsumerState<ShippingProfileForm> {
  late final _name = TextEditingController(text: widget.profile?.name ?? '');
  late bool _kg = (widget.profile?.weightGrams ?? 1000) >= 1000;
  late final _weight = TextEditingController(
    text: widget.profile == null
        ? ''
        : _kg
        ? (widget.profile!.weightGrams / 1000)
              .toString()
              .replaceAll(RegExp(r'\.0$'), '')
              .replaceAll('.', ',')
        : '${widget.profile!.weightGrams}',
  );
  late final _l = TextEditingController(text: _dim(widget.profile?.lengthCm));
  late final _w = TextEditingController(text: _dim(widget.profile?.widthCm));
  late final _h = TextEditingController(text: _dim(widget.profile?.heightCm));
  late bool _bundle = (widget.profile?.maxItems ?? 0) > 0;
  late final _max = TextEditingController(
    text:
        '${(widget.profile?.maxItems ?? 0) > 0 ? widget.profile!.maxItems : 5}',
  );
  String? _error;

  static String _dim(int? v) => v == null || v == 0 ? '' : '$v';

  @override
  void dispose() {
    for (final c in [_name, _weight, _l, _w, _h, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _grams {
    final v = double.tryParse(_weight.text.trim().replaceAll(',', '.')) ?? 0;
    return (_kg ? v * 1000 : v).round();
  }

  int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  ShippingProfile get _preview => ShippingProfile(
    id: '',
    name: _name.text,
    weightGrams: _grams,
    lengthCm: _int(_l),
    widthCm: _int(_w),
    heightCm: _int(_h),
    maxItems: _bundle ? _int(_max) : 0,
  );

  Future<void> _save() async {
    try {
      final saved = await ref
          .read(appProvider.notifier)
          .saveShippingProfile(
            id: widget.profile?.id,
            name: _name.text,
            weightGrams: _grams,
            lengthCm: _int(_l),
            widthCm: _int(_w),
            heightCm: _int(_h),
            maxItems: _bundle ? _int(_max) : 0,
          );
      if (mounted) Navigator.of(context).pop(saved);
      showLoopSnackBar(t('Profil dostave je spremljen.'));
    } on TradeException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _delete() async {
    await ref
        .read(appProvider.notifier)
        .deleteShippingProfile(widget.profile!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    Widget dim(String key, TextEditingController c, String label) => Expanded(
      child: TextField(
        key: ValueKey(key),
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: digits,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label, suffixText: 'cm'),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.profile == null
              ? t('Novi profil dostave')
              : t('Uredi profil dostave'),
        ),
        actions: [
          if (widget.profile != null)
            IconButton(
              key: const ValueKey('shipping-profile-delete'),
              tooltip: t('Obriši'),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        key: const ValueKey('shipping-profile-form'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            key: const ValueKey('sp-name'),
            controller: _name,
            maxLength: ShippingProfile.maxName,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: t('Naziv profila'),
              hintText: t('npr. Mala kutija do 1 kg'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('Težina paketa'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('sp-weight'),
                  controller: _weight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: t('Težina')),
                ),
              ),
              const SizedBox(width: 10),
              SegmentedButton<bool>(
                key: const ValueKey('sp-unit'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('g')),
                  ButtonSegment(value: true, label: Text('kg')),
                ],
                selected: {_kg},
                onSelectionChanged: (v) => setState(() => _kg = v.first),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            t('Dimenzije paketa'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              dim('sp-l', _l, t('Dužina')),
              const SizedBox(width: 8),
              dim('sp-w', _w, t('Širina')),
              const SizedBox(width: 8),
              dim('sp-h', _h, t('Visina')),
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            child: Column(
              children: [
                SwitchListTile(
                  key: const ValueKey('sp-bundle'),
                  value: _bundle,
                  onChanged: (v) => setState(() => _bundle = v),
                  title: Text(
                    t('Ograniči broj predmeta u paketu'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    t(
                      'Kupnje iz istog livea idu u jedan paket i dostava se plaća jednom. Kad paket bude pun, kreće novi.',
                    ),
                  ),
                ),
                if (_bundle)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      key: const ValueKey('sp-max'),
                      controller: _max,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: t('Najviše predmeta u jednom paketu'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (p.weightGrams > 0)
            Container(
              key: const ValueKey('sp-preview'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: LoopColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(kRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('Veličina paketa: {0}', [p.parcelSize.label]),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t('Kurir {0} · paketomat {1}', [
                      formatCredits(
                        DeliveryService.costFor(
                          DeliveryMethod.courier,
                          p.parcelSize,
                        ),
                      ),
                      p.parcelSize.index <= ParcelSize.medium.index
                          ? formatCredits(
                              DeliveryService.costFor(
                                DeliveryMethod.parcelLocker,
                                p.parcelSize,
                              ),
                            )
                          : '—',
                    ]),
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ],
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const ValueKey('sp-error'),
              style: TextStyle(
                color: LoopColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              key: const ValueKey('sp-save'),
              onPressed: _save,
              child: Text(t('Spremi')),
            ),
          ),
        ),
      ),
    );
  }
}
