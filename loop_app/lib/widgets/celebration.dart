import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'item_image.dart';

/// Slavlje preko cijelog ekrana kao na Whatnotu: konfeti, veliki naslov
/// ("Kupljeno!", "Osvojio si!"), slika predmeta i cijena. Nestaje samo
/// nakon ~2,8 s ili na dodir.
Future<void> showCelebration(
  BuildContext context, {
  required String title,
  String? subtitle,
  Device? device,
  double? amount,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, _, _) => _Celebration(
      title: title,
      subtitle: subtitle,
      device: device,
      amount: amount,
    ),
    transitionBuilder: (_, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.9,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}

class _Celebration extends StatefulWidget {
  const _Celebration({
    required this.title,
    this.subtitle,
    this.device,
    this.amount,
  });

  final String title;
  final String? subtitle;
  final Device? device;
  final double? amount;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..forward().whenComplete(_close);

  bool _closed = false;

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    return GestureDetector(
      key: const ValueKey('celebration'),
      behavior: HitTestBehavior.opaque,
      onTap: _close,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) =>
                  CustomPaint(painter: _ConfettiPainter(_c.value)),
            ),
          ),
          Center(
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (d != null)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: const [
                          BoxShadow(blurRadius: 24, color: Colors.black45),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ItemThumb(device: d, size: 150),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      shadows: [Shadow(blurRadius: 12, color: Colors.black54)],
                    ),
                  ),
                  if (d != null || widget.amount != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (d != null) d.name,
                        if (widget.amount != null)
                          formatCredits(widget.amount!),
                      ].join(' · '),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                      ),
                    ),
                  ],
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: LoopColors.accent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        widget.subtitle!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: LoopColors.onAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    t('Dodirni za nastavak'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Konfeti padaju odozgo i lagano se vrte (isti uzorak svaki put).
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);
  final double t;

  static const _colors = [
    Color(0xFFFF5A5F),
    Color(0xFFFFC233),
    Color(0xFF2EC4B6),
    Color(0xFF3A86FF),
    Color(0xFFFF8A5C),
    Color(0xFFFFFFFF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 90; i++) {
      final x0 = rnd.nextDouble() * size.width;
      final delay = rnd.nextDouble() * 0.35;
      final speed = 0.7 + rnd.nextDouble() * 0.8;
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final y = -20 + p * speed * (size.height + 60);
      final x = x0 + math.sin(p * 10 + i) * 18;
      paint.color = _colors[i % _colors.length].withValues(
        alpha: p > 0.85 ? (1 - p) / 0.15 : 1,
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p * 8 + i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 9, height: 14),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// Jednokratni pljusak konfeta preko roditelja (npr. "Prodano" u liveu).
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_c.value)),
  );
}
