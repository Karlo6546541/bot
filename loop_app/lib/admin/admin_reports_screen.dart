import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/report.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';
import 'admin_shell.dart';

/// Prijave oglasa i korisnika: admin ih rješava (briše sadržaj) ili odbacuje.
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  bool _showClosed = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final list = _showClosed ? s.reports : s.openReports;
    final header = Row(
      children: [
        Expanded(
          child: Text(
            t('Otvorene prijave: {0}', [s.openReports.length]),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        FilterChip(
          label: Text(t('Prikaži i zatvorene')),
          selected: _showClosed,
          onSelected: (v) => setState(() => _showClosed = v),
        ),
      ],
    );
    if (list.isEmpty) {
      return Column(
        children: [
          Padding(padding: const EdgeInsets.all(16), child: header),
          Expanded(
            child: EmptyState(
              icon: Icons.verified_user_outlined,
              title: t('Nema prijava'),
            ),
          ),
        ],
      );
    }
    return AdminList(
      header: header,
      itemCount: list.length,
      itemBuilder: (context, i) => _ReportCard(report: list[i]),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.report});
  final Report report;

  Future<void> _removeTarget(BuildContext context, WidgetRef ref) async {
    final r = report;
    final ok = await confirmDialog(
      context,
      title: r.isDevice ? t('Obrisati predmet?') : t('Obrisati korisnika?'),
      message: t('"{0}" bit će uklonjen, a prijava označena kao riješena.', [
        r.targetLabel,
      ]),
      confirmLabel: t('Obriši'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final c = ref.read(appProvider.notifier);
    await runWithLoading(context, () async {
      final exists = r.isDevice
          ? ref.read(appProvider).deviceById(r.targetId) != null
          : ref.read(appProvider).userById(r.targetId) != null;
      if (exists) {
        if (r.isDevice) {
          // Vlasnik dobiva obrazloženje i mogućnost žalbe (DSA).
          await c.notifyRemoval(r.id);
          await c.deleteDevice(r.targetId);
        } else {
          await c.deleteUser(r.targetId);
        }
      }
      await c.closeReport(r.id, ReportStatus.resolved);
    }, successMessage: t('Prijava riješena'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = report;
    final c = ref.read(appProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  r.isAppeal
                      ? Icons.gavel
                      : r.isDevice
                      ? Icons.sell_outlined
                      : Icons.person_outline,
                  color: LoopColors.admin,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.targetLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (!r.isOpen)
                  Text(
                    r.status == ReportStatus.resolved
                        ? t('Riješeno')
                        : t('Odbačeno'),
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t('{0} · prijavio {1} · {2}', [
                r.reason.label,
                r.reporterLabel,
                formatDateTime(r.createdAt),
              ]),
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            if (r.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('"${r.note}"'),
            ],
            if (r.isOpen) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!r.isAppeal)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: LoopColors.error,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _removeTarget(context, ref),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(
                        r.isDevice
                            ? t('Obriši predmet')
                            : t('Obriši korisnika'),
                      ),
                    ),
                  OutlinedButton(
                    onPressed: () => c.closeReport(r.id, ReportStatus.resolved),
                    child: Text(t('Riješeno')),
                  ),
                  TextButton(
                    onPressed: () =>
                        c.closeReport(r.id, ReportStatus.dismissed),
                    child: Text(t('Odbaci')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
