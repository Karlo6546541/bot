import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../widgets/empty_state.dart';
import 'auctions_home_screen.dart' show BuyNowTile;

/// Oglasnik: spremljeni oglasi (favoriti), kao mreža oglasa.
class SavedListingsScreen extends ConsumerWidget {
  const SavedListingsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SavedListingsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final saved = [
      for (final id in s.currentUser?.favorites ?? const <String>[])
        ?s.deviceById(id),
    ];
    final width = MediaQuery.sizeOf(context).width.clamp(0, 900).toDouble();
    final columns = width >= 700 ? 3 : 2;
    return Scaffold(
      key: const ValueKey('saved-listings'),
      appBar: AppBar(title: Text(t('Spremljeni oglasi'))),
      body: saved.isEmpty
          ? EmptyState(
              icon: Icons.favorite_border,
              title: t('Još nemaš spremljenih oglasa'),
              message: t('Dodirni srce na oglasu da ga spremiš.'),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent:
                    (width - 32 - (columns - 1) * 12) / columns +
                    132 * MediaQuery.textScalerOf(context).scale(1),
              ),
              itemCount: saved.length,
              itemBuilder: (_, i) => BuyNowTile(
                key: ValueKey('saved-item-${saved[i].id}'),
                device: saved[i],
              ),
            ),
    );
  }
}
