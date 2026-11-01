import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ime aplikacije. "Subhasto" dolazi od latinskog *sub hasta* — "pod
/// kopljem": u starom Rimu javna prodaja (dražba) održavala se ispod
/// koplja zabodenog u zemlju. Odatle znak: koplje s listastim vrhom.
const kAppName = 'Subhasto';

/// Znak Subhasta: koplje pod 45° — drška, vezica i listasti vrh s
/// rebrom. [head] je boja vrha (akcent), [shaft] boja drške.
class SpearMark extends StatelessWidget {
  const SpearMark({
    super.key,
    this.size = 28,
    required this.head,
    required this.shaft,
  });

  final double size;
  final Color head;
  final Color shaft;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: SpearPainter(head: head, shaft: shaft),
    ),
  );
}

/// Crta koplje u kvadrat. [glint] 0–1: bijeli odsjaj koji jednom prijeđe
/// preko vrha (uvodna animacija); izvan toga raspona nema odsjaja.
class SpearPainter extends CustomPainter {
  SpearPainter({required this.head, required this.shaft, this.glint = -1});

  final Color head;
  final Color shaft;
  final double glint;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    // Koplje leži na osi x (vrh desno), pa se zakrene prema gore-desno.
    canvas.rotate(-math.pi / 4);
    canvas.scale(s);

    // Drška.
    canvas.drawLine(
      const Offset(-0.58, 0),
      const Offset(0.08, 0),
      Paint()
        ..color = shaft
        ..strokeWidth = 0.065
        ..strokeCap = StrokeCap.round,
    );
    // Okov na dnu drške.
    canvas.drawPath(
      Path()
        ..moveTo(-0.66, 0)
        ..lineTo(-0.56, -0.05)
        ..lineTo(-0.52, 0)
        ..lineTo(-0.56, 0.05)
        ..close(),
      Paint()..color = head,
    );
    // Poprečni graničnik ispod vrha.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(0.07, 0),
          width: 0.05,
          height: 0.24,
        ),
        const Radius.circular(0.025),
      ),
      Paint()..color = head,
    );
    // Oštar (romboidni) vrh.
    final leaf = Path()
      ..moveTo(0.1, 0)
      ..lineTo(0.27, -0.11)
      ..lineTo(0.64, 0)
      ..lineTo(0.27, 0.11)
      ..close();
    canvas.drawPath(leaf, Paint()..color = head);
    // Rebro vrha (svjetlije).
    canvas.drawLine(
      const Offset(0.15, 0),
      const Offset(0.56, 0),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 0.02
        ..strokeCap = StrokeCap.round,
    );
    if (glint > 0 && glint < 1) {
      final x = 0.1 + 0.54 * glint;
      canvas.save();
      canvas.clipPath(leaf);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, 0), width: 0.07, height: 0.5),
        Paint()..color = Colors.white.withValues(alpha: 0.75),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SpearPainter old) =>
      old.head != head || old.shaft != shaft || old.glint != glint;
}
