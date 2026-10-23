import 'package:flutter/material.dart';

import '../l10n/tr.dart';

import '../theme/app_theme.dart';

/// Širina od koje prikazujemo bočni izbornik umjesto donje navigacije.
const double kDesktopBreakpoint = 840;

class ShellDestination {
  const ShellDestination(
    this.label,
    this.icon,
    this.selectedIcon, {
    this.action = false,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Radnja (npr. "+ Objavi"), a ne kartica: istaknuti okrugli gumb.
  final bool action;

  Widget iconWidget(BuildContext context, {bool selected = false}) {
    if (!action) return Icon(selected ? selectedIcon : icon);
    return Container(
      key: const ValueKey('nav-create'),
      width: 44,
      height: 32,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
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
                icon: d.iconWidget(context),
                selectedIcon: d.iconWidget(context, selected: true),
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
                  icon: d.iconWidget(context),
                  selectedIcon: d.iconWidget(context, selected: true),
                  label: Text(d.label),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: LoopColors.surfaceHover),
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

/// LICIT logotip.
class LoopLogo extends StatelessWidget {
  const LoopLogo({super.key, this.size = 28, this.color, this.onTap});
  final double size;
  final Color? color;

  /// Dodir na logo (npr. povratak na početnu).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // LICIT: čekić u gradijentu (ljubičasta → crvena "uživo") i natpis.
    final logo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size * 1.35,
          height: size * 1.35,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6A2BD6), Color(0xFFFF2D55)],
            ),
            borderRadius: BorderRadius.circular(size * 0.4),
          ),
          child: Icon(Icons.gavel, color: Colors.white, size: size * 0.85),
        ),
        SizedBox(width: size * 0.35),
        Text(
          'LICIT',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            letterSpacing: size * 0.12,
            color: color ?? LoopColors.textPrimary,
          ),
        ),
      ],
    );
    if (onTap == null) return logo;
    return Tooltip(
      message: t('Početna'),
      child: InkWell(
        key: const ValueKey('logo-home'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: logo,
        ),
      ),
    );
  }
}
