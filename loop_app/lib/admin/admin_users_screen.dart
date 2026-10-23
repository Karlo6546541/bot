import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';
import 'admin_shell.dart';
import '../l10n/tr.dart';

class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    if (s.users.isEmpty) {
      return EmptyState(icon: Icons.group_off, title: t('Nema korisnika'));
    }
    return AdminList(
      itemCount: s.users.length,
      itemBuilder: (context, i) {
        final u = s.users[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            u.email,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t('{0} · {1} predmeta', [
                          formatCredits(u.credits),
                          s.devicesOf(u.id).length,
                        ]),
                        style: TextStyle(color: LoopColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _addCredits(context, ref, u),
                      style: FilledButton.styleFrom(
                        backgroundColor: LoopColors.admin,
                        minimumSize: const Size(0, 44),
                      ),
                      icon: const Icon(Icons.add_card, size: 18),
                      label: Text(t('Dodaj sredstva')),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: t('Obriši korisnika'),
                      color: LoopColors.error,
                      onPressed: () => _delete(context, ref, u),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addCredits(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _AddCreditsDialog(user: user),
    );
    if (amount == null || !context.mounted) return;
    await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).addCredits(user.id, amount),
      successMessage: t('Dodano {0} korisniku {1}', [
        formatCredits(amount),
        user.email,
      ]),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    final ok = await confirmDialog(
      context,
      title: t('Obrisati korisnika?'),
      message: t(
        '{0} bit će obrisan. Njegovi predmeti vraćaju se u prodaju, a transakcije ostaju u povijesti.',
        [user.email],
      ),
      confirmLabel: t('Obriši'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).deleteUser(user.id),
      successMessage: t('Korisnik obrisan'),
    );
  }
}

class _AddCreditsDialog extends StatefulWidget {
  const _AddCreditsDialog({required this.user});
  final AppUser user;

  @override
  State<_AddCreditsDialog> createState() => _AddCreditsDialogState();
}

class _AddCreditsDialogState extends State<_AddCreditsDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) {
      setState(() => _error = t('Unesi pozitivan iznos'));
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Dodaj sredstva')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.user.email,
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final preset in const [100, 500, 1000])
                  ActionChip(
                    label: Text('+$preset'),
                    onPressed: () =>
                        setState(() => _controller.text = preset.toString()),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: t('Iznos'),
                suffixText: t('€'),
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Odustani')),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: LoopColors.admin,
            minimumSize: const Size(0, 44),
          ),
          child: Text(t('Dodaj')),
        ),
      ],
    );
  }
}
