import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/tr.dart';
import 'vision_glass.dart';

/// A deliberate horizontal gesture; a normal tap never places a bid.
class VisionBidSlider extends StatefulWidget {
  const VisionBidSlider({
    super.key,
    required this.label,
    required this.confirmationKey,
    required this.onConfirm,
    this.semanticLabel,
  });
  final String label;
  final String? semanticLabel;
  final Object confirmationKey;
  final Future<void> Function()? onConfirm;
  @override
  State<VisionBidSlider> createState() => _VisionBidSliderState();
}

class _VisionBidSliderState extends State<VisionBidSlider> {
  double _progress = 0;
  bool _dragging = false, _submitting = false;
  bool get _enabled => widget.onConfirm != null && !_submitting;
  @override
  void didUpdateWidget(VisionBidSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A bid price changing under the finger requires a fresh gesture.
    if (oldWidget.confirmationKey != widget.confirmationKey || !_enabled) {
      _dragging = false;
      _progress = 0;
    }
  }

  Future<void> _confirm() async {
    if (!_enabled) return;
    final action = widget.onConfirm!;
    setState(() {
      _submitting = true;
      _dragging = false;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _progress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: _enabled,
    label: widget.semanticLabel ?? widget.label,
    onTap: _enabled ? _confirm : null,
    child: FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _confirm();
            return null;
          },
        ),
      },
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            final travel = (box.maxWidth - 56).clamp(1.0, double.infinity);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: !_enabled
                  ? null
                  : (_) => setState(() {
                      _dragging = true;
                      _progress = 0;
                    }),
              onHorizontalDragUpdate: !_enabled
                  ? null
                  : (details) {
                      if (_dragging) {
                        setState(
                          () => _progress =
                              (_progress + details.delta.dx / travel).clamp(
                                0,
                                1,
                              ),
                        );
                      }
                    },
              onHorizontalDragCancel: () => setState(() {
                _dragging = false;
                _progress = 0;
              }),
              onHorizontalDragEnd: !_enabled
                  ? null
                  : (_) {
                      if (_dragging && _progress >= .85) {
                        _confirm();
                      } else {
                        setState(() {
                          _dragging = false;
                          _progress = 0;
                        });
                      }
                    },
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Colors.white.withValues(alpha: .2)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: _progress,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0x800A84FF), Color(0x9930D158)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 58, right: 12),
                      child: Text(
                        _submitting ? t('Obrada…') : widget.label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _enabled ? Colors.white : Colors.white54,
                          fontSize: 14,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration:
                          _dragging || MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      left: 4 + travel * _progress,
                      top: 4,
                      child: Container(
                        key: const ValueKey('vision-slide-thumb'),
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: _submitting
                            ? const Icon(
                                Icons.more_horiz,
                                color: Colors.black,
                                size: 22,
                              )
                            : const Icon(
                                Icons.arrow_forward,
                                color: Colors.black,
                                size: 22,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// The HTML's bottom handle. Drag recognition stays away from catalog scrolling
/// and horizontal bid gestures.
class VisionShopHandle extends StatefulWidget {
  const VisionShopHandle({
    super.key,
    required this.onOpen,
    required this.label,
  });
  final VoidCallback onOpen;
  final String label;
  @override
  State<VisionShopHandle> createState() => _VisionShopHandleState();
}

class _VisionShopHandleState extends State<VisionShopHandle> {
  double _distance = 0;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onOpen,
      onVerticalDragStart: (_) => _distance = 0,
      onVerticalDragUpdate: (d) => _distance -= d.delta.dy,
      onVerticalDragEnd: (d) {
        if (_distance > 36 || (d.primaryVelocity ?? 0) < -300) widget.onOpen();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white54,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: Color(0xFFE2E2E7),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class VisionLiveShopOverlay extends StatefulWidget {
  const VisionLiveShopOverlay({
    super.key,
    required this.child,
    required this.drawerBuilder,
  });
  final Widget child;
  final Widget Function(BuildContext, VoidCallback) drawerBuilder;
  @override
  State<VisionLiveShopOverlay> createState() => VisionLiveShopOverlayState();
}

class VisionLiveShopOverlayState extends State<VisionLiveShopOverlay> {
  bool _open = false, _created = false;
  double _drag = 0;
  void open() {
    FocusScope.of(context).unfocus();
    setState(() {
      _created = true;
      _open = true;
    });
  }

  void close() => setState(() => _open = false);
  bool get isOpen => _open;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_open,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _open) close();
    },
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final duration = MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 400);
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(excluding: _open, child: widget.child),
                  IgnorePointer(
                    ignoring: !_open,
                    child: AnimatedOpacity(
                      opacity: _open ? 1 : 0,
                      duration: duration,
                      child: GestureDetector(
                        onTap: close,
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: _open ? 8 : 0,
                            sigmaY: _open ? 8 : 0,
                          ),
                          child: const ColoredBox(color: Color(0x55000000)),
                        ),
                      ),
                    ),
                  ),
                  if (_created)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: IgnorePointer(
                        ignoring: !_open,
                        child: ExcludeSemantics(
                          excluding: !_open,
                          child: AnimatedSlide(
                            offset: _open ? Offset.zero : const Offset(0, 1.1),
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            child: SizedBox(
                              height: constraints.maxHeight * .70,
                              child: VisionGlass(
                                dark: true,
                                heavy: true,
                                radius: 32,
                                child: Column(
                                  children: [
                                    GestureDetector(
                                      key: const ValueKey('live-shop-dismiss'),
                                      behavior: HitTestBehavior.opaque,
                                      onVerticalDragStart: (_) => _drag = 0,
                                      onVerticalDragUpdate: (d) =>
                                          _drag += d.delta.dy,
                                      onVerticalDragEnd: (d) {
                                        if (_drag > 36 ||
                                            (d.primaryVelocity ?? 0) > 300) {
                                          close();
                                        }
                                      },
                                      child: SizedBox(
                                        width: double.infinity,
                                        height: 52,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 42,
                                                  height: 4,
                                                  decoration: BoxDecoration(
                                                    color: Colors.white54,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          99,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  t(
                                                    'Povuci dolje za puni video',
                                                  ),
                                                  style: const TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Positioned(
                                              right: 6,
                                              child: IconButton(
                                                key: const ValueKey(
                                                  'live-shop-close',
                                                ),
                                                tooltip: t('Zatvori shop'),
                                                onPressed: close,
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: widget.drawerBuilder(
                                        context,
                                        close,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
