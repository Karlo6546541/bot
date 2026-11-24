import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../models/story.dart';
import 'category_style.dart';
import 'item_image.dart';

/// Omjer priče (kao na Instagramu).
const kStoryAspect = 9 / 16;

/// Naziv fonta za odabir.
String storyFontLabel(StoryFont f) => switch (f) {
  StoryFont.classic => t('Klasično'),
  StoryFont.modern => t('Moderno'),
  StoryFont.neon => t('Neon'),
  StoryFont.typewriter => t('Pisaći stroj'),
  StoryFont.script => t('Rukopis'),
};

/// Stil slova za font (bez veličine i boje).
TextStyle storyFontStyle(StoryFont f) => switch (f) {
  StoryFont.classic => const TextStyle(
    fontFamily: 'Nunito',
    fontWeight: FontWeight.w900,
    height: 1.2,
  ),
  StoryFont.modern => const TextStyle(
    fontFamily: 'BebasNeue',
    letterSpacing: 1.5,
    height: 1.05,
  ),
  StoryFont.neon => const TextStyle(
    fontFamily: 'Nunito',
    fontWeight: FontWeight.w800,
    height: 1.2,
  ),
  StoryFont.typewriter => const TextStyle(
    fontFamily: 'SpaceMono',
    fontWeight: FontWeight.w700,
    height: 1.25,
  ),
  StoryFont.script => const TextStyle(fontFamily: 'Pacifico', height: 1.35),
};

/// Puna boja iza teksta → kontrastna boja slova.
Color _onColor(Color c) =>
    c.computeLuminance() > 0.55 ? Colors.black : Colors.white;

/// Izgled jednog teksta (bez položaja) za priču zadane širine.
class StoryTextBox extends StatelessWidget {
  const StoryTextBox({super.key, required this.layer, required this.width});

  final StoryText layer;
  final double width;

  @override
  Widget build(BuildContext context) =>
      _decorated(layer, width, Text(layer.text, textAlign: layer.align));
}

/// Tekst s pozadinom i stilom teksta [layer]; [child] je Text ili polje
/// za upis (urednik).
Widget _decorated(StoryText layer, double width, Widget child) {
  final style = storyTextStyleFor(layer, width);
  final fs = style.fontSize!;
  final color = Color(layer.color);
  final box = switch (layer.background) {
    StoryTextBackground.none => null,
    StoryTextBackground.solid => color,
    StoryTextBackground.soft => Colors.black.withValues(alpha: 0.45),
  };
  return Container(
    padding: box == null
        ? EdgeInsets.zero
        : EdgeInsets.symmetric(horizontal: fs * 0.4, vertical: fs * 0.15),
    decoration: box == null
        ? null
        : BoxDecoration(
            color: box,
            borderRadius: BorderRadius.circular(fs * 0.35),
          ),
    child: DefaultTextStyle.merge(style: style, child: child),
  );
}

/// Polje za upis s istim izgledom kao gotovi tekst.
Widget decoratedStoryText(StoryText layer, double width, Widget child) =>
    _decorated(layer, width, child);

/// Potpuni stil slova (font, veličina, boja, sjena/sjaj).
TextStyle storyTextStyleFor(StoryText layer, double width) {
  final color = Color(layer.color);
  final base = storyFontStyle(layer.font);
  final fs = layer.size * width * (layer.font == StoryFont.modern ? 1.3 : 1.0);
  final textColor = switch (layer.background) {
    StoryTextBackground.solid => _onColor(color),
    _ =>
      layer.font == StoryFont.neon
          ? Color.lerp(color, Colors.white, 0.55)!
          : color,
  };
  final shadows = layer.font == StoryFont.neon
      ? [
          Shadow(color: color, blurRadius: fs * 0.3),
          Shadow(color: color, blurRadius: fs * 0.8),
        ]
      : layer.background == StoryTextBackground.none
      ? [Shadow(color: Colors.black45, blurRadius: fs * 0.25)]
      : null;
  // Sve izričito: tema inače dodaje razmak slova (drukčiji u polju za upis
  // i u tekstu), pa bi se tekst lomio drukčije u uredniku i na priči.
  return base.copyWith(
    fontSize: fs,
    color: textColor,
    shadows: shadows,
    letterSpacing: base.letterSpacing ?? 0,
    wordSpacing: 0,
    fontStyle: FontStyle.normal,
    decoration: TextDecoration.none,
  );
}

/// Smješta [child] tako da mu je središte na (x, y) priče, uz rotaciju.
Widget positionStoryLayer({
  required StoryText layer,
  required Size size,
  required Widget child,
}) => Positioned(
  left: layer.x * size.width,
  top: layer.y * size.height,
  child: FractionalTranslation(
    translation: const Offset(-0.5, -0.5),
    child: Transform.rotate(
      angle: layer.rotation,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: size.width * 0.92),
        child: child,
      ),
    ),
  ),
);

/// Svi tekstovi priče (za prikaz).
class StoryLayers extends StatelessWidget {
  const StoryLayers({super.key, required this.layers});
  final List<StoryText> layers;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final size = c.biggest;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          for (final l in layers)
            positionStoryLayer(
              layer: l,
              size: size,
              child: StoryTextBox(layer: l, width: size.width),
            ),
        ],
      );
    },
  );
}

/// Pozadina priče: fotografija (cijela, preko zamućene kopije), fotografija
/// oglasa ili gradijent s ikonom kategorije.
class StoryBackdrop extends StatelessWidget {
  const StoryBackdrop({
    super.key,
    required this.gradient,
    this.photo,
    this.device,
  });

  final List<Color> gradient;
  final String? photo;
  final Device? device;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final path =
        photo ??
        (d != null && d.imagePaths.isNotEmpty ? d.imagePaths.first : null);
    final background = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
    );
    if (path == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          background,
          if (d != null)
            Center(
              child: Icon(d.category.icon, size: 150, color: Colors.white24),
            ),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: LocalPhoto(path: path, cacheWidth: 200, fallback: background),
        ),
        LocalPhoto(
          path: path,
          fit: BoxFit.contain,
          cacheWidth: 1080,
          fallback: background,
        ),
      ],
    );
  }
}

/// Kartica oglasa na dnu priče.
class StoryItemCard extends StatelessWidget {
  const StoryItemCard({
    super.key,
    required this.device,
    required this.price,
    this.discounted = false,
    this.onOpen,
    this.compact = false,
  });

  final Device device;
  final String price;
  final bool discounted;
  final VoidCallback? onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final d = device;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: onOpen == null ? null : const ValueKey('story-item'),
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 10),
          child: Row(
            children: [
              ItemThumb(device: d, size: compact ? 40 : 52),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      price,
                      style: TextStyle(
                        color: discounted
                            ? const Color(0xFFE5254B)
                            : Colors.black87,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // U uredniku je gumb samo pregled (bez dodira).
              IgnorePointer(
                ignoring: onOpen == null,
                child: FilledButton(
                  onPressed: onOpen ?? () {},
                  child: Text(t('Pogledaj')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
