import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';
import 'admin_shell.dart';
import '../l10n/tr.dart';

class AdminDevicesScreen extends ConsumerWidget {
  const AdminDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    if (s.devices.isEmpty) {
      return EmptyState(icon: Icons.devices_other, title: t('Nema predmeta'));
    }
    return AdminList(
      itemCount: s.devices.length,
      itemBuilder: (context, i) {
        final d = s.devices[i];
        final owner = s.userLabel(d.ownerId);
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: CategoryAvatar(category: d.category, size: 40),
            title: Text(
              '${d.name} · ${d.model}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              t('{0} · {1}\nVlasnik: {2}', [
                d.condition.label,
                formatCredits(d.price),
                owner,
              ]),
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: t('Obriši predmet'),
              color: LoopColors.error,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref, d),
            ),
          ),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Device d) async {
    final ok = await confirmDialog(
      context,
      title: t('Obrisati predmet?'),
      message: t('{0} ({1}) bit će trajno uklonjen.', [d.name, d.model]),
      confirmLabel: t('Obriši'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).deleteDevice(d.id),
      successMessage: t('Predmet obrisan'),
    );
  }
}
