import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/delivery.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'seller_hub.dart' show AccountHealth, HealthLevel;

/// Zdravlje računa kao Whatnot: poruka o stanju, prstenovi učinka
/// (pravovremena predaja, uspješna isporuka, ocjena kupaca) i stanje
/// pravila zajednice.
class AccountHealthScreen extends ConsumerWidget {
  const AccountHealthScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const AccountHealthScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final user = s.currentUser;
    if (user == null || user.isGuest) return const SizedBox.shrink();
    final h = AccountHealth.of(s, user.id, DateTime.now());
    final level = h.level;
    final banner = switch (level) {
      HealthLevel.excellent => t('Odlično! Tvoj račun je u dobrom stanju.'),
      HealthLevel.good => t('Dobro. Još malo do odličnog stanja.'),
      HealthLevel.attention => t(
        'Račun treba pažnju. Pogledaj što se može poboljšati.',
      ),
      HealthLevel.fresh => t('Novi račun: stanje se računa od prve prodaje.'),
    };
    final muted = TextStyle(color: LoopColors.textSecondary, fontSize: 13);

    return Scaffold(
      appBar: AppBar(title: Text(t('Zdravlje računa'))),
      body: ListView(
        key: const ValueKey('account-health'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            key: ValueKey('health-banner-${level.name}'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: level.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: Row(
              children: [
                Icon(
                  level == HealthLevel.attention
                      ? Icons.error_outline
                      : Icons.verified_outlined,
                  color: level.color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    banner,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            t('Učinak prodavača'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            t(
              'Udio narudžbi u kojima je kupac imao dobro iskustvo: paket predan dostavljaču u roku od 48 sati i uspješno isporučen. Rijetko je 100 %, jer kupce štiti Zaštita kupca i kad greška nije tvoja.',
            ),
            style: muted,
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 12,
            runSpacing: 16,
            children: [
              _Ring(
                key: const ValueKey('ring-on-time'),
                value: h.onTimeRate,
                label: t('Pravovremena predaja'),
              ),
              _Ring(
                key: const ValueKey('ring-delivery'),
                value: h.deliveryRate,
                label: t('Uspješna isporuka'),
              ),
              _Ring(
                key: const ValueKey('ring-rating'),
                value: h.ratingCount == 0 ? null : h.ratingAverage / 5,
                label: t('Ocjena kupaca'),
                text: h.ratingCount == 0
                    ? null
                    : '★ ${h.ratingAverage.toStringAsFixed(1)}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              t('{0} pošiljaka · {1} ocjena', [
                '${h.shipments}',
                '${h.ratingCount}',
              ]),
              style: muted,
            ),
          ),
          const SizedBox(height: 22),
          Divider(color: LoopColors.surfaceHover),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                t('Pravila zajednice'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                key: ValueKey('policy-${h.policy.name}'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: h.policy.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  h.policy.label,
                  style: TextStyle(
                    color: h.policy.color,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            h.openReports + h.upheldReports == 0
                ? t(
                    'Nema prijava. Kršenja pravila zajednice ostaju vidljiva ovdje 180 dana.',
                  )
                : t(
                    'Prijave u zadnjih 180 dana: {0} u obradi, {1} potvrđeno. Ako misliš da je prijava greška, odgovori na poruku tima za sigurnost.',
                    ['${h.openReports}', '${h.upheldReports}'],
                  ),
            style: muted,
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: LoopColors.surface,
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Kako održati odlično stanje'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                for (final tip in [
                  t('Predaj paket u roku od {0} sati.', [
                    '${Delivery.handOverDeadline.inHours}',
                  ]),
                  t('Opiši stanje predmeta iskreno, s pravim fotografijama.'),
                  t('Odgovaraj kupcima u porukama isti dan.'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check, size: 18, color: LoopColors.success),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tip, style: muted)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Prsten s postotkom (zeleno ≥ 95 %, plavo ≥ 85 %, inače narančasto).
class _Ring extends StatelessWidget {
  const _Ring({super.key, required this.value, required this.label, this.text});

  /// 0…1, `null` = još nema podataka.
  final double? value;
  final String label;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final color = v == null
        ? LoopColors.textSecondary
        : v >= 0.95
        ? LoopColors.success
        : v >= 0.85
        ? LoopColors.info
        : LoopColors.accent;
    return SizedBox(
      width: 104,
      child: Column(
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: CustomPaint(
              painter: _RingPainter(
                value: v ?? 0,
                color: color,
                track: LoopColors.surfaceHover,
              ),
              child: Center(
                child: Text(
                  text ??
                      (v == null
                          ? '—'
                          : '${(v * 100).toStringAsFixed(v == 1 ? 0 : 1)} %'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track});

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}
