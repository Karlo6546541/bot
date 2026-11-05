import '../config/backend_config.dart';
import 'cloud_commerce_screen.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

import '../widgets/adaptive_shell.dart';
import '../widgets/trade_actions.dart';
import 'activity_view.dart';
import 'categories_screen.dart';
import 'live_home_screen.dart';
import 'live_screens.dart';
import 'profile_screen.dart';
import 'seller_hub.dart';
import '../l10n/tr.dart';
import '../widgets/language_button.dart';
import '../services/deep_link.dart';
import '../services/app_location/app_location.dart';
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

  List<ShellDestination> get _destinations => [
    ShellDestination(
      t('Pozornica'),
      Icons.play_circle_outline,
      Icons.play_circle,
    ),
    ShellDestination(
      t('Studio'),
      Icons.sensors_outlined,
      Icons.sensors,
      action: true,
    ),
    ShellDestination(t('Trezor'), Icons.wallet_outlined, Icons.wallet),
  ];

  // Legacy deep links keep their meaning; three destinations collect those views.
  static int _navIndex(int tab) => switch (tab) {
    4 => 1,
    2 || 3 => 2,
    _ => 0,
  };

  void _onNav(int nav) {
    if (nav == 1 && blockGuest(context)) return;
    _go(switch (nav) {
      1 => 4,
      2 => 2,
      _ => 0,
    });
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
      4 => 'tab=studio',
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
    final cloud = PendingLink.cloud;
    if (cloud != null) {
      final cloudRoom = PendingLink.cloudRoom;
      PendingLink.clear();
      if (BackendConfig.cloudCommerceEnabled) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: AppPlace(
              'cloud=$cloud${cloudRoom == null ? '' : '&room=${Uri.encodeQueryComponent(cloudRoom)}'}',
            ).settings,
            builder: (_) => CloudCommerceScreen(
              initialTab: cloud == 'orders'
                  ? 2
                  : cloud == 'catalog'
                  ? 1
                  : 0,
              initialRoom: cloudRoom,
              liveOnly: cloud == 'live',
            ),
          ),
        );
      }
      return;
    }
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
        case 'studio':
        case 'prodavac':
          _go(4);
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
      showNavigation: true,
      immersiveNavigation: _index == 0 && feedSelected,
      // Isto na mobitelu i na računalu (Whatnot): Početna · Kategorije ·
      // Objavi · Moje (aktivnost) · Profil.
      destinations: _destinations,
      selectedIndex: _navIndex(_index),
      onSelect: _onNav,
      railHeader: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: LoopLogo(size: 22, onTap: _goHome),
      ),
      appBar: _index == 0 || _index == 4
          ? null
          : AppBar(
              // Jednostavna traka: logo lijevo, desno samo pretraga, poruke,
              // obavijesti i stanje (jezik je u Profilu → Postavke).
              titleSpacing: phone ? 8 : null,
              title: isDesktop
                  ? Text(_destinations[_navIndex(_index)].label)
                  : InkWell(
                      key: const ValueKey('logo-home'),
                      onTap: _goHome,
                      child: Text(
                        _index == 2 || _index == 3
                            ? t('Trezor')
                            : t('Pozornica'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
              actions: [
                // Početna i Kategorije već imaju svoju tražilicu.
                if (_index != 0 && _index != 1)
                  IconButton(
                    key: const ValueKey('open-search'),
                    tooltip: t('Pretraži objave i račune'),
                    icon: const Icon(Icons.search),
                    onPressed: () => SearchScreen.open(context),
                  ),
                if (_index == 2 || _index == 3)
                  IconButton(
                    key: const ValueKey('vault-account'),
                    tooltip: t(
                      _index == 3 ? 'Moje kupnje' : 'Profil i postavke',
                    ),
                    icon: Icon(
                      _index == 3
                          ? Icons.wallet_outlined
                          : Icons.account_circle_outlined,
                    ),
                    onPressed: () => _go(_index == 3 ? 2 : 3),
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
          TickerMode(
            enabled: _index == 2,
            child: ActivityView(onBrowse: () => _go(0)),
          ),
          const ProfileScreen(),
          TickerMode(
            enabled: _index == 4,
            child: const SellerHubScreen(embedded: true),
          ),
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
