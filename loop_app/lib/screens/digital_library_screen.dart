import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/empty_state.dart';
import '../widgets/trade_actions.dart';
import 'device_detail_screen.dart';

/// Kupljeni digitalni proizvodi — datoteke se mogu preuzeti bilo kad.
class DigitalLibraryScreen extends ConsumerWidget {
  const DigitalLibraryScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const DigitalLibraryScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final items = state.myDigitalPurchases;
    return Scaffold(
      appBar: AppBar(title: Text(t('Moje digitalne kupnje'))),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.download_for_offline_outlined,
              title: t('Još nemaš digitalnih kupnji'),
              message: t(
                'U Marketu odaberi odjeljak "Digitalno" — 3D modeli, softver, e-knjige, predlošci i zvukovi.',
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  children: [
                    for (final d in items)
                      Card(
                        child: ListTile(
                          leading: CategoryAvatar(
                            category: d.category,
                            size: 42,
                          ),
                          title: Text(
                            d.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            d.file == null
                                ? t('Datoteka nije dostupna')
                                : '${d.file!.name} · ${d.file!.sizeLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: LoopColors.textSecondary),
                          ),
                          trailing: IconButton.filledTonal(
                            key: ValueKey('download-${d.id}'),
                            tooltip: t('Preuzmi'),
                            onPressed: d.file == null
                                ? null
                                : () => downloadDigital(context, ref, d),
                            icon: const Icon(Icons.download),
                          ),
                          onTap: () => DeviceDetailScreen.open(context, d),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
