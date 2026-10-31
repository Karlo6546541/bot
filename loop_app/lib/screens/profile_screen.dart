import '../config/features.dart';
import 'package:flutter/material.dart';

import '../config/backend_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/trade_actions.dart';
import 'activity_screen.dart';
import 'legal_screen.dart';
import 'login_screen.dart';
import 'seller_screens.dart';
import '../l10n/tr.dart';
import '../widgets/language_button.dart';
import '../models/app_user.dart';
import 'account_screens.dart';
import 'public_profile_screen.dart';
import 'shop_screens.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/user_avatar.dart';
import '../models/device.dart';
import '../widgets/item_image.dart';
import '../widgets/formatters.dart';
import '../widgets/create_sheet.dart';
import 'device_detail_screen.dart';
import 'live_screens.dart';

/// Profile content is separate from account settings.
final profileSettingsProvider =
    NotifierProvider<ProfileSettingsController, bool>(
      ProfileSettingsController.new,
    );

class ProfileSettingsController extends Notifier<bool> {
  @override
  bool build() => false;
  void setOpen(bool value) => state = value;
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _liked = false;

  @override
  Widget build(BuildContext context) {
    if (ref.watch(profileSettingsProvider)) return const _ProfileSettingsView();
    final state = ref.watch(appProvider);
    final user = state.currentUser;
    if (user == null) return const SizedBox.shrink();
    final items = _liked
        ? state.devices.where((d) => state.isFavorite(d.id)).toList()
        : state.myDevices;
    final lives = state.activeLives
        .where((e) => e.$1.hostId == user.id)
        .toList();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: CustomScrollView(
          key: const ValueKey('account-profile'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (user.isGuest) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: _settingsButton(),
                      ),
                      const _GuestCard(),
                    ] else ...[
                      ProfileHeader(
                        user: user,
                        editable: true,
                        compact: true,
                        trailing: _settingsButton(),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          _stat(
                            '${state.followersOf(user.id)}',
                            t('pratitelja'),
                            'my-followers',
                            () => FollowListScreen.open(context, user.id),
                          ),
                          _stat(
                            '${state.followingListOf(user.id).length}',
                            t('pratim'),
                            'my-following',
                            () => FollowListScreen.open(
                              context,
                              user.id,
                              following: true,
                            ),
                          ),
                          _stat(
                            '${state.salesCountOf(user.id)}',
                            t('prodaja'),
                            'my-sales',
                            () => SalesListScreen.open(context, user.id),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const ValueKey('profile-edit'),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: LoopColors.surfaceHover,
                                side: BorderSide.none,
                                minimumSize: const Size(0, 44),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: () => EditProfileScreen.open(context),
                              icon: const Icon(Icons.edit_outlined, size: 17),
                              label: Text(t('Uredi profil')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              key: const ValueKey('profile-create'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: () {
                                setState(() => _liked = false);
                                showCreateSheet(context);
                              },
                              icon: const Icon(Icons.add, size: 19),
                              label: Text(t('Dodaj objavu')),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _tab(
                            false,
                            Icons.grid_on_outlined,
                            t('Objave'),
                          ),
                        ),
                        Expanded(
                          child: _tab(
                            true,
                            Icons.favorite_border,
                            t('Sviđa mi se'),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    if (!_liked && !user.isGuest)
                      for (final (show, live) in lives)
                        ListTile(
                          key: ValueKey('account-live-${show.id}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          leading: const Icon(Icons.videocam_outlined),
                          title: Text(
                            show.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            live.isLive ? t('Uživo sada') : t('Uskoro'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => LiveRoomScreen.open(context, show.id),
                        ),
                  ],
                ),
              ),
            ),
            if (items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Icon(
                        _liked ? Icons.favorite_border : Icons.grid_on_outlined,
                        size: 36,
                        color: LoopColors.textSecondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _liked
                            ? t('Još nema lajkanih oglasa.')
                            : t('Tvoje objave prikazat će se ovdje.'),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) => SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: constraints.crossAxisExtent >= 600
                          ? 3
                          : 2,
                      mainAxisExtent:
                          constraints.crossAxisExtent /
                              (constraints.crossAxisExtent >= 600 ? 3 : 2) +
                          90,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _AccountPostTile(
                        device: items[i],
                        mine: items[i].ownerId == user.id,
                        likedSection: _liked,
                      ),
                      childCount: items.length,
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _settingsButton() => IconButton(
    key: const ValueKey('profile-settings'),
    tooltip: t('Postavke'),
    onPressed: () => ref.read(profileSettingsProvider.notifier).setOpen(true),
    icon: const Icon(Icons.settings_outlined),
  );

  /// Broj i naziv u istom retku ("12 pratitelja"), kao Whatnot.
  Widget _stat(String value, String label, String key, VoidCallback onTap) =>
      TextButton(
        key: ValueKey(key),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: onTap,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  color: LoopColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(
                text: ' $label',
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );

  /// Tekstualni tab s podcrtom (kao Whatnot).
  Widget _tab(bool liked, IconData icon, String label) {
    final on = _liked == liked;
    return InkWell(
      key: ValueKey(liked ? 'profile-liked-tab' : 'profile-posts-tab'),
      onTap: () => setState(() => _liked = liked),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? LoopColors.textPrimary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 16,
            fontWeight: on ? FontWeight.w800 : FontWeight.w500,
            color: on ? LoopColors.textPrimary : LoopColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _AccountPostTile extends ConsumerWidget {
  const _AccountPostTile({
    required this.device,
    required this.mine,
    required this.likedSection,
  });
  final Device device;
  final bool mine;
  final bool likedSection;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: t('Obrisati predmet?'),
      message: t(
        '"{0}" bit će trajno uklonjen iz tvog portfolija{1}. Ovo se ne može poništiti.',
        [device.name, device.isListed ? t(' i iz prodaje') : ''],
      ),
      confirmLabel: t('Obriši'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).deleteMyDevice(device.id),
      successMessage: t('Predmet obrisan'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final d = device;
    final auction = state.activeAuctions
        .where((a) => a.deviceId == d.id)
        .firstOrNull;
    // Kartica: lagani rub i sjena da se vidi okvir; slika ispunjava
    // cijeli kvadrat (bez praznih rubova).
    return Material(
      key: ValueKey('account-post-${d.id}'),
      color: LoopColors.surface,
      elevation: 0,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: LoopColors.textSecondary.withValues(alpha: 0.14),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => DeviceDetailScreen.open(context, d),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  d.imagePaths.isEmpty
                      ? ItemIllustration(category: d.category)
                      : LocalPhoto(
                          path: d.imagePaths.first,
                          fit: BoxFit.cover,
                          cacheWidth: 720,
                          fallback: ItemIllustration(category: d.category),
                        ),
                  // Okrugli prozirni gumb (srce ili izbornik) kao na
                  // Instagramu — ne prekriva sliku.
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.32),
                        shape: BoxShape.circle,
                      ),
                      child: likedSection
                          ? IconButton(
                              key: ValueKey('profile-unlike-${d.id}'),
                              tooltip: t('Ukloni iz favorita'),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  toggleFavorite(ref, d, context: context),
                              icon: const Icon(
                                Icons.favorite_rounded,
                                color: Color(0xFFFF4D6D),
                                size: 18,
                                shadows: [
                                  Shadow(blurRadius: 4, color: Colors.black38),
                                ],
                              ),
                            )
                          : PopupMenuButton<String>(
                              key: ValueKey('profile-post-menu-${d.id}'),
                              tooltip: t('Detalji'),
                              iconSize: 18,
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.more_horiz,
                                color: Colors.white,
                              ),
                              onSelected: (value) async {
                                if (value == 'delete') {
                                  await _delete(context, ref);
                                } else {
                                  await DeviceDetailScreen.open(context, d);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'details',
                                  child: Text(t('Detalji')),
                                ),
                                if (mine)
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(t('Obriši predmet')),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 0),
              child: Text(
                '${d.name} ${d.model}'.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 4, 9, 0),
              child: Text(
                formatCredits(
                  auction?.currentPrice ??
                      (mine ? d.askPrice : state.priceForMe(d)),
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 2, 9, 0),
              child: Text(
                auction != null
                    ? t('Aukcija')
                    : d.isListed && kBuyNowEnabled
                    ? t('Kupi odmah')
                    : t('Nije na prodaji'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSettingsView extends ConsumerWidget {
  const _ProfileSettingsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final user = state.currentUser;
    if (user == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const ValueKey('profile-settings-close'),
                      tooltip: t('Natrag'),
                      onPressed: () => ref
                          .read(profileSettingsProvider.notifier)
                          .setOpen(false),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Text(
                      t('Postavke'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                // Račun i postavke odvojeni su od objava na profilu.
                if (user.isGuest)
                  const _GuestCard()
                else ...[
                  _SectionTitle(t('Račun'), Icons.manage_accounts_outlined),
                  _ShopCard(user: user),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        _NavTile(
                          key: const ValueKey('profile-checkout'),
                          icon: Icons.credit_card,
                          title: user.checkoutReady
                              ? '${user.paymentCard} · ${user.address}'
                              : t('Dodaj karticu i adresu'),
                          onTap: () =>
                              ensureCheckout(context, ref, force: true),
                        ),
                        const Divider(height: 1),
                        _NavTile(
                          key: const ValueKey('open-activity'),
                          icon: Icons.receipt_long_outlined,
                          title: t('Povijest transakcija'),
                          onTap: () => ActivityPage.open(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _AccountCard(user: user),
                ],
                _SectionTitle(t('Postavke'), Icons.tune),
                Card(
                  child: _NavTile(
                    key: const ValueKey('open-legal'),
                    icon: Icons.description_outlined,
                    title: t('Uvjeti, privatnost i impresum'),
                    onTap: () => LegalListScreen.open(context),
                  ),
                ),
                // Gost ne sprema ništa — stanje sinkronizacije ga ne zanima.
                if (!user.isGuest) const _SyncStatusTile(),
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
                if (!user.isGuest) ...[
                  OutlinedButton.icon(
                    onPressed: () {
                      ref.read(profileSettingsProvider.notifier).setOpen(false);
                      ref.read(appProvider.notifier).logout();
                    },
                    icon: const Icon(Icons.logout),
                    label: Text(t('Odjavi se')),
                  ),
                  const SizedBox(height: 12),
                ],
                // Reset briše samo lokalne demo podatke; uz online bazu
                // ga nema, da nitko ne može prebrisati zajedničke podatke.
                if (!BackendConfig.isOnline)
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

/// Redak koji otvara drugi ekran.
class _NavTile extends StatelessWidget {
  const _NavTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: LoopColors.textSecondary),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

/// Je li aplikacija spojena na online bazu (Supabase) ili radi lokalno.
class _SyncStatusTile extends ConsumerWidget {
  const _SyncStatusTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    if (sync == null) return _tile(context, null, null);
    return ListenableBuilder(
      listenable: Listenable.merge([
        sync.statusListenable,
        sync.pendingListenable,
      ]),
      builder: (context, _) => _tile(context, sync, sync.status),
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
      SyncStatus.online when sync!.pendingCount > 0 => (
        '🟡',
        t('Online baza: {0} promjena čeka slanje', [sync.pendingCount]),
        sync.lastError == null
            ? t('Šalje se automatski…')
            : t('Zadnja greška: {0}', [sync.lastError!]),
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
            TextButton(onPressed: sync.retry, child: Text(t('Pokušaj ponovno')))
          else if (status == SyncStatus.online &&
              sync != null &&
              sync.pendingCount > 0)
            TextButton(
              key: const ValueKey('sync-flush'),
              onPressed: sync.flushNow,
              child: Text(t('Pošalji sada')),
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
              key: const ValueKey('guest-signup'),
              onPressed: () => LoginScreen.open(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(t('Prijava / registracija')),
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
    return Card(
      child: Column(
        children: [
          _NavTile(
            key: const ValueKey('seller-info'),
            icon: Icons.badge_outlined,
            title: t('Podaci prodavatelja'),
            subtitle: user.seller == null
                ? t('Nije ispunjeno — potrebno za isplatu zarade')
                : '${user.seller!.isBusiness ? user.seller!.tradeName : t('Fizička osoba')} · ${user.seller!.maskedIban}',
            onTap: () => SellerInfoScreen.open(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('my-shop'),
            leading: const Icon(Icons.storefront_outlined),
            title: Text(t('Moja trgovina: {0}', [user.shopTitle])),
            subtitle: Text(
              t('{0} aukcija · ocjena {1}', [
                '${state.auctions.where((a) => a.sellerId == user.id && a.isActive).length}',
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
                text: t('Pogledaj moju trgovinu {0} na Subhastu', [
                  user.shopTitle,
                ]),
              ),
            ),
            onTap: () => showShopNameDialog(context, ref),
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
