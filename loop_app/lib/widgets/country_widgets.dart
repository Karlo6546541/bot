import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/country.dart';

/// Odabir države (zastavica + ime).
class CountryField extends StatelessWidget {
  const CountryField({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: const ValueKey('country-field'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: t('Država'),
      helperText: t('Za lokalne dostavljače i prikaz uz oglase'),
      prefixIcon: const Icon(Icons.public),
    ),
    items: [
      for (final c in kCountries)
        DropdownMenuItem(value: c.code, child: Text(c.label)),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}

/// Mala oznaka države: zastavica (i kod ako [withCode]).
class CountryBadge extends StatelessWidget {
  const CountryBadge({
    super.key,
    required this.code,
    this.withName = false,
    this.style,
  });

  final String? code;
  final bool withName;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = countryOf(code);
    return Tooltip(
      message: c.name,
      child: Text(
        withName ? c.label : c.flag,
        style: style ?? const TextStyle(fontSize: 13),
      ),
    );
  }
}
