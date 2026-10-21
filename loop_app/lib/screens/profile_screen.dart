import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../widgets/status_badge.dart';
import '../widgets/trade_actions.dart';
import 'buy_credits_screen.dart';
import 'deliveries_screen.dart';
import '../l10n/tr.dart';
import '../widgets/language_button.dart';
import '../models/app_user.dart';
import 'account_screens.dart';
import 'public_profile_screen.dart';
import 'package:flutter/services.dart';
import '../widgets/user_avatar.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final user = state.currentUser;
    if (user == null) return const SizedBox.shrink();

    final status = state.statusOf(user);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProfileHeader(
                  user: user,
                  trailing: user.isGuest ? null : StatusBadge(status: status),
                ),
                const SizedBox(height: 12),
                if (user.isGuest)
                  const _GuestCard()
                else
                  _AccountCard(user: user),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      _InfoTile(
                        icon: Icons.toll,
                        label: t('Trenutni krediti'),
                        value: formatCredits(user.credits),
                      ),
                      const Divider(height: 1),
                      _InfoTile(
                        icon: Icons.workspace_premium,
                        label: t('Status'),
                        value: status.label,
                      ),
                      const Divider(height: 1),
                      _InfoTile(
                        icon: Icons.devices,
                        label: t('Predmeti u portfoliju'),
                        value: '${state.myDevices.length}',
                      ),
                      const Divider(height: 1),
                      _InfoTile(
                        icon: Icons.stacked_line_chart,
                        label: t('Ukupna vrijednost'),
                        value: formatCredits(state.totalValueOf(user)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t(
                    'LOOP krediti se ne mogu isplatiti — koriste se isključivo za kupnju predmeta unutar aplikacije. Status: Bronze < 2000, Silver 2000–5000, Gold > 5000 (krediti + portfolio).',
                  ),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => BuyCreditsScreen.open(context),
                  icon: const Icon(Icons.add_card),
                  label: Text(t('Kupi kredite')),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => DeliveriesScreen.open(context),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: Text(
                    state.myOpenDeliveries.isEmpty
                        ? t('Moje dostave')
                        : t('Moje dostave ({0} u tijeku)', [
                            state.myOpenDeliveries.length,
                          ]),
                  ),
                ),
                const SizedBox(height: 12),
                const _SyncStatusTile(),
                SizedBox(height: 20),
                Text(
                  t('Izgled'),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(t('Svijetla')),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(t('Tamna')),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(t('Sustav')),
                      icon: Icon(Icons.settings_suggest_outlined),
                    ),
                  ],
                  selected: {state.themeMode},
                  onSelectionChanged: (m) =>
                      ref.read(appProvider.notifier).setThemeMode(m.first),
                ),
                const SizedBox(height: 20),
                Text(
                  Tr.lang == AppLang.hr
                      ? 'Jezik / Language'
                      : 'Language / Jezik',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                const LanguageSelector(),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => ref.read(appProvider.notifier).logout(),
                  icon: const Icon(Icons.logout),
                  label: Text(t('Odjavi se')),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LoopColors.error,
                    side: BorderSide(color: LoopColors.error),
                  ),
                  onPressed: () => _reset(context, ref),
                  icon: const Icon(Icons.restart_alt),
                  label: Text(t('Resetiraj demo podatke')),
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
      title: t('Resetirati demo podatke?'),
      message: t(
        'Svi korisnici, predmeti i transakcije bit će obrisani i vraćeni na početne demo podatke. Bit ćeš odjavljen.',
      ),
      confirmLabel: t('Resetiraj'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    // Nakon reseta sesija je obrisana pa se ovaj ekran zamijeni loginom;
    // SnackBar ide preko globalnog messengera pa i dalje bude prikazan.
    await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).resetDemoData(),
      successMessage: t('Demo podaci resetirani'),
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

/// Je li aplikacija spojena na online bazu (Supabase) ili radi lokalno.
class _SyncStatusTile extends ConsumerWidget {
  const _SyncStatusTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final (emoji, title, subtitle) = switch (sync?.status) {
      SyncStatus.online => (
        '🟢',
        t('Online baza: povezano'),
        t('Promjene se dijele sa svim testerima u stvarnom vremenu.'),
      ),
      SyncStatus.error => (
        '🟠',
        t('Online baza: nedostupna'),
        t('Radiš lokalno. {0}', [sync?.lastError ?? '']),
      ),
      SyncStatus.connecting => ('🟡', t('Povezivanje…'), ''),
      _ => (
        '⚪',
        t('Lokalni način rada'),
        t('Podaci su samo na ovom uređaju (online baza nije postavljena).'),
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: LoopColors.surfaceHover),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gost: samo razgledavanje — poziv na registraciju.
class _GuestCard extends ConsumerWidget {
  const _GuestCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: LoopColors.sunny,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('Razgledavaš kao gost'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'Za kupnju, prodaju i aukcije napravi besplatan račun — dobivaš početne kredite.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => ref.read(appProvider.notifier).logout(),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(t('Napravi račun')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Račun: uređivanje profila, lozinka, potvrda e-maila, kod za poziv.
class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(authBackendProvider).isOnline;
    final email = ref.read(appProvider.notifier).currentEmail;
    return Card(
      child: Column(
        children: [
          if (email.isNotEmpty)
            ListTile(
              leading: Icon(
                Icons.alternate_email,
                color: LoopColors.textSecondary,
              ),
              title: Text(email),
              subtitle: Text(
                user.authProvider == 'google'
                    ? t('Prijava Googleom')
                    : t('Prijava e-mailom'),
              ),
              trailing: user.emailVerified
                  ? const VerifiedBadgeLabel()
                  : online
                  ? null
                  : TextButton(
                      onPressed: () =>
                          ref.read(appProvider.notifier).verifyEmailDemo(),
                      child: Text(t('Potvrdi (demo)')),
                    ),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(t('Uredi profil')),
            subtitle: Text(t('Fotografija, ime, korisničko ime, opis, grad')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => EditProfileScreen.open(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.public),
            title: Text(t('Moj javni profil')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => PublicProfileScreen.open(context, user.id),
          ),
          if (user.authProvider != 'google') ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(t('Promijeni lozinku')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showChangePasswordDialog(context),
            ),
          ],
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(t('Preuzmi moje podatke')),
            subtitle: Text(t('Profil, predmeti, transakcije (JSON)')),
            onTap: () => exportMyData(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.person_remove_outlined,
              color: LoopColors.error,
            ),
            title: Text(
              t('Obriši račun'),
              style: TextStyle(color: LoopColors.error),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => DeleteAccountScreen.open(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.card_giftcard),
            title: Text(t('Pozovi prijatelja')),
            subtitle: Text(
              t('Kod za poziv: {0} — oboje dobivate bonus kredite.', [
                user.handle,
              ]),
            ),
            trailing: IconButton(
              tooltip: t('Kopiraj'),
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: user.username));
                showLoopSnackBar(t('Kod kopiran'));
              },
            ),
          ),
        ],
      ),
    );
  }
}
