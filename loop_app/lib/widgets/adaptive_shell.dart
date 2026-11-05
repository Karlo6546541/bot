import 'dart:async';
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
  Timer? _idle;
  bool _collapsed = false;

  void _expand() {
    _idle?.cancel();
    if (_collapsed) setState(() => _collapsed = false);
  }

  bool _scroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
      _idle?.cancel();
      if (!_collapsed) setState(() => _collapsed = true);
    } else if (n is ScrollEndNotification) {
      _idle?.cancel();
      _idle = Timer(const Duration(milliseconds: 280), _expand);
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant AdaptiveShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) _expand();
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  Widget _navigation(BuildContext context, {bool compact = false}) =>
      NavigationBar(
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopBreakpoint;

    if (!isDesktop) {
      return Scaffold(
        appBar: widget.appBar,
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                onNotification: _scroll,
                child: SafeArea(top: false, child: widget.body),
              ),
            ),
            if (widget.showNavigation)
              Positioned(
                left: 20,
                right: 20,
                bottom: 10,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: AnimatedSize(
                      key: const ValueKey('floating-dock'),
                      alignment: Alignment.bottomCenter,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      child: SizedBox(
                        width: _collapsed ? 104 : 320,
                        height: _collapsed ? 44 : 68,
                        child: _collapsed
                            ? Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  key: const ValueKey('dock-expand'),
                                  onTap: _expand,
                                  borderRadius: BorderRadius.circular(99),
                                  child: Semantics(
                                    button: true,
                                    label: t('Otvori navigaciju'),
                                    child: Center(
                                      child: VisionGlass(
                                        radius: 99,
                                        child: SizedBox(
                                          width: 104,
                                          height: 10,
                                          child: Center(
                                            child: Container(
                                              width: 48,
                                              height: 3,
                                              color: LoopColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : VisionGlass(
                                radius: 99,
                                child: _navigation(context, compact: true),
                              ),
                      ),
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
