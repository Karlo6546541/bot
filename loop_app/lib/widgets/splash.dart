import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'brand.dart';

/// Uvodni ekran (~1,7 s): koplje uleti dijagonalno i zabije se u sredinu
/// (udarni val i kratki potres), slova SUBHASTO padnu jedno po jedno,
/// odsjaj prijeđe preko vrha koplja i traka učitavanja se napuni.
/// [onDone] se zove kad animacija završi.
class LoopSplash extends StatefulWidget {
  const LoopSplash({super.key, this.onDone});
  final VoidCallback? onDone;

  static const duration = Duration(milliseconds: 1700);

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

  static const _accent = Color(0xFFFF9248);
  static const _cream = Color(0xFFF5EDE6);

  /// Trenutak udarca (udio animacije).
  static const _hit = 0.3;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF17120F),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = _c.value;
          // Let: iz donjeg lijevog kuta do sredine, ubrzano (kao bačeno).
          final fly = _seg(0, _hit, Curves.easeInQuad);
          final flyOffset = Offset(-260, 260) * (1 - fly);
          // Udarac: val i potres odmah nakon _hit.
          final wave = _seg(_hit, _hit + 0.35);
          final shakeT = _seg(_hit, _hit + 0.12, Curves.linear);
          final shake = v > _hit && shakeT < 1
              ? math.sin(shakeT * math.pi * 6) * 6 * (1 - shakeT)
              : 0.0;
          final glint = _seg(0.62, 0.9, Curves.easeInOut);
          final bar = _seg(0.05, 1, Curves.easeInOut);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Topli sjaj iza znaka nakon udarca.
              Center(
                child: Container(
                  width: 360,
                  height: 360,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _accent.withValues(alpha: 0.30 * wave),
                        _accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(shake, 0),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 150,
                        height: 150,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            // Udarni val.
                            if (v > _hit && wave < 1)
                              CustomPaint(
                                size: const Size.square(150),
                                painter: _WavePainter(wave, _accent),
                              ),
                            // Trag leta.
                            if (fly > 0 && fly < 1)
                              Transform.translate(
                                offset: flyOffset * 1.25,
                                child: Opacity(
                                  opacity: 0.25,
                                  child: SizedBox.square(
                                    dimension: 120,
                                    child: CustomPaint(
                                      painter: SpearPainter(
                                        head: _accent,
                                        shaft: _cream,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Transform.translate(
                              offset: flyOffset,
                              child: SizedBox.square(
                                dimension: 120,
                                child: CustomPaint(
                                  painter: SpearPainter(
                                    head: _accent,
                                    shaft: _cream,
                                    glint: glint,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (i, ch)
                              in kAppName.toUpperCase().split('').indexed)
                            Builder(
                              builder: (_) {
                                final l = _seg(
                                  _hit + 0.05 + i * 0.04,
                                  _hit + 0.25 + i * 0.04,
                                  Curves.easeOutBack,
                                );
                                return Opacity(
                                  opacity: l.clamp(0.0, 1.0),
                                  child: Transform.translate(
                                    offset: Offset(0, -22 * (1 - l)),
                                    child: Text(
                                      ch,
                                      style: const TextStyle(
                                        fontFamily: kFontFamily,
                                        color: Colors.white,
                                        fontSize: 38,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 4,
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
                        opacity: _seg(0.65, 0.9),
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
                        color: _accent,
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

/// Udarni val: dva prstena koji se šire i blijede.
class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (final (delay, width) in const [(0.0, 5.0), (0.18, 3.0)]) {
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      canvas.drawCircle(
        c,
        20 + 110 * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * (1 - p) + 0.5
          ..color = color.withValues(alpha: 0.8 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t;
}
