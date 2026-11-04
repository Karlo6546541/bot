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
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool blur;
  final bool? dark;
  final bool heavy;
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final isDark = dark ?? Theme.of(context).brightness == Brightness.dark;
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: isDark
          ? (heavy
                ? const Color(0xFF19191E).withValues(alpha: opacity ?? .65)
                : const Color(0xFF28282D).withValues(alpha: opacity ?? .45))
          : Colors.white.withValues(alpha: .86),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: .22)
            : Colors.black.withValues(alpha: .10),
      ),
    );
    final panel = DecoratedBox(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: blur && !MediaQuery.disableAnimationsOf(context)
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
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.25,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
