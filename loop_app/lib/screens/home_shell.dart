import 'package:flutter/material.dart';

import '../widgets/adaptive_shell.dart';
import 'activity_screen.dart';
import 'add_device_screen.dart';
import 'market_screen.dart';
import 'portfolio_screen.dart';
import 'profile_screen.dart';

/// Glavni okvir za prijavljenog korisnika s 4 taba.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    ShellDestination(
      'Portfolio',
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
    ),
    ShellDestination('Market', Icons.storefront_outlined, Icons.storefront),
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
      onSelect: (i) => setState(() => _index = i),
      railHeader: const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: LoopLogo(size: 22),
      ),
      appBar: AppBar(
        title: isDesktop
            ? Text(_destinations[_index].label)
            : const LoopLogo(size: 22),
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: _openAddDevice,
              icon: const Icon(Icons.add),
              label: const Text(
                'Dodaj predmet',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      // IndexedStack čuva stanje (npr. search u Marketu) pri promjeni taba.
      body: IndexedStack(
        index: _index,
        children: [
          PortfolioScreen(onGoToMarket: () => setState(() => _index = 1)),
          const MarketScreen(),
          const ActivityScreen(),
          const ProfileScreen(),
        ],
      ),
    );
  }
}
