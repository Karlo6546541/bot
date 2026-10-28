import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

import '../widgets/adaptive_shell.dart';
import '../widgets/create_sheet.dart';
import 'auctions_screen.dart';
import 'categories_screen.dart';
import 'live_home_screen.dart';
import 'live_screens.dart';
import 'profile_screen.dart';
import '../l10n/tr.dart';
import '../widgets/language_button.dart';
import '../services/deep_link.dart';
import '../services/app_location/app_location.dart';
import '../widgets/loop_snackbar.dart';
import 'add_device_screen.dart';
import 'auction_detail_screen.dart';
import 'device_detail_screen.dart';
import 'messages_screen.dart';
import 'public_profile_screen.dart';
import 'search_screen.dart';
import 'wishlists_screen.dart';
import 'notifications_screen.dart';

/// Glavni okvir: Početna · Kategorije · [+ Objavi] · Moje · Profil.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int get _index => ref.watch(homeTabProvider);

  /// Povijest otvaranja (kartica + gornji tab Početne), najnovije zadnje.
  /// Natrag (tipka ili gesta) vraća kronološki, pa na Početnu (Za tebe),
  /// a tek onda izlazi iz aplikacije.
  final _history = <(int, String)>[];
  bool _restoring = false;

  (int, String) get _current =>
      (ref.read(homeTabProvider), ref.read(homeFilterProvider));

  void _remember((int, String) previous) {
    if (_restoring) return;
    if (_history.isEmpty || _history.last != previous) _history.add(previous);
    if (_history.length > 50) _history.removeAt(0);
  }

  void _back() {
    // Otvorene postavke profila zatvaraju se prve.
    if (ref.read(profileSettingsProvider)) {
      ref.read(profileSettingsProvider.notifier).setOpen(false);
      return;
    }
    final now = _current;
    while (_history.isNotEmpty && _history.last == now) {
      _history.removeLast();
    }
    final (tab, filter) = _history.isNotEmpty
        ? _history.removeLast()
        : now == (0, 'for-you')
        ? (-1, '')
        : (0, 'for-you');
    if (tab < 0) {
      SystemNavigator.pop();
      return;
    }
    _restoring = true;
    ref.read(homeFilterProvider.notifier).select(filter);
    ref.read(homeTabProvider.notifier).select(tab);
    // Promjene vraćanja ne idu natrag u povijest (slušači se mogu javiti
    // i kasnije, zato tek nakon iscrtavanja).
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoring = false);
  }

  void _go(int i) {
    if (i != 3) ref.read(profileSettingsProvider.notifier).setOpen(false);
    ref.read(homeTabProvider.notifier).select(i);
  }

  /// Logo vodi na početnu: zatvara otvorene ekrane i bira Portfolio.
  void _goHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _go(0);
  }

  static List<ShellDestination> get _destinations => [
    ShellDestination(t('Početna'), Icons.home_outlined, Icons.home),
    ShellDestination(
      t('Kategorije'),
      Icons.grid_view_outlined,
      Icons.grid_view_rounded,
    ),
    ShellDestination(t('Objavi'), Icons.add, Icons.add, action: true),
    ShellDestination(
      t('Moje'),
      Icons.local_activity_outlined,
      Icons.local_activity,
    ),
    ShellDestination(t('Profil'), Icons.person_outline, Icons.person),
  ];

  /// Kartice: 0 Početna, 1 Kategorije, 2 Moje, 3 Profil. U traci je "+"
  /// na mjestu 2 pa su Moje i Profil pomaknuti za jedan.
  static const _createSlot = 2;
  static int _navIndex(int tab) => tab < _createSlot ? tab : tab + 1;

  void _onNav(int nav) {
    if (nav == _createSlot) {
      showCreateSheet(context);
      return;
    }
    _go(nav < _createSlot ? nav : nav - 1);
  }

  /// Tab početne u adresi (`?tab=live`…); Za tebe je bez upita.
  void _syncHome() {
    final tab = ref.read(homeTabProvider);
    final filter = ref.read(homeFilterProvider);
    AppLocation.setHome(switch (tab) {
      0 when filter == 'for-you' => '',
      0 => 'tab=$filter',
      1 => 'tab=kategorije',
      2 => 'tab=moje',
      _ => 'tab=profil',
    });
  }

  /// Poveznica koja se dugo ne pojavi (ne postoji ili je uklonjena).
  Timer? _linkTimeout;

  @override
  void dispose() {
    _linkTimeout?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Nakon registracije (aplikacija se gradi ispočetka): natrag na
    // mjesto s kojeg je gost krenuo (live, oglas, nova objava…).
    final back = AppLocation.takeReturn();
    if (back != null && !PendingLink.isPending) AppLocation.restore(back);
    if (PendingLink.isPending) {
      _linkTimeout = Timer(const Duration(seconds: 20), () {
        if (!mounted || !PendingLink.isPending) return;
        PendingLink.clear();
        showLoopSnackBar(
          t(
            'Poveznica ne vodi nikamo — oglas, live ili trgovina više ne postoji.',
          ),
          error: true,
        );
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncHome();
      _openPendingLink();
    });
  }

  /// Otvara dijeljeni oglas ili trgovinu (kad se podaci učitaju).
  void _openPendingLink() {
    if (!mounted || !PendingLink.isPending) return;
    final state = ref.read(appProvider);
    final item = PendingLink.item;
    final shop = PendingLink.shop;
    final list = PendingLink.list;
    final live = PendingLink.live;
    final auction = PendingLink.auction;
    final create = PendingLink.create;
    final tab = PendingLink.tab;
    if (tab != null) {
      PendingLink.clear();
      switch (tab) {
        case 'kategorije':
          _go(1);
        case 'moje':
          _go(2);
        case 'profil':
          _go(3);
        default:
          _go(0);
          ref.read(homeFilterProvider.notifier).select(tab);
      }
      return;
    }
    if (create != null) {
      PendingLink.clear();
      if (create == 'live') {
        CreateLiveShowScreen.open(context);
      } else {
        AddDeviceScreen.open(context);
      }
      return;
    }
    if (auction != null) {
      if (state.auctionById(auction) == null) return; // možda se sinkronizira
      PendingLink.clear();
      AuctionDetailScreen.open(context, auction);
      return;
    }
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
    ref.listen(homeTabProvider, (prev, _) {
      if (prev != null) _remember((prev, ref.read(homeFilterProvider)));
      _syncHome();
    });
    ref.listen(homeFilterProvider, (prev, _) {
      if (prev != null) _remember((ref.read(homeTabProvider), prev));
      _syncHome();
    });
    final feedSelected = ref.watch(homeFilterProvider) == 'for-you';
    if (PendingLink.isPending) {
      ref.listen(appProvider, (_, _) => _openPendingLink());
    }
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopBreakpoint;
    final phone = width < 600;

    final shell = AdaptiveShell(
      immersiveNavigation: _index == 0 && feedSelected,
      destinations: isDesktop
          ? _destinations
          // Mobitel: Početna · Moje (kupljeno, dostave, ponude) · + · Profil.
          : [
              _destinations[0],
              _destinations[3],
              _destinations[2],
              _destinations[4],
            ],
      selectedIndex: isDesktop
          ? _navIndex(_index)
          : switch (_index) {
              2 => 1,
              3 => 3,
              _ => 0,
            },
      onSelect: isDesktop
          ? _onNav
          : (nav) {
              if (nav == 2) {
                showCreateSheet(context);
              } else {
                _go(switch (nav) {
                  1 => 2,
                  3 => 3,
                  _ => 0,
                });
              }
            },
      railHeader: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: LoopLogo(size: 22, onTap: _goHome),
      ),
      appBar: _index == 0 && phone
          ? null
          : AppBar(
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
                // Početna već ima traku za pretragu.
                if (_index != 0)
                  IconButton(
                    key: const ValueKey('open-search'),
                    tooltip: t('Pretraži objave i račune'),
                    icon: const Icon(Icons.search),
                    onPressed: () => SearchScreen.open(context),
                  ),
                PopupMenuButton<int>(
                  key: const ValueKey('shell-library-menu'),
                  tooltip: t('Filteri'),
                  icon: const Icon(Icons.tune),
                  onSelected: _go,
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 1, child: Text(t('Kategorije'))),
                    PopupMenuItem(value: 2, child: Text(t('Moje'))),
                  ],
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
          LiveHomeScreen(visible: _index == 0),
          const CategoriesScreen(),
          MyAuctionsView(onBrowse: () => _go(0)),
          const ProfileScreen(),
        ],
      ),
    );
    // Natrag: kronološki kroz otvorene kartice, pa na Početnu, pa izlaz.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: shell,
    );
  }
}
