import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'vision_glass.dart';

/// Quiet pools of colour sit behind content; scrolling never blurs the page.
class JednostavnoBackdrop extends StatelessWidget {
  const JednostavnoBackdrop({
    super.key,
    required this.child,
    this.seller = false,
  });
  final Widget child;
  final bool seller;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
        ),
        if (dark) ...[
          Positioned(
            top: -150,
            right: -110,
            width: 400,
            height: 400,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      (seller
                              ? const Color(0xFF7652B9)
                              : const Color(0xFF426CA8))
                          .withValues(alpha: .24),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: -170,
            width: 400,
            height: 400,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFD49B58).withValues(alpha: .10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        child,
      ],
    );
  }
}

class JednostavnoGroup extends StatelessWidget {
  const JednostavnoGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => VisionGlass(
    radius: 32,
    blur: false,
    child: Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: children),
      ),
    ),
  );
}

class JednostavnoRow extends StatelessWidget {
  const JednostavnoRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.count,
    this.trailing,
    this.leading,
  });
  final String title;
  final String? subtitle;
  final int? count;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -.3,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: LoopColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (count != null && count! > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: LoopColors.textPrimary.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            if (trailing != null)
              trailing!
            else
              Icon(
                Icons.chevron_right,
                color: LoopColors.textSecondary,
                size: 20,
              ),
          ],
        ),
      ),
    ),
  );
}

class JednostavnoTitle extends StatelessWidget {
  const JednostavnoTitle(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 34,
      height: 1.08,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.2,
    ),
  );
}
