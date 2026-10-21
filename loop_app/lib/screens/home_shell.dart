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

/// Glavni okvir za prijavljenog korisnika s 4 taba.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int get _index => ref.watch(homeTabProvider);

  void _go(int i) => ref.read(homeTabProvider.notifier).select(i);

  static const _destinations = [
    ShellDestination(
      'Portfolio',
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
    ),
    ShellDestination('Market', Icons.storefront_outlined, Icons.storefront),
    ShellDestination('Aukcije', Icons.gavel_outlined, Icons.gavel),
    ShellDestination(
      'Aktivnost',
      Icons.receipt_long_outlined,
      Icons.receipt_long,
    ),
    ShellDestination('Profil', Icons.person_outline, Icons.person),
  ];

  void _openAddDevice() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AddDeviceScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    return AdaptiveShell(
      destinations: _destinations,
      selectedIndex: _index,
      onSelect: _go,
      railHeader: const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: LoopLogo(size: 22),
      ),
      appBar: AppBar(
        title: isDesktop
            ? Text(_destinations[_index].label)
            : const LoopLogo(size: 22),
        actions: const [_CreditsPill(), SizedBox(width: 12)],
      ),
      floatingActionButton: switch (_index) {
        0 => FloatingActionButton.extended(
          onPressed: _openAddDevice,
          icon: const Icon(Icons.add),
          label: const Text(
            'Dodaj predmet',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        2 => FloatingActionButton.extended(
          onPressed: () => CreateAuctionScreen.open(context),
          icon: const Icon(Icons.gavel),
          label: const Text(
            'Nova aukcija',
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
      message: 'Kupi kredite',
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
