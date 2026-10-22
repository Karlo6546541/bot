import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../widgets/status_badge.dart';
import '../widgets/trade_actions.dart';
import 'buy_credits_screen.dart';
import 'wishlists_screen.dart';
import 'deliveries_screen.dart';
import 'digital_library_screen.dart';
import '../l10n/tr.dart';
import '../widgets/language_button.dart';
import '../models/app_user.dart';
import 'account_screens.dart';
import 'public_profile_screen.dart';
import 'shop_screens.dart';
import '../services/community_service.dart';
import '../widgets/shop_widgets.dart';
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
                  editable: !user.isGuest,
                  trailing: user.isGuest ? null : StatusBadge(status: status),
                ),
                const SizedBox(height: 12),
                if (user.isGuest)
                  const _GuestCard()
                else ...[
                  _SectionTitle(t('Moja trgovina'), Icons.storefront_outlined),
                  _ShopCard(user: user),
                ],
                _SectionTitle(
                  t('Novac i kupnje'),
                  Icons.account_balance_wallet_outlined,
                ),
                Card(
                  child: Column(
                    children: [
                      _InfoTile(
                        icon: Icons.toll,
                        label: t('Trenutno stanje'),
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
                    'Stanje je u eurima. Status: Bronze < 2000 €, Silver 2000–5000 €, Gold > 5000 € (stanje + portfolio).',
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
                  label: Text(t('Uplati novac')),
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
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('my-downloads'),
                  onPressed: () => DigitalLibraryScreen.open(context),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text(
                    t('Moje digitalne kupnje ({0})', [
                      state.myDigitalPurchases.length,
                    ]),
                  ),
                ),
                if (!user.isGuest) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('my-wishlists'),
                    onPressed: () => WishlistsScreen.open(context),
                    icon: const Icon(Icons.bookmarks_outlined),
                    label: Text(
                      t('Liste želja ({0})', [user.wishlists.length + 1]),
                    ),
                  ),
                  _SectionTitle(t('Račun'), Icons.manage_accounts_outlined),
                  _AccountCard(user: user),
                ],
                _SectionTitle(t('Postavke'), Icons.tune),
                const _SyncStatusTile(),
                SizedBox(height: 12),
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
    if (sync == null) return _tile(context, null, null);
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: sync.statusListenable,
      builder: (context, _, _) => _tile(context, sync, sync.status),
    );
  }

  Widget _tile(BuildContext context, SyncService? sync, SyncStatus? status) {
    final (emoji, title, subtitle) = switch (status) {
      SyncStatus.online when sync!.missingTables.isNotEmpty => (
        '🟠',
        t('Online baza: povezano, ali nedostaju tablice'),
        t(
          'Pokreni supabase/schema.sql u Supabase SQL Editoru pa osvježi stranicu. Do tada ostaju samo na ovom uređaju: {0}',
          [sync.missingTables.join(', ')],
        ),
      ),
      SyncStatus.online => (
        '🟢',
        t('Online baza: povezano'),
        t('Promjene se dijele sa svim testerima u stvarnom vremenu.'),
      ),
      SyncStatus.error => (
        '🟠',
        t('Online baza: nedostupna'),
        t(
          'Radiš lokalno — promjene čekaju i šalju se čim veza proradi. Ponovni pokušaj je automatski.',
        ),
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
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (status == SyncStatus.error && sync != null)
            TextButton(
              onPressed: sync.retry,
              child: Text(t('Pokušaj ponovno')),
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
                'Za kupnju, prodaju i aukcije napravi besplatan račun — besplatno je.',
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

/// Mini webshop: trgovina, ponude cijena, isticanje, ljestvica.
class _ShopCard extends ConsumerWidget {
  const _ShopCard({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final toAnswer = state.bargainsToAnswer.length;
    Widget stat(String value, String label, VoidCallback onTap, String key) =>
        Expanded(
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    return Card(
      child: Column(
        children: [
          Row(
            children: [
              stat(
                '${state.followersOf(user.id)}',
                t('pratitelja'),
                () => FollowListScreen.open(context, user.id),
                'my-followers',
              ),
              stat(
                '${state.followingListOf(user.id).length}',
                t('pratim'),
                () => FollowListScreen.open(context, user.id, following: true),
                'my-following',
              ),
              stat(
                '${state.salesCountOf(user.id)}',
                t('prodaja'),
                () => SalesListScreen.open(context, user.id),
                'my-sales',
              ),
            ],
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('my-shop'),
            leading: const Icon(Icons.storefront_outlined),
            title: Text(t('Moja trgovina: {0}', [user.shopTitle])),
            subtitle: Text(
              t('{0} oglasa · ocjena {1}', [
                '${state.listingsOf(user.id).length}',
                state.ratingOf(user.id).count == 0
                    ? '–'
                    : state.ratingOf(user.id).average.toStringAsFixed(1),
              ]),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => PublicProfileScreen.open(context, user.id),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(t('Naziv trgovine')),
            subtitle: Text(user.shopTitle),
            trailing: IconButton(
              tooltip: t('Kopiraj poveznicu trgovine'),
              icon: const Icon(Icons.ios_share),
              onPressed: () => shareLink(
                context,
                publicLink(shop: user.username),
                text: t('Pogledaj moju trgovinu {0} na LOOP-u', [
                  user.shopTitle,
                ]),
              ),
            ),
            onTap: () => showShopNameDialog(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('open-bargains'),
            leading: const Icon(Icons.price_change_outlined),
            title: Text(t('Ponude cijena')),
            subtitle: Text(
              toAnswer > 0
                  ? t('{0} čeka tvoj odgovor', ['$toAnswer'])
                  : t('Cjenkanje s kupcima i prodavateljima'),
            ),
            trailing: toAnswer > 0
                ? Badge(label: Text('$toAnswer'))
                : const Icon(Icons.chevron_right),
            onTap: () => BargainsScreen.open(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('promote'),
            leading: const Icon(Icons.campaign_outlined),
            title: Text(t('Istakni račun')),
            subtitle: Text(
              user.isPromoted
                  ? t('Istaknut do {0}', [formatDateTime(user.promotedUntil!)])
                  : t('{0} tjedno — oglasi se prikazuju više ljudi', [
                      formatCredits(CommunityService.promotionWeekly),
                    ]),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showPromoteSheet(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.emoji_events_outlined),
            title: Text(t('Top prodavatelji')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => LeaderboardScreen.open(context),
          ),
        ],
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
          if (user.blockedIds.isNotEmpty) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(
                t('Blokirani korisnici ({0})', [user.blockedIds.length]),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => BlockedUsersScreen.open(context),
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
              t('Kod za poziv: {0} — podijeli ga s prijateljima.', [
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

/// Naslov odjeljka na profilu.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.icon);
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Row(
      children: [
        Icon(icon, size: 20, color: LoopColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
      ],
    ),
  );
}
