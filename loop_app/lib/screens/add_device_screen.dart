import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../widgets/trade_actions.dart';

/// Forma za dodavanje uređaja u portfolio. Sva polja su obavezna.
class AddDeviceScreen extends ConsumerStatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  ConsumerState<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends ConsumerState<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _model = TextEditingController();
  final _price = TextEditingController();
  DeviceCondition? _condition;
  DeviceCategory? _category;

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    _price.dispose();
    super.dispose();
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
            condition: _condition!,
            price: _parsePrice(_price.text)!,
            category: _category!,
          ),
      successMessage: 'Uređaj dodan u portfolio',
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Obavezno polje' : null;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj uređaj')),
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
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Naziv',
                        hintText: 'npr. iPhone 15 Pro',
                      ),
                      validator: _required,
                    ),
                    gap,
                    TextFormField(
                      controller: _model,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        hintText: 'npr. 256GB Titanium',
                      ),
                      validator: _required,
                    ),
                    gap,
                    DropdownButtonFormField<DeviceCondition>(
                      initialValue: _condition,
                      decoration: const InputDecoration(labelText: 'Stanje'),
                      items: [
                        for (final c in DeviceCondition.values)
                          DropdownMenuItem(value: c, child: Text(c.label)),
                      ],
                      onChanged: (c) => setState(() => _condition = c),
                      validator: (v) => v == null ? 'Odaberi stanje' : null,
                    ),
                    gap,
                    DropdownButtonFormField<DeviceCategory>(
                      initialValue: _category,
                      decoration: const InputDecoration(
                        labelText: 'Kategorija',
                      ),
                      items: [
                        for (final c in DeviceCategory.values)
                          DropdownMenuItem(value: c, child: Text(c.label)),
                      ],
                      onChanged: (c) => setState(() => _category = c),
                      validator: (v) => v == null ? 'Odaberi kategoriju' : null,
                    ),
                    gap,
                    TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Cijena',
                        suffixText: 'LC',
                      ),
                      validator: (v) {
                        final p = _parsePrice(v);
                        if (p == null) return 'Unesi ispravnu cijenu';
                        if (p <= 0) return 'Cijena mora biti veća od 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.add),
                      label: const Text('Dodaj u portfolio'),
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
