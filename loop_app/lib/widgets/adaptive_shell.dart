import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Širina od koje prikazujemo bočni izbornik umjesto donje navigacije.
const double kDesktopBreakpoint = 840;

class ShellDestination {
  const ShellDestination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Zajednički okvir: Bottom Navigation Bar na mobitelu,
/// Navigation Rail (sidebar) na širim ekranima (Windows desktop).
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.railHeader,
  });

  final List<ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? railHeader;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopBreakpoint;

    if (!isDesktop) {
      return Scaffold(
        appBar: appBar,
        body: SafeArea(top: false, child: body),
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelect,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: width >= 1100,
            minExtendedWidth: 220,
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelect,
            leading: railHeader,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, color: LoopColors.surfaceHover),
          Expanded(
            child: Scaffold(
              appBar: appBar,
              body: body,
              floatingActionButton: floatingActionButton,
            ),
          ),
        ],
      ),
    );
  }
}

/// LOOP logotip.
class LoopLogo extends StatelessWidget {
  const LoopLogo({super.key, this.size = 28, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.all_inclusive, color: c, size: size * 1.1),
        SizedBox(width: size * 0.3),
        Text(
          'LOOP',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            letterSpacing: size * 0.12,
            color: LoopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
