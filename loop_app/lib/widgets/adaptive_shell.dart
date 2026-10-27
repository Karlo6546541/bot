import 'package:flutter/material.dart';

import 'brand.dart';

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
    return Container(
      key: const ValueKey('nav-create'),
      width: compact ? 44 : 44,
      height: compact ? 32 : 32,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
      ),
      child: Icon(icon, color: Colors.white, size: compact ? 22 : null),
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
  });

  final List<ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? railHeader;
  final bool immersiveNavigation;

  Widget _navigation(BuildContext context, {bool compact = false}) =>
      NavigationBar(
        key: ValueKey(compact ? 'feed-navigation' : 'main-navigation'),
        // Mobitel: samo ikone (bez natpisa) na tamnosivoj traci — ugodnije
        // za oči od crne.
        height: compact ? 56 : null,
        labelBehavior: compact
            ? NavigationDestinationLabelBehavior.alwaysHide
            : null,
        backgroundColor: compact ? const Color(0xFF26272C) : null,
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
        body: SafeArea(top: false, child: body),
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(
            navigationBarTheme: NavigationBarThemeData(
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 10,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: states.contains(WidgetState.selected)
                      ? const Color(0xFFE9E9ED)
                      : const Color(0xFF92939D),
                ),
              ),
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  color: states.contains(WidgetState.selected)
                      ? const Color(0xFFE9E9ED)
                      : const Color(0xFF92939D),
                ),
              ),
            ),
          ),
          child: _navigation(context, compact: true),
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

/// Subhasto logotip.
class LoopLogo extends StatelessWidget {
  const LoopLogo({super.key, this.size = 28, this.color, this.onTap});
  final double size;
  final Color? color;

  /// Dodir na logo (npr. povratak na početnu).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final logo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpearMark(
          size: size * 1.25,
          head: c,
          shaft: color ?? LoopColors.textPrimary,
        ),
        SizedBox(width: size * 0.25),
        Text(
          kAppName.toUpperCase(),
          style: TextStyle(
            fontSize: size * 0.9,
            fontWeight: FontWeight.w900,
            letterSpacing: size * 0.08,
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
