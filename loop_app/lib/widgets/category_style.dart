import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/app_theme.dart';

/// Vizualni identitet kategorije: ikona i boja (za gradijente, čipove, grafove).
extension CategoryStyle on DeviceCategory {
  IconData get icon => switch (this) {
    DeviceCategory.phone => Icons.smartphone,
    DeviceCategory.laptop => Icons.laptop_mac,
    DeviceCategory.tablet => Icons.tablet_mac,
    DeviceCategory.audio => Icons.headphones,
    DeviceCategory.console => Icons.sports_esports,
    DeviceCategory.watch => Icons.watch,
    DeviceCategory.camera => Icons.photo_camera,
    DeviceCategory.other => Icons.devices_other,
  };

  Color get color => switch (this) {
    DeviceCategory.phone => LoopColors.accent,
    DeviceCategory.laptop => const Color(0xFF5B8CFF),
    DeviceCategory.tablet => const Color(0xFFB57BFF),
    DeviceCategory.audio => const Color(0xFFFF7AB6),
    DeviceCategory.console => const Color(0xFFFF6B4A),
    DeviceCategory.watch => const Color(0xFFFFC94D),
    DeviceCategory.camera => const Color(0xFF3FD0FF),
    DeviceCategory.other => LoopColors.textSecondary,
  };

  /// Dijagonalni gradijent od boje kategorije prema tamnoj površini.
  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.08)],
  );
}

/// Boja stanja uređaja (zeleno → crveno).
extension ConditionStyle on DeviceCondition {
  Color get color => switch (this) {
    DeviceCondition.excellent => LoopColors.success,
    DeviceCondition.veryGood => const Color(0xFF7BE0C3),
    DeviceCondition.good => const Color(0xFFFFC94D),
    DeviceCondition.forParts => LoopColors.error,
  };
}

/// Zaobljena ikona kategorije s gradijentom.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 48});

  final DeviceCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: category.gradient,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: category.color.withValues(alpha: 0.35)),
      ),
      child: Icon(category.icon, color: category.color, size: size * 0.5),
    );
  }
}

/// Animirani ulaz (fade + slide) za stavke liste; [index] daje lagano
/// kašnjenje kako bi se kartice pojavljivale jedna za drugom.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final ms = 260 + (index.clamp(0, 8) * 45);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 18),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
