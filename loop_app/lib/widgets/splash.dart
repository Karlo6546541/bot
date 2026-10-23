import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Uvodni ekran (~1,4 s): znak ∞ se iscrta, "LOOP" uskoči slovo po
/// slovo, pa kratki sjaj i traka učitavanja. [onDone] se zove kad
/// animacija završi (aplikacija se tad otvori ako su podaci spremni).
class LoopSplash extends StatefulWidget {
  const LoopSplash({super.key, this.onDone});
  final VoidCallback? onDone;

  static const duration = Duration(milliseconds: 1500);

  @override
  State<LoopSplash> createState() => _LoopSplashState();
}

class _LoopSplashState extends State<LoopSplash>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: LoopSplash.duration,
  )..forward().whenComplete(() => widget.onDone?.call());

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Dio animacije [from]–[to] preslikan na 0–1 s krivuljom.
  double _seg(double from, double to, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_c.value - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFF8A5C);
    return Material(
      color: const Color(0xFF17120F),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final draw = _seg(0, 0.5, Curves.easeInOutCubic);
          final pop = _seg(0.15, 0.45, Curves.elasticOut);
          final shine = _seg(0.55, 0.85);
          final bar = _seg(0.1, 1, Curves.easeInOut);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Topli sjaj iza znaka koji "diše".
              Center(
                child: Container(
                  width: 320 + 60 * math.sin(_c.value * math.pi),
                  height: 320 + 60 * math.sin(_c.value * math.pi),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accent.withValues(alpha: 0.35 * draw),
                        accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 0.6 + 0.4 * pop,
                      child: SizedBox(
                        width: 150,
                        height: 76,
                        child: CustomPaint(
                          painter: _InfinityPainter(
                            progress: draw,
                            shine: shine,
                            color: accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (i, ch) in 'LOOP'.split('').indexed)
                          Builder(
                            builder: (_) {
                              final v = _seg(
                                0.3 + i * 0.07,
                                0.55 + i * 0.07,
                                Curves.easeOutBack,
                              );
                              return Opacity(
                                opacity: v.clamp(0.0, 1.0),
                                child: Transform.translate(
                                  offset: Offset(0, 24 * (1 - v)),
                                  child: Text(
                                    ch,
                                    style: const TextStyle(
                                      fontFamily: kFontFamily,
                                      color: Colors.white,
                                      fontSize: 44,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 6,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Opacity(
                      opacity: _seg(0.6, 0.85),
                      child: const Text(
                        'LIVE · AUKCIJE · KUPI ODMAH',
                        style: TextStyle(
                          fontFamily: kFontFamily,
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 64,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: SizedBox(
                      width: 120,
                      height: 4,
                      child: LinearProgressIndicator(
                        value: bar,
                        color: accent,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Znak ∞ (lemniskata) koji se iscrtava, s bijelim odsjajem koji jednom
/// proleti po crti.
class _InfinityPainter extends CustomPainter {
  _InfinityPainter({
    required this.progress,
    required this.shine,
    required this.color,
  });

  final double progress;
  final double shine;
  final Color color;

  Path _path(Size s) {
    final path = Path();
    final a = s.width / 2 - 8;
    final cx = s.width / 2;
    final cy = s.height / 2;
    const n = 120;
    for (var i = 0; i <= n; i++) {
      final t = i / n * 2 * math.pi;
      final d = 1 + math.pow(math.sin(t), 2);
      final x = cx + a * math.cos(t) / d;
      final y = cy + a * math.sin(t) * math.cos(t) / d * 1.25;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final metric = _path(size).computeMetrics().first;
    final len = metric.length;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(metric.extractPath(0, len * progress), stroke);
    if (shine > 0 && shine < 1) {
      final at = len * shine;
      canvas.drawPath(
        metric.extractPath(math.max(0, at - len * 0.12), at),
        stroke
          ..strokeWidth = 5
          ..color = Colors.white.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(_InfinityPainter old) =>
      old.progress != progress || old.shine != shine;
}
