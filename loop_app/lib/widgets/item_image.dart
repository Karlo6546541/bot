import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/image_store.dart';
import 'photo_viewer.dart';
import '../theme/app_theme.dart';
import 'category_style.dart';

/// Lokalna fotografija; ako datoteka ne postoji (ili je web), prikazuje
/// [fallback]. Slike se dekodiraju u smanjenoj veličini radi memorije.
class LocalPhoto extends StatelessWidget {
  const LocalPhoto({
    super.key,
    required this.path,
    required this.fallback,
    this.cacheWidth,
    this.fit = BoxFit.cover,
  });

  final String path;
  final Widget fallback;
  final int? cacheWidth;
  final BoxFit fit;

  /// Shared cache keys for visible images and feed preloading.
  static ImageProvider<Object>? providerFor(String path, {int? cacheWidth}) {
    final ImageProvider<Object> provider;
    switch (PhotoSource.of(path)) {
      case PhotoSource.network:
        provider = NetworkImage(path);
      case PhotoSource.data:
        final bytes = _decodeDataUrl(path);
        if (bytes == null) return null;
        provider = MemoryImage(bytes);
      case PhotoSource.file:
        if (kIsWeb) return null;
        provider = FileImage(File(path));
    }
    return ResizeImage.resizeIfNeeded(cacheWidth, null, provider);
  }

  @override
  Widget build(BuildContext context) {
    final provider = providerFor(path, cacheWidth: cacheWidth);
    if (provider == null) return fallback;
    return Image(
      image: provider,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : fallback,
    );
  }

  /// Dekodirane data: URL slike pamte se, da se ne dekodiraju pri svakom
  /// iscrtavanju.
  static final _decoded = <String, Uint8List>{};

  static Uint8List? _decodeDataUrl(String url) {
    final cached = _decoded[url];
    if (cached != null) return cached;
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    try {
      final bytes = base64Decode(url.substring(comma + 1));
      if (_decoded.length > 60) _decoded.clear();
      return _decoded[url] = bytes;
    } catch (_) {
      return null;
    }
  }
}

/// Kvadratna sličica predmeta: naslovna fotografija ili ikona kategorije.
class ItemThumb extends StatelessWidget {
  const ItemThumb({super.key, required this.device, this.size = 48});

  final Device device;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatar = CategoryAvatar(category: device.category, size: size);
    if (device.imagePaths.isEmpty) return avatar;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: SizedBox(
        width: size,
        height: size,
        child: LocalPhoto(
          path: device.imagePaths.first,
          fallback: avatar,
          cacheWidth: (size * 3).round(),
        ),
      ),
    );
  }
}

/// Velika naslovna slika za ekran detalja: galerija fotografija s točkicama
/// ili, bez fotografija, ilustracija u bojama kategorije.
class ItemGallery extends StatefulWidget {
  const ItemGallery({super.key, required this.device, this.height = 280});

  final Device device;
  final double height;

  @override
  State<ItemGallery> createState() => _ItemGalleryState();
}

class _ItemGalleryState extends State<ItemGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final photos = d.imagePaths;
    final illustration = ItemIllustration(category: d.category);

    if (photos.isEmpty) {
      return SizedBox(height: widget.height, child: illustration);
    }
    if (_page >= photos.length) _page = photos.length - 1;

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // Dodir na sliku otvara pregled preko cijelog ekrana.
          ScrollConfiguration(
            behavior: const AnyDeviceDragBehavior(),
            child: PageView.builder(
              controller: _controller,
              itemCount: photos.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => PhotoViewer.open(context, photos, initial: i),
                child: MouseRegion(
                  cursor: SystemMouseCursors.zoomIn,
                  child: LocalPhoto(
                    path: photos[i],
                    fallback: illustration,
                    cacheWidth: 1200,
                  ),
                ),
              ),
            ),
          ),
          // Brojač + naznaka da se slika može otvoriti.
          Positioned(
            top: 10,
            right: 10,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.zoom_out_map,
                      size: 14,
                      color: Colors.white,
                    ),
                    if (photos.length > 1) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${_page + 1} / ${photos.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (photos.length > 1) ...[
            // Strelice za desktop (na mobitelu se lista prstom).
            _Arrow(
              left: true,
              visible: _page > 0,
              onTap: () => _controller.previousPage(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              ),
            ),
            _Arrow(
              left: false,
              visible: _page < photos.length - 1,
              onTap: () => _controller.nextPage(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              ),
            ),
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < photos.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.left,
    required this.visible,
    required this.onTap,
  });
  final bool left;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left ? 8 : null,
      right: left ? null : 8,
      top: 0,
      bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: IgnorePointer(
            ignoring: !visible,
            child: IconButton.filledTonal(
              onPressed: onTap,
              icon: Icon(left ? Icons.chevron_left : Icons.chevron_right),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ilustracija kategorije za predmete bez fotografije: gradijent,
/// dekorativni krugovi i velika ikona.
class ItemIllustration extends StatelessWidget {
  const ItemIllustration({
    super.key,
    required this.category,
    this.iconSize = 72,
  });
  final DeviceCategory category;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = category.color;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withValues(alpha: 0.45), LoopColors.surface],
        ),
      ),
      child: Stack(
        children: [
          Positioned(right: -50, top: -50, child: _Ring(color: c, size: 200)),
          Positioned(left: -30, bottom: -60, child: _Ring(color: c, size: 160)),
          Center(
            child: Container(
              padding: EdgeInsets.all(iconSize * 0.39),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LoopColors.background.withValues(alpha: 0.35),
                border: Border.all(color: c.withValues(alpha: 0.5), width: 2),
              ),
              child: Icon(
                category.icon,
                size: iconSize,
                color: LoopColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.25), width: 18),
      ),
    );
  }
}
