import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

import '../widgets/adaptive_shell.dart';
import '../widgets/create_sheet.dart';
import 'auctions_screen.dart';
import 'live_home_screen.dart';
import 'live_screens.dart';
import 'profile_screen.dart';
import '../l10n/tr.dart';
import '../widgets/language_button.dart';
import '../services/deep_link.dart';
import 'device_detail_screen.dart';
import 'messages_screen.dart';
import 'public_profile_screen.dart';
import 'search_screen.dart';
import 'wishlists_screen.dart';
import 'notifications_screen.dart';

/// Glavni okvir (samo aukcije): Početna · Aukcije · [+ Objavi] · Moje ·
/// Profil.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int get _index => ref.watch(homeTabProvider);

  void _go(int i) => ref.read(homeTabProvider.notifier).select(i);

  /// Logo vodi na početnu: zatvara otvorene ekrane i bira Portfolio.
  void _goHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _go(0);
  }

  static List<ShellDestination> get _destinations => [
    ShellDestination(t('Početna'), Icons.home_outlined, Icons.home),
    ShellDestination(t('Aukcije'), Icons.gavel_outlined, Icons.gavel),
    ShellDestination(t('Objavi'), Icons.add, Icons.add, action: true),
    ShellDestination(
      t('Moje'),
      Icons.local_activity_outlined,
      Icons.local_activity,
    ),
    ShellDestination(t('Profil'), Icons.person_outline, Icons.person),
  ];

  /// Kartice: 0 Početna, 1 Aukcije, 2 Moje, 3 Profil. U traci je "+" na
  /// mjestu 2 pa su Moje i Profil pomaknuti za jedan.
  static const _createSlot = 2;
  static int _navIndex(int tab) => tab < _createSlot ? tab : tab + 1;

  void _onNav(int nav) {
    if (nav == _createSlot) {
      showCreateSheet(context);
      return;
    }
    _go(nav < _createSlot ? nav : nav - 1);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingLink());
  }

  /// Otvara dijeljeni oglas ili trgovinu (kad se podaci učitaju).
  void _openPendingLink() {
    if (!mounted || !PendingLink.isPending) return;
    final state = ref.read(appProvider);
    final item = PendingLink.item;
    final shop = PendingLink.shop;
    final list = PendingLink.list;
    final live = PendingLink.live;
    if (live != null) {
      if (state.liveShowById(live) == null) return; // možda se sinkronizira
      PendingLink.clear();
      LiveRoomScreen.open(context, live);
      return;
    }
    if (list != null) {
      final dot = list.indexOf('.');
      final owner = list.substring(0, dot);
      if (state.userById(owner) == null) return;
      PendingLink.clear();
      WishlistDetailScreen.open(context, owner, list.substring(dot + 1));
      return;
    }
    if (item != null) {
      final d = state.deviceById(item);
      if (d == null) return; // možda se još sinkronizira
      PendingLink.clear();
      DeviceDetailScreen.open(context, d);
    } else if (shop != null) {
      final user = state.users
          .where((u) => u.username.toLowerCase() == shop)
          .firstOrNull;
      if (user == null) return;
      PendingLink.clear();
      PublicProfileScreen.open(context, user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PendingLink.isPending) {
      ref.listen(appProvider, (_, _) => _openPendingLink());
    }
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopBreakpoint;
    final phone = width < 600;

    return AdaptiveShell(
      destinations: _destinations,
      selectedIndex: _navIndex(_index),
      onSelect: _onNav,
      railHeader: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: LoopLogo(size: 22, onTap: _goHome),
      ),
      appBar: AppBar(
        // Jednostavna traka: logo lijevo, desno samo pretraga, poruke,
        // obavijesti i stanje (jezik je u Profilu → Postavke).
        titleSpacing: phone ? 8 : null,
        title: isDesktop
            ? Text(_destinations[_navIndex(_index)].label)
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: LoopLogo(size: 20, onTap: _goHome),
              ),
        actions: [
          IconButton(
            key: const ValueKey('open-search'),
            tooltip: t('Pretraži objave i račune'),
            icon: const Icon(Icons.search),
            onPressed: () => SearchScreen.open(context),
          ),
          const MessagesButton(),
          const NotificationBell(),
          if (!phone) ...[
            const LanguageButton(compact: true),
            const SizedBox(width: 6),
          ],
          SizedBox(width: phone ? 8 : 12),
        ],
      ),
      // IndexedStack čuva stanje (npr. odabranu kategoriju) pri promjeni taba.
      body: IndexedStack(
        index: _index,
        children: [
          LiveHomeScreen(onBrowse: () => _go(1)),
          const AuctionsScreen(),
          const MyAuctionsView(),
          const ProfileScreen(),
        ],
      ),
    );
  }
}
