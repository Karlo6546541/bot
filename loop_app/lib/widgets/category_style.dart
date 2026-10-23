import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/app_theme.dart';

/// Kategorijska paleta, provjerena validatorom za obje teme
/// (svijetla na #FFFFFF, tamna na #221B17): raspon svjetline, kroma,
/// CVD razlučivost susjednih boja i kontrast. U svijetloj temi tri boje
/// imaju kontrast < 3:1, pa grafikoni uvijek imaju vidljive oznake/legendu.
/// Boje se dodjeljuju UVIJEK istim redom — nikad se ne generiraju nove.
/// Odjeljak dobiva boju po svom redu u [ItemSection], kategorija po svom
/// redu unutar odjeljka (najviše 8 kategorija po odjeljku).
const _paletteLight = <Color>[
  Color(0xFF2A78D6), // plava
  Color(0xFFEB6834), // narančasta
  Color(0xFF1BAF7A), // tirkizna
  Color(0xFFEDA100), // žuta
  Color(0xFFE87BA4), // magenta
  Color(0xFF008300), // zelena
  Color(0xFF6250D6), // ljubičasta
  Color(0xFFE34948), // crvena
];

const _paletteDark = <Color>[
  Color(0xFF3987E5),
  Color(0xFFD95926),
  Color(0xFF199E70),
  Color(0xFFC98500),
  Color(0xFFD55181),
  Color(0xFF008300),
  Color(0xFF9085E9),
  Color(0xFFE66767),
];

List<Color> get kCategoricalPalette =>
    LoopColors.isDark ? _paletteDark : _paletteLight;

extension SectionStyle on ItemSection {
  Color get color => kCategoricalPalette[index];

  IconData get icon => switch (this) {
    ItemSection.electronics => Icons.devices,
    ItemSection.collectibles => Icons.auto_awesome,
    ItemSection.hobbies => Icons.interests,
    ItemSection.fashion => Icons.checkroom,
    ItemSection.home => Icons.chair_outlined,
    ItemSection.crafts => Icons.brush,
    ItemSection.activities => Icons.local_activity,
    ItemSection.digital => Icons.cloud_download_outlined,
  };
}

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
    DeviceCategory.cards => Icons.style,
    DeviceCategory.tcg => Icons.catching_pokemon,
    DeviceCategory.comics => Icons.auto_stories,
    DeviceCategory.coins => Icons.monetization_on_outlined,
    DeviceCategory.stamps => Icons.local_post_office_outlined,
    DeviceCategory.figures => Icons.smart_toy_outlined,
    DeviceCategory.vinyl => Icons.album,
    DeviceCategory.sport => Icons.directions_bike,
    DeviceCategory.instruments => Icons.music_note,
    DeviceCategory.books => Icons.menu_book,
    DeviceCategory.boardGames => Icons.casino_outlined,
    DeviceCategory.models => Icons.extension,
    DeviceCategory.videoGames => Icons.videogame_asset,
    DeviceCategory.clothes => Icons.dry_cleaning,
    DeviceCategory.sneakers => Icons.directions_run,
    DeviceCategory.bags => Icons.shopping_bag_outlined,
    DeviceCategory.watches => Icons.watch_later_outlined,
    DeviceCategory.accessories => Icons.style_outlined,
    DeviceCategory.homeDecor => Icons.chair_outlined,
    DeviceCategory.vintage => Icons.hourglass_bottom,
    DeviceCategory.beauty => Icons.spa_outlined,
    DeviceCategory.kids => Icons.child_friendly_outlined,
    DeviceCategory.jewelry => Icons.diamond_outlined,
    DeviceCategory.ceramics => Icons.coffee,
    DeviceCategory.textile => Icons.checkroom,
    DeviceCategory.woodwork => Icons.carpenter,
    DeviceCategory.paintings => Icons.palette_outlined,
    DeviceCategory.workshops => Icons.handyman_outlined,
    DeviceCategory.tutoring => Icons.school_outlined,
    DeviceCategory.tickets => Icons.confirmation_number_outlined,
    DeviceCategory.experiences => Icons.kayaking,
    DeviceCategory.models3d => Icons.view_in_ar,
    DeviceCategory.software => Icons.terminal,
    DeviceCategory.ebooks => Icons.auto_stories_outlined,
    DeviceCategory.templates => Icons.dashboard_customize_outlined,
    DeviceCategory.sounds => Icons.graphic_eq,
  };

  Color get color =>
      kCategoricalPalette[section.categories.indexOf(this) %
          kCategoricalPalette.length];

  /// Dijagonalni gradijent od boje kategorije prema tamnoj površini.
  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [color.withValues(alpha: 0.38), color.withValues(alpha: 0.08)],
  );
}

/// Boja stanja uređaja (zeleno → crveno).
extension ConditionStyle on DeviceCondition {
  Color get color => switch (this) {
    DeviceCondition.brandNew => const Color(0xFF5EE6FF),
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
