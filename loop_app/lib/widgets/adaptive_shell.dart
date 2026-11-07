import '../config/design_variant.dart';

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
    if (!action || kSimpleDesign) {
      return Icon(
        selected ? selectedIcon : icon,
        key: action ? const ValueKey('nav-create') : null,
        color: action && selected && !kSimpleDesign ? LoopColors.live : null,
        size: compact ? 25 : null,
      );
    }
    // Jedini istaknuti element u traci: okrugli akcent s plusom.
    return Container(
      key: const ValueKey('nav-create'),
      width: compact ? 46 : 44,
      height: compact ? 40 : 36,
      decoration: BoxDecoration(
        color: selected
            ? LoopColors.live
            : LoopColors.live.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Icon(
        icon,
        color: selected ? Colors.white : LoopColors.live,
        size: compact ? 23 : null,
      ),
    );
  }
}

/// Zajednički okvir: Bottom Navigation Bar na mobitelu,
/// Navigation Rail (sidebar) na širim ekranima (Windows desktop).
class AdaptiveShell extends StatefulWidget {
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

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  Widget _navigation(BuildContext context, {bool compact = false}) {
    if (kSimpleDesign && compact) {
      return JednostavnoDock(
        destinations: widget.destinations,
        selectedIndex: widget.selectedIndex,
        onSelect: widget.onSelect,
      );
    }
    return NavigationBar(
      key: ValueKey(compact ? 'feed-navigation' : 'main-navigation'),
      // Mobitel: ikone s natpisima na tamnosivoj traci.
      height: compact ? 68 : null,
      labelBehavior: compact
          ? NavigationDestinationLabelBehavior.alwaysShow
          : null,
      backgroundColor: Colors.transparent,
      surfaceTintColor: compact ? Colors.transparent : null,
      indicatorColor: compact ? Colors.transparent : null,
      selectedIndex: widget.selectedIndex,
      onDestinationSelected: widget.onSelect,
      destinations: [
        for (final d in widget.destinations)
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
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopBreakpoint;

    if (!isDesktop) {
      // Traka je dio rasporeda (ne lebdi preko sadržaja): sadržaj uvijek
      // završava iznad nje, pa je ništa ne prekriva.
      return Scaffold(
        appBar: widget.appBar,
        body: Column(
          children: [
            Expanded(
              child: SafeArea(top: false, bottom: false, child: widget.body),
            ),
            if (widget.showNavigation)
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Center(
                  child: ConstrainedBox(
                    key: const ValueKey('floating-dock'),
                    constraints: BoxConstraints(
                      maxWidth: kSimpleDesign ? 460 : 400,
                      minHeight: 64,
                    ),
                    child: VisionGlass(
                      heavy: kSimpleDesign,
                      radius: 99,
                      child: _navigation(context, compact: true),
                    ),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: widget.floatingActionButton,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: width >= 1100,
            minExtendedWidth: 224,
            selectedIndex: widget.selectedIndex,
            onDestinationSelected: widget.onSelect,
            leading: widget.railHeader,
            destinations: [
              for (final d in widget.destinations)
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
              appBar: widget.appBar,
              body: widget.body,
              floatingActionButton: widget.floatingActionButton,
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
              fontSize: kSimpleDesign ? size : size * 0.9,
              fontWeight: kSimpleDesign ? FontWeight.w700 : FontWeight.w800,
              letterSpacing: kSimpleDesign ? -size * .03 : -size * .045,
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

/// Odredišta u donjoj traci: svaka ikona uvijek ima tekstualni naziv
/// (ikona iznad natpisa), a odabrano je istaknuto kapsulom.
class JednostavnoDock extends StatelessWidget {
  const JednostavnoDock({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });
  final List<ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          for (var i = 0; i < destinations.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selectedIndex,
                label: destinations[i].label,
                excludeSemantics: true,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('simple-nav-$i'),
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => onSelect(i),
                    child: AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      constraints: const BoxConstraints(minHeight: 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: i == selectedIndex
                            ? scheme.onSurface.withValues(alpha: .15)
                            : Colors.transparent,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            i == selectedIndex
                                ? destinations[i].selectedIcon
                                : destinations[i].icon,
                            size: 22,
                            color: scheme.onSurface.withValues(
                              alpha: i == selectedIndex ? 1 : .72,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            destinations[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: i == selectedIndex
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: scheme.onSurface.withValues(
                                alpha: i == selectedIndex ? 1 : .72,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
