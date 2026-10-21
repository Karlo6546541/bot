import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'item_image.dart';

/// Listanje prstom, mišem i touchpadom (na webu PageView inače ne reagira
/// na povlačenje mišem).
class AnyDeviceDragBehavior extends MaterialScrollBehavior {
  const AnyDeviceDragBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

/// Pregled fotografija preko cijelog ekrana: listanje lijevo/desno,
/// uvećanje s dva prsta (ili kotačićem miša), dvostruki dodir za uvećanje,
/// sličice na dnu i zatvaranje s ✕, tipkom Esc ili povlačenjem prema dolje.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.photos, this.initial = 0});

  final List<String> photos;
  final int initial;

  static Future<void> open(
    BuildContext context,
    List<String> photos, {
    int initial = 0,
  }) {
    if (photos.isEmpty) return Future.value();
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => PhotoViewer(photos: photos, initial: initial),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final _controller = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  /// Kontroleri uvećanja po slici (za dvostruki dodir i reset pri listanju).
  final _zoom = <int, TransformationController>{};

  /// Dok je slika uvećana, listanje je isključeno (povlačenje pomiče sliku).
  bool _zoomed = false;
  double _dragDown = 0;

  TransformationController _zoomFor(int i) => _zoom.putIfAbsent(i, () {
    final c = TransformationController();
    c.addListener(() {
      final z = c.value.getMaxScaleOnAxis() > 1.01;
      if (i == _page && z != _zoomed) setState(() => _zoomed = z);
    });
    return c;
  });

  @override
  void dispose() {
    _controller.dispose();
    for (final c in _zoom.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(int i) {
    if (i < 0 || i >= widget.photos.length) return;
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _toggleZoom(int i, TapDownDetails? at) {
    final c = _zoomFor(i);
    if (c.value.getMaxScaleOnAxis() > 1.01) {
      c.value = Matrix4.identity();
    } else {
      // Uvećaj 2.5× oko točke dodira.
      final p = at?.localPosition ?? Offset.zero;
      const s = 2.5;
      c.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final many = photos.length > 1;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    TapDownDetails? lastTap;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _go(_page - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _go(_page + 1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            // Povlačenje prema dolje (kad slika nije uvećana) zatvara pregled.
            onVerticalDragUpdate: _zoomed
                ? null
                : (d) => setState(() => _dragDown += d.delta.dy),
            onVerticalDragEnd: _zoomed
                ? null
                : (_) {
                    if (_dragDown > 120) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _dragDown = 0);
                    }
                  },
            child: Transform.translate(
              offset: Offset(0, _dragDown.clamp(0, 400)),
              child: Opacity(
                opacity: (1 - _dragDown.clamp(0, 400) / 600).clamp(0.3, 1),
                child: Stack(
                  children: [
                    ScrollConfiguration(
                      behavior: const AnyDeviceDragBehavior(),
                      child: PageView.builder(
                        controller: _controller,
                        physics: _zoomed
                            ? const NeverScrollableScrollPhysics()
                            : const PageScrollPhysics(),
                        itemCount: photos.length,
                        onPageChanged: (i) {
                          // Vrati uvećanje prethodne slike.
                          _zoom[_page]?.value = Matrix4.identity();
                          setState(() {
                            _page = i;
                            _zoomed = false;
                          });
                        },
                        itemBuilder: (_, i) => GestureDetector(
                          onDoubleTapDown: (d) => lastTap = d,
                          onDoubleTap: () => _toggleZoom(i, lastTap),
                          child: InteractiveViewer(
                            transformationController: _zoomFor(i),
                            minScale: 1,
                            maxScale: 5,
                            child: Center(
                              child: LocalPhoto(
                                path: photos[i],
                                fit: BoxFit.contain,
                                fallback: const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white54,
                                  size: 64,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Gornja traka: brojač i zatvaranje.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              if (many)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${_page + 1} / ${photos.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              IconButton.filledTonal(
                                tooltip: 'Zatvori',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Strelice (korisne na računalu).
                    if (many && wide) ...[
                      _ViewerArrow(
                        left: true,
                        visible: _page > 0,
                        onTap: () => _go(_page - 1),
                      ),
                      _ViewerArrow(
                        left: false,
                        visible: _page < photos.length - 1,
                        onTap: () => _go(_page + 1),
                      ),
                    ],
                    // Sličice na dnu.
                    if (many)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var i = 0; i < photos.length; i++)
                                  GestureDetector(
                                    onTap: () => _go(i),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      width: 54,
                                      height: 54,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: i == _page
                                              ? Colors.white
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Opacity(
                                          opacity: i == _page ? 1 : 0.55,
                                          child: LocalPhoto(
                                            path: photos[i],
                                            cacheWidth: 160,
                                            fallback: const ColoredBox(
                                              color: Colors.white10,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
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
    );
  }
}

class _ViewerArrow extends StatelessWidget {
  const _ViewerArrow({
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
      left: left ? 12 : null,
      right: left ? null : 12,
      top: 0,
      bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: IgnorePointer(
            ignoring: !visible,
            child: IconButton.filledTonal(
              iconSize: 32,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              onPressed: onTap,
              icon: Icon(left ? Icons.chevron_left : Icons.chevron_right),
            ),
          ),
        ),
      ),
    );
  }
}
