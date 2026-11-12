import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import 'category_style.dart';

/// An explicit "all" choice is distinct from dismissing the sheet.
class BrowseCategoryChoice {
  const BrowseCategoryChoice(this.category);
  final DeviceCategory? category;
}

Future<BrowseCategoryChoice?> pickBrowseCategory(
  BuildContext context, {
  required String title,
  required String keyPrefix,
  required Map<DeviceCategory, int> counts,
  DeviceCategory? selected,
}) => showModalBottomSheet<BrowseCategoryChoice>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (ctx) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            key: ValueKey('$keyPrefix-all'),
            leading: const Icon(Icons.apps),
            title: Text(t('Sve kategorije')),
            selected: selected == null,
            trailing: selected == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, const BrowseCategoryChoice(null)),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                for (final sec in ItemSection.active)
                  if (sec != ItemSection.digital) ...[
                    // Kategorije su razvrstane po odjeljcima.
                    Padding(
                      key: ValueKey('$keyPrefix-section-${sec.name}'),
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                      child: Row(
                        children: [
                          Icon(sec.icon, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            sec.label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final c in sec.categories)
                      ListTile(
                        key: ValueKey('$keyPrefix-${c.name}'),
                        leading: Icon(c.icon, color: c.color, size: 22),
                        title: Text(c.label),
                        selected: c == selected,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${counts[c] ?? 0}'),
                            if (c == selected) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.check, size: 18),
                            ],
                          ],
                        ),
                        onTap: () =>
                            Navigator.pop(ctx, BrowseCategoryChoice(c)),
                      ),
                  ],
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
