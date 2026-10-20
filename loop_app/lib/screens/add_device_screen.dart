import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/formatters.dart';
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
                      onChanged: (_) => setState(() {}),
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
                      onChanged: (_) => setState(() {}),
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
                      validator: (v) => v == null ? 'Odaberi stanje' : null,
                    ),
                    gap,
                    // Kategorija se bira dodirom na pločicu.
                    FormField<DeviceCategory>(
                      initialValue: _category,
                      validator: (v) => v == null ? 'Odaberi kategoriju' : null,
                      builder: (field) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Kategorija',
                            style: TextStyle(color: LoopColors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in DeviceCategory.values)
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
                                style: const TextStyle(
                                  color: LoopColors.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
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
                    _Preview(
                      name: _name.text,
                      model: _model.text,
                      category: _category,
                      price: _parsePrice(_price.text),
                    ),
                    const SizedBox(height: 16),
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
    required this.name,
    required this.model,
    required this.category,
    required this.price,
  });

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
          CategoryAvatar(category: cat),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PREGLED',
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  name.trim().isEmpty ? 'Naziv uređaja' : name.trim(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  model.trim().isEmpty ? 'Model' : model.trim(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: LoopColors.textSecondary),
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
                  'prodaja: ${formatCredits(sellPayout(price!))}',
                  style: const TextStyle(
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
