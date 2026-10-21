import 'package:flutter/material.dart';

import '../models/delivery.dart';
import '../theme/app_theme.dart';
import 'formatters.dart';

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
  late DeliveryMethod _method = widget.methods.first;
  late final _address = TextEditingController(text: widget.savedAddress);
  String _locker = kDemoLockers.first;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  String? get _destination => _method.needsAddress
      ? _address.text
      : _method.needsLocker
      ? _locker
      : null;

  void _emit() {
    if (mounted) widget.onChanged(DeliveryChoice(_method, _destination));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in widget.methods)
          Padding(
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
                        m.cost == 0 ? 'Besplatno' : formatCredits(m.cost),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_method.needsAddress) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'Adresa za dostavu',
              hintText: 'npr. Ilica 1, 10000 Zagreb',
              prefixIcon: Icon(Icons.home_outlined),
            ),
            onChanged: (_) => _emit(),
          ),
        ],
        if (_method.needsLocker) ...[
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: _locker,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Paketomat',
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
