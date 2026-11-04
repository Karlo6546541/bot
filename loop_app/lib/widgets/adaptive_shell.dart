import 'package:flutter/material.dart';

import 'brand.dart';
import 'vision_glass.dart';

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

  Widget iconWidget(
    BuildContext context, {
    bool selected = false,
    bool compact = false,
  }) {
    if (!action) {
      return Icon(selected ? selectedIcon : icon, size: compact ? 25 : null);
    }
    // Jedini istaknuti element u traci: okrugli akcent s plusom.
    return Container(
      key: const ValueKey('nav-create'),
      width: compact ? 46 : 44,
      height: compact ? 40 : 36,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Icon(
        icon,
        color: Theme.of(context).colorScheme.onPrimary,
        size: compact ? 23 : null,
      ),
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
    this.immersiveNavigation = false,
    this.showNavigation = true,
  });

  final List<ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? railHeader;
  final bool immersiveNavigation;
  final bool showNavigation;

  Widget _navigation(BuildContext context, {bool compact = false}) =>
      NavigationBar(
        key: ValueKey(compact ? 'feed-navigation' : 'main-navigation'),
        // Mobitel: ikone s natpisima na tamnosivoj traci.
        height: compact ? 72 : null,
        labelBehavior: compact
            ? NavigationDestinationLabelBehavior.alwaysShow
            : null,
        backgroundColor: Colors.transparent,
        surfaceTintColor: compact ? Colors.transparent : null,
        indicatorColor: compact ? Colors.transparent : null,
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelect,
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: d.iconWidget(context, compact: compact),
              selectedIcon: d.iconWidget(
                context,
                selected: true,
                compact: compact,
              ),
              label: d.label,
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopBreakpoint;

    if (!isDesktop) {
      return Scaffold(
        appBar: appBar,
        extendBody: true,
        body: SafeArea(top: false, child: body),
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: !showNavigation
            ? null
            : SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: VisionGlass(
                  radius: 30,
                  child: _navigation(context, compact: true),
                ),
              ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: width >= 1100,
            minExtendedWidth: 224,
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

/// Subhasto logotip.
class LoopLogo extends StatelessWidget {
  const LoopLogo({super.key, this.size = 28, this.color, this.onTap});
  final double size;
  final Color? color;

  /// Dodir na logo (npr. povratak na početnu).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final logo = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kAppName,
            style: TextStyle(
              fontSize: size * 0.9,
              fontWeight: FontWeight.w800,
              letterSpacing: -size * 0.045,
              color: color ?? LoopColors.textPrimary,
            ),
          ),
        ],
      ),
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
