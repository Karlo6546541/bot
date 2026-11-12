import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/language_button.dart';
import '../widgets/trade_actions.dart';
import '../widgets/user_avatar.dart';
import 'legal_screen.dart';
import 'login_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'public_profile_screen.dart';
import 'search_screen.dart';
import 'wishlists_screen.dart';

/// Avatar u gornjoj traci: otvara izbornik računa (kao Whatnot).
class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appProvider.select((s) => s.currentUser));
    return IconButton(
      key: const ValueKey('account-menu-button'),
      tooltip: t('Izbornik'),
      onPressed: () => AccountMenuScreen.open(context),
      icon: user == null || user.isGuest
          ? const Icon(Icons.account_circle_outlined, size: 30)
          : UserAvatar(user: user, size: 30),
    );
  }
}

/// Izbornik računa preko cijelog ekrana: pretraga, Početna, Kategorije,
/// Poruke, Kupujem (Spremljeno, Ponude, Kupnje, Novčanik, Adrese), Račun,
/// Pomoć i pravno te jezik.
class AccountMenuScreen extends ConsumerWidget {
  const AccountMenuScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const AccountMenuScreen(),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final user = s.currentUser;
    final guest = user == null || user.isGuest;

    /// Zatvara izbornik, pa izvršava radnju.
    void go(VoidCallback action) {
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) => action());
    }

    void tab(int i) => go(() => ref.read(homeTabProvider.notifier).select(i));

    Widget row(String key, IconData icon, String label, VoidCallback onTap) =>
        ListTile(
          key: ValueKey(key),
          minTileHeight: 52,
          leading: Icon(icon, color: LoopColors.textPrimary),
          title: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          trailing: Icon(Icons.chevron_right, color: LoopColors.textSecondary),
          onTap: onTap,
        );

    Widget head(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          t('Izbornik'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton.filledTonal(
            key: const ValueKey('account-menu-close'),
            tooltip: t('Zatvori'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            key: const ValueKey('account-menu'),
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: InkWell(
                  key: const ValueKey('account-menu-search'),
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => go(() => SearchScreen.open(context)),
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: LoopColors.surfaceHover,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, color: LoopColors.textSecondary),
                        const SizedBox(width: 10),
                        Text(
                          t('Traži na Subhastu'),
                          style: TextStyle(color: LoopColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              row('menu-home', Icons.home_outlined, t('Početna'), () => tab(0)),
              row(
                'menu-browse',
                Icons.grid_view_outlined,
                t('Kategorije'),
                () => tab(1),
              ),
              if (!guest)
                row(
                  'menu-inbox',
                  Icons.chat_bubble_outline,
                  t('Poruke'),
                  () => go(() => MessagesScreen.open(context)),
                ),
              if (!guest) ...[
                head(t('Kupujem')),
                row(
                  'menu-saved',
                  Icons.bookmark_border,
                  t('Spremljeno'),
                  () => go(() => WishlistsScreen.open(context)),
                ),
                row(
                  'menu-offers',
                  Icons.local_offer_outlined,
                  t('Ponude'),
                  () => go(() => MessagesScreen.open(context)),
                ),
                row(
                  'menu-purchases',
                  Icons.receipt_long_outlined,
                  t('Kupnje'),
                  () => tab(2),
                ),
                row(
                  'menu-wallet',
                  Icons.credit_card,
                  t('Novčanik'),
                  () => go(() => ensureCheckout(context, ref, force: true)),
                ),
                row(
                  'menu-addresses',
                  Icons.location_on_outlined,
                  t('Adrese'),
                  () => go(() => ensureCheckout(context, ref, force: true)),
                ),
                head(t('Račun')),
                ListTile(
                  key: const ValueKey('menu-profile'),
                  minTileHeight: 64,
                  leading: UserAvatar(user: user, size: 40),
                  title: Text(
                    user.name.isNotEmpty ? user.name : user.handle,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(user.handle),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: LoopColors.textSecondary,
                  ),
                  onTap: () =>
                      go(() => PublicProfileScreen.open(context, user.id)),
                ),
                row(
                  'menu-settings',
                  Icons.settings_outlined,
                  t('Postavke'),
                  () {
                    go(() {
                      ref.read(homeTabProvider.notifier).select(3);
                      ref.read(profileSettingsProvider.notifier).setOpen(true);
                    });
                  },
                ),
              ] else ...[
                head(t('Račun')),
                row(
                  'menu-login',
                  Icons.login,
                  t('Prijava / registracija'),
                  () => go(() => LoginScreen.open(context)),
                ),
              ],
              head(t('Pomoć i pravno')),
              row(
                'menu-legal',
                Icons.gavel_outlined,
                t('Uvjeti i pravila'),
                () => go(() => LegalListScreen.open(context)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('Jezik'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const LanguageButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
