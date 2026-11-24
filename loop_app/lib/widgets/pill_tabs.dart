import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Kapsula je u cijeloj aplikaciji RESERVIRANA za promjenu kartica
/// (tabova): jedna kapsula, unutar nje odabrana "pilula". Sve ostalo ima
/// jedinstvene radijuse — čipovi 12, gumbi i polja 16, kartice 20, listovi
/// 28.
///
/// [PillTabBar] je zamjena za [TabBar]: koristi [DefaultTabController] (ili
/// [controller]) pa radi uz postojeći [TabBarView]; ključevi na [Tab]-ovima
/// ostaju na dodirnoj površini.
class PillTabBar extends StatelessWidget implements PreferredSizeWidget {
  const PillTabBar({
    super.key,
    required this.tabs,
    this.scrollable = false,
    this.onDark = false,
    this.controller,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 8),
  });

  final List<Widget> tabs;

  /// Mnogo kartica ili dugi nazivi: kapsula se pomiče vodoravno.
  final bool scrollable;

  /// Uvijek tamna podloga (live soba, listovi iz livea).
  final bool onDark;
  final TabController? controller;
  final EdgeInsetsGeometry padding;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  static String _label(Widget tab) {
    if (tab is Tab) {
      if (tab.text != null) return tab.text!;
      final child = tab.child;
      if (child is Text) return child.data ?? '';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final c = controller ?? DefaultTabController.of(context);
    final dark = onDark || LoopColors.isDark;
    final track = onDark
        ? const Color(0x1FFFFFFF)
        : dark
        ? const Color(0x1AFFFFFF)
        : LoopColors.surfaceHover;
    final selectedBg = onDark
        ? Colors.white
        : dark
        ? Colors.white
        : const Color(0xFF1D1D1F);
    final selectedFg = onDark || dark ? Colors.black : Colors.white;
    final idleFg = onDark ? const Color(0xFFD0D0D6) : LoopColors.textSecondary;

    return AnimatedBuilder(
      animation: c.animation ?? c,
      builder: (context, _) {
        final selected = (c.animation?.value ?? c.index.toDouble()).round();
        Widget item(int i) {
          final on = i == selected;
          final tab = tabs[i];
          final pill = AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: on ? selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              _label(tab),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: on ? selectedFg : idleFg,
              ),
            ),
          );
          return Semantics(
            button: true,
            selected: on,
            label: _label(tab),
            excludeSemantics: true,
            child: InkWell(
              key: tab.key,
              borderRadius: BorderRadius.circular(99),
              onTap: () => c.animateTo(i),
              child: pill,
            ),
          );
        }

        final items = [for (var i = 0; i < tabs.length; i++) item(i)];
        return Padding(
          padding: padding,
          child: Container(
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(99),
            ),
            child: scrollable
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          items[i],
                        ],
                      ],
                    ),
                  )
                : Row(children: [for (final i in items) Expanded(child: i)]),
          ),
        );
      },
    );
  }
}

/// Kapsula za prebacivanje prikaza bez [TabController]-a (npr. filteri
/// početne): ista kapsula i odabrana pilula kao [PillTabBar].
class PillSwitch extends StatelessWidget {
  const PillSwitch({
    super.key,
    required this.items,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  final List<PillSwitchItem> items;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = LoopColors.isDark;
    final track = dark ? const Color(0x1AFFFFFF) : LoopColors.surfaceHover;
    final selectedBg = dark ? Colors.white : const Color(0xFF1D1D1F);
    final selectedFg = dark ? Colors.black : Colors.white;
    return Padding(
      padding: padding,
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(99),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Semantics(
                  button: true,
                  selected: items[i].selected,
                  label: items[i].label,
                  excludeSemantics: true,
                  child: InkWell(
                    key: items[i].key,
                    borderRadius: BorderRadius.circular(99),
                    onTap: items[i].onTap,
                    child: AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: items[i].selected
                            ? selectedBg
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        items[i].label,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: items[i].selected
                              ? selectedFg
                              : LoopColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PillSwitchItem {
  const PillSwitchItem({
    this.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final Key? key;
  final String label;
  final bool selected;
  final VoidCallback onTap;
}
