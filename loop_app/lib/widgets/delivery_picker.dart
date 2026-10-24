import 'package:flutter/material.dart';

import '../models/delivery.dart';
import '../services/boxnow/boxnow.dart';
import 'loop_snackbar.dart';
import '../theme/app_theme.dart';
import 'formatters.dart';
import '../l10n/tr.dart';

/// Odabrana dostava (način + odredište).
class DeliveryChoice {
  const DeliveryChoice(this.method, this.destination);
  final DeliveryMethod method;
  final String? destination;
}

IconData deliveryIcon(DeliveryMethod m) => switch (m) {
  DeliveryMethod.pickup => Icons.storefront_outlined,
  DeliveryMethod.parcelLocker => Icons.inventory_2_outlined,
  DeliveryMethod.courier => Icons.local_shipping_outlined,
  DeliveryMethod.express => Icons.bolt,
  DeliveryMethod.digital => Icons.alternate_email,
};

/// Popis načina dostave + polje za adresu ili odabir paketomata.
/// Javlja promjene preko [onChanged].
class DeliveryPicker extends StatefulWidget {
  const DeliveryPicker({
    super.key,
    required this.methods,
    required this.onChanged,
    this.savedAddress,
  });

  final List<DeliveryMethod> methods;
  final ValueChanged<DeliveryChoice> onChanged;

  /// Zadnja korištena adresa korisnika (predlaže se).
  final String? savedAddress;

  @override
  State<DeliveryPicker> createState() => _DeliveryPickerState();
}

class _DeliveryPickerState extends State<DeliveryPicker> {
  /// Ništa nije unaprijed odabrano — kupac sam bira način dostave (osim
  /// kad postoji samo jedan, npr. digitalna dostava).
  late DeliveryMethod? _method = widget.methods.length == 1
      ? widget.methods.first
      : null;

  @override
  void initState() {
    super.initState();
    if (_method != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
    }
  }

  late final _address = TextEditingController(text: widget.savedAddress);
  String _locker = kDemoLockers.first;

  /// BOX NOW karta (web); ako se ne učita, bira se s popisa.
  BoxNowLocker? _boxNow;
  bool _mapFailed = !BoxNow.available;

  /// Karta se otvara preko aplikacije; ako je kupac zatvori bez odabira,
  /// gumb ostaje dostupan (novo otvaranje zamjenjuje staro).
  Future<void> _pickOnMap() async {
    final r = await BoxNow.pick();
    if (!mounted) return;
    setState(() {
      switch (r) {
        case BoxNowPicked(:final locker):
          _boxNow = locker;
        case BoxNowUnavailable():
          // Karta se nije učitala — bira se s popisa.
          _mapFailed = true;
          showLoopSnackBar(
            t('BOX NOW karta se nije otvorila — odaberi paketomat s popisa.'),
          );
        case BoxNowClosed():
          break;
      }
    });
    _emit();
  }

  /// Prikazani su i rjeđi načini (ekspres, osobno preuzimanje).
  bool _all = false;

  /// Odabran je način koji je inače skriven iza "Više načina dostave".
  bool get _hiddenSelected {
    final m = _method;
    return m != null && widget.methods.indexOf(m) >= 2;
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  String? get _destination => switch (_method) {
    final m? when m.needsAddress => _address.text,
    final m? when m.needsLocker => _mapFailed ? _locker : _boxNow?.destination,
    _ => null,
  };

  void _emit() {
    final m = _method;
    if (mounted && m != null) widget.onChanged(DeliveryChoice(m, _destination));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in widget.methods.take(
          _all || _hiddenSelected ? widget.methods.length : 2,
        ))
          Padding(
            key: ValueKey('delivery-${m.name}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: LoopColors.surface,
              borderRadius: BorderRadius.circular(kRadius),
              child: InkWell(
                borderRadius: BorderRadius.circular(kRadius),
                onTap: () {
                  setState(() => _method = m);
                  _emit();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kRadius),
                    border: Border.all(
                      color: _method == m ? accent : LoopColors.surfaceHover,
                      width: _method == m ? 2 : 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: LoopColors.mint,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(deliveryIcon(m)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              m.subtitle,
                              style: TextStyle(
                                color: LoopColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        m.cost == 0 ? t('Besplatno') : formatCredits(m.cost),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (!_all && widget.methods.length > 2 && !_hiddenSelected)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('delivery-more'),
              onPressed: () => setState(() => _all = true),
              child: Text(t('Više načina dostave')),
            ),
          ),
        if (_method?.needsAddress ?? false) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _address,
            decoration: InputDecoration(
              labelText: t('Adresa za dostavu'),
              hintText: t('npr. Ilica 1, 10000 Zagreb'),
              prefixIcon: Icon(Icons.home_outlined),
            ),
            onChanged: (_) => _emit(),
          ),
        ],
        if ((_method?.needsLocker ?? false) && !_mapFailed) ...[
          const SizedBox(height: 4),
          _BoxNowTile(locker: _boxNow, onPick: _pickOnMap),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('boxnow-list'),
              onPressed: () {
                setState(() => _mapFailed = true);
                _emit();
              },
              child: Text(t('Karta ne radi? Odaberi s popisa')),
            ),
          ),
        ],
        if ((_method?.needsLocker ?? false) && _mapFailed) ...[
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: _locker,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: t('Paketomat'),
              prefixIcon: Icon(Icons.place_outlined),
            ),
            items: [
              for (final l in kDemoLockers)
                DropdownMenuItem(value: l, child: Text(l)),
            ],
            onChanged: (v) {
              setState(() => _locker = v!);
              _emit();
            },
          ),
        ],
      ],
    );
  }
}

/// Odabrani BOX NOW paketomat + gumb koji otvara kartu.
class _BoxNowTile extends StatelessWidget {
  const _BoxNowTile({required this.locker, required this.onPick});

  final BoxNowLocker? locker;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l = locker;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: LoopColors.surfaceHover, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF6CD04E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.place, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l == null ? t('Paketomat nije odabran') : 'BOX NOW #${l.id}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  l == null
                      ? t('Odaberi najbliži BOX NOW paketomat na karti.')
                      : [
                          if (l.name.isNotEmpty) l.name,
                          l.address,
                          if (l.postalCode.isNotEmpty) l.postalCode,
                        ].join(', '),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            key: const ValueKey('boxnow-pick'),
            onPressed: onPick,
            child: Text(l == null ? t('Karta') : t('Promijeni')),
          ),
        ],
      ),
    );
  }
}
