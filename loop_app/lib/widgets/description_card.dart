import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../l10n/tr.dart';

/// Opis predmeta; dulji tekst se skraćuje uz "Prikaži više".
class DescriptionCard extends StatefulWidget {
  const DescriptionCard({super.key, required this.text});
  final String text;

  @override
  State<DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<DescriptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final long = widget.text.length > 180;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Opis'),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              widget.text,
              maxLines: long && !_expanded ? 4 : null,
              overflow: long && !_expanded ? TextOverflow.ellipsis : null,
              style: TextStyle(height: 1.45, color: LoopColors.textPrimary),
            ),
            if (long)
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? t('Prikaži manje') : t('Prikaži više')),
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
