import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';

import '../widgets/adaptive_shell.dart';
import 'activity_screen.dart';
import 'add_device_screen.dart';
import 'auctions_screen.dart';
import 'buy_credits_screen.dart';
import 'create_auction_screen.dart';
import 'market_screen.dart';
import 'portfolio_screen.dart';
import 'profile_screen.dart';
import '../l10n/tr.dart';
import '../widgets/language_button.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';

/// Glavni okvir za prijavljenog korisnika s 4 taba.
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
    ShellDestination(
      'Portfolio',
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
    ),
    ShellDestination('Market', Icons.storefront_outlined, Icons.storefront),
    ShellDestination(t('Aukcije'), Icons.gavel_outlined, Icons.gavel),
    ShellDestination(
      t('Aktivnost'),
      Icons.receipt_long_outlined,
      Icons.receipt_long,
    ),
    ShellDestination(t('Profil'), Icons.person_outline, Icons.person),
  ];

  void _openAddDevice() {
    AddDeviceScreen.open(context);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopBreakpoint;
    final phone = width < 600;

    return AdaptiveShell(
      destinations: _destinations,
      selectedIndex: _index,
      onSelect: _go,
      railHeader: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: LoopLogo(size: 22, onTap: _goHome),
      ),
      appBar: AppBar(
        title: isDesktop
            ? Text(_destinations[_index].label)
            // Na uskom ekranu logo se smanji da stanu jezik i krediti.
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: LoopLogo(size: 22, onTap: _goHome),
              ),
        actions: [
          const MessagesButton(),
          const NotificationBell(),
          LanguageButton(compact: phone),
          const SizedBox(width: 6),
          const _CreditsPill(),
          const SizedBox(width: 12),
        ],
      ),
      // Na mobitelu: početna ima "Dodaj predmet" u brzim akcijama, a za
      // aukcije je dovoljan okrugli gumb koji ne prekriva kartice.
      floatingActionButton: switch (_index) {
        0 when phone => null,
        2 when phone => FloatingActionButton(
          tooltip: t('Nova aukcija'),
          onPressed: () => CreateAuctionScreen.open(context),
          child: const Icon(Icons.gavel),
        ),
        0 => FloatingActionButton.extended(
          onPressed: _openAddDevice,
          icon: const Icon(Icons.add),
          label: Text(
            t('Dodaj predmet'),
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        2 => FloatingActionButton.extended(
          onPressed: () => CreateAuctionScreen.open(context),
          icon: const Icon(Icons.gavel),
          label: Text(
            t('Nova aukcija'),
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        _ => null,
      },
      // IndexedStack čuva stanje (npr. search u Marketu) pri promjeni taba.
      body: IndexedStack(
        index: _index,
        children: [
          PortfolioScreen(onGoToMarket: () => _go(1)),
          const MarketScreen(),
          const AuctionsScreen(),
          const ActivityScreen(),
          const ProfileScreen(),
        ],
      ),
    );
  }
}

/// Stanje kredita u gornjoj traci; dodir otvara kupnju kredita.
class _CreditsPill extends ConsumerWidget {
  const _CreditsPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = ref.watch(
      appProvider.select((s) => s.currentUser?.credits ?? 0),
    );
    return Tooltip(
      message: t('Uplati novac'),
      child: Material(
        color: LoopColors.sunny,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => BuyCreditsScreen.open(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🪙', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  formatNumber(credits),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 4),
                Icon(Icons.add_circle, size: 20, color: LoopColors.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
