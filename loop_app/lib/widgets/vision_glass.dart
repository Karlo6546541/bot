import '../config/design_variant.dart';

import 'dart:ui';

import 'package:flutter/material.dart';

/// Bounded glass: blur only the navigation, live dock and open drawers.
/// Product grids use normal images, so scrolling does not stack filters.
class VisionGlass extends StatelessWidget {
  const VisionGlass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.blur = true,
    this.dark,
    this.heavy = false,
    this.opacity,
    this.quiet = false,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool blur;
  final bool? dark;
  final bool heavy;
  final bool quiet;
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final isDark = dark ?? Theme.of(context).brightness == Brightness.dark;
    final flat = kSimpleDesign && quiet && !heavy && dark == null;
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: flat
          ? Colors.transparent
          : isDark
          ? (heavy
                ? const Color(
                    0xFF19191E,
                  ).withValues(alpha: opacity ?? (kSimpleDesign ? .52 : .65))
                : const Color(
                    0xFF28282D,
                  ).withValues(alpha: opacity ?? (kSimpleDesign ? .65 : .45)))
          : Colors.white.withValues(alpha: .86),
      border: Border.all(
        color: flat
            ? Colors.transparent
            : isDark
            ? Colors.white.withValues(alpha: kSimpleDesign ? .12 : .22)
            : Colors.black.withValues(alpha: .10),
      ),
    );
    final panel = DecoratedBox(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: !flat && blur && !MediaQuery.disableAnimationsOf(context)
          ? BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: heavy ? 40 : 25,
                sigmaY: heavy ? 40 : 25,
              ),
              child: panel,
            )
          : panel,
    );
  }
}

class VisionSectionLabel extends StatelessWidget {
  const VisionSectionLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      kSimpleDesign ? label : label.toUpperCase(),
      style: TextStyle(
        fontSize: kSimpleDesign ? 21 : 11,
        fontWeight: FontWeight.w600,
        letterSpacing: kSimpleDesign ? -.5 : 1.25,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
