import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../widgets/status_badge.dart';
import '../widgets/trade_actions.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final user = state.currentUser;
    if (user == null) return const SizedBox.shrink();

    final status = state.statusOf(user);
    final initial = user.name.isEmpty ? '?' : user.name[0].toUpperCase();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: LoopColors.accent.withValues(
                            alpha: 0.18,
                          ),
                          child: Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: LoopColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                user.email,
                                style: const TextStyle(
                                  color: LoopColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              StatusBadge(status: status),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      _InfoTile(
                        icon: Icons.toll,
                        label: 'Trenutni krediti',
                        value: formatCredits(user.credits),
                      ),
                      const Divider(height: 1),
                      _InfoTile(
                        icon: Icons.workspace_premium,
                        label: 'Status',
                        value: status.label,
                      ),
                      const Divider(height: 1),
                      _InfoTile(
                        icon: Icons.devices,
                        label: 'Predmeti u portfoliju',
                        value: '${state.myDevices.length}',
                      ),
                      const Divider(height: 1),
                      _InfoTile(
                        icon: Icons.stacked_line_chart,
                        label: 'Ukupna vrijednost',
                        value: formatCredits(state.totalValueOf(user)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'LOOP krediti se ne mogu isplatiti — koriste se isključivo '
                  'za kupnju predmeta unutar aplikacije. Status: Bronze < 2000, '
                  'Silver 2000–5000, Gold > 5000 (krediti + portfolio).',
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => ref.read(appProvider.notifier).logout(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Odjavi se'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LoopColors.error,
                    side: const BorderSide(color: LoopColors.error),
                  ),
                  onPressed: () => _reset(context, ref),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Resetiraj demo podatke'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Resetirati demo podatke?',
      message:
          'Svi korisnici, predmeti i transakcije bit će obrisani i '
          'vraćeni na početne demo podatke. Bit ćeš odjavljen.',
      confirmLabel: 'Resetiraj',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    // Nakon reseta sesija je obrisana pa se ovaj ekran zamijeni loginom;
    // SnackBar ide preko globalnog messengera pa i dalje bude prikazan.
    await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).resetDemoData(),
      successMessage: 'Demo podaci resetirani',
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: LoopColors.textSecondary),
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }
}
