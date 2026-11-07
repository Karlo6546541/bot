import '../config/design_variant.dart';
import 'reference_order_row.dart';
import 'reference_sheet.dart';
import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../theme/app_theme.dart';
import 'item_image.dart';
import 'vision_glass.dart';

/// An order is a single ticket: the purchased object, then its receipt and actions.
class WalletTicket extends StatelessWidget {
  const WalletTicket({
    super.key,
    required this.title,
    required this.status,
    required this.date,
    this.price,
    this.seller,
    this.device,
    this.imagePath,
    this.onTap,
    this.openKey,
    this.statusKey,
    this.footer,
  });
  final String title, status;
  final DateTime date;
  final String? price, seller, imagePath;
  final Device? device;
  final VoidCallback? onTap;
  final Key? openKey, statusKey;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final photo =
        imagePath ??
        (device?.imagePaths.isNotEmpty == true
            ? device!.imagePaths.first
            : null);
    final fallback = device != null
        ? ItemIllustration(category: device!.category)
        : ColoredBox(
            color: LoopColors.surfaceHover,
            child: Center(
              child: Icon(
                Icons.inventory_2_outlined,
                size: kSimpleDesign ? 26 : 56,
                color: LoopColors.textSecondary,
              ),
            ),
          );
    final shortDate =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.'
        '${date.year == DateTime.now().year ? '' : date.year}';
    if (kSimpleDesign) {
      final art = photo == null
          ? fallback
          : LocalPhoto(path: photo, fallback: fallback, cacheWidth: 320);
      Color stateColor() {
        if (status == t('Čeka plaćanje')) return const Color(0xFFFFC176);
        if (status == t('Povrati') || status == t('Otkazano')) {
          return const Color(0xFFFF8F78);
        }
        if (status == t('Završeno') || status == t('Stiglo')) {
          return LoopColors.textSecondary;
        }
        return const Color(0xFF86F6D3);
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ReferenceOrderRow(
          key: openKey,
          title: title,
          subtitle: status,
          artwork: art,
          amount: price,
          date: shortDate,
          statusKey: statusKey,
          color: stateColor(),
          onTap: () => openReferenceSheet<void>(
            context,
            title: t('Detalji narudžbe'),
            builder: (_) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(width: 68, height: 68, child: art),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              status,
                              style: TextStyle(
                                color: stateColor(),
                                fontSize: 14,
                              ),
                            ),
                            if (price != null)
                              Text(
                                price!,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (seller != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      seller!,
                      style: TextStyle(color: LoopColors.textSecondary),
                    ),
                  ],
                  if (footer != null) ...[const SizedBox(height: 24), footer!],
                  if (onTap != null) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: Text(t('Pogledaj')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return VisionGlass(
      quiet: true,
      radius: 28,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: openKey,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: title,
                image: true,
                child: AspectRatio(
                  key: const ValueKey('wallet-artwork'),
                  aspectRatio: 1.8,
                  child: photo == null
                      ? fallback
                      : LocalPhoto(
                          path: photo,
                          fallback: fallback,
                          cacheWidth: 1000,
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            status,
                            key: statusKey,
                            style: TextStyle(
                              color: LoopColors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          shortDate,
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.6,
                      ),
                    ),
                    if (seller != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          seller!,
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    if (price != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          price!,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                    if (footer != null) ...[
                      const SizedBox(height: 18),
                      Divider(height: 1, color: LoopColors.glassBorder),
                      const SizedBox(height: 18),
                      footer!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Explicit stages only. -1 means unpaid; a pulse never advances the order.
class CinematicTracking extends StatefulWidget {
  const CinematicTracking({
    super.key,
    required this.stage,
    this.animate = true,
  });
  final int stage;
  final bool animate;
  static int stageForOrder(String status) => switch (status) {
    'paid' => 0,
    'shipped' => 1,
    'delivered' => 2,
    _ => -1,
  };
  @override
  State<CinematicTracking> createState() => _CinematicTrackingState();
}

class _CinematicTrackingState extends State<CinematicTracking>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  void _sync() {
    final run =
        widget.animate &&
        widget.stage >= 0 &&
        widget.stage < 2 &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (run && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!run) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant CinematicTracking oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.stage < 0
        ? t('Dostava još nije započela')
        : [t('Plaćeno'), t('Poslano'), t('Stiglo')][widget.stage.clamp(0, 2)],
    child: ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final accent = LoopColors.accent;
          return Column(
            children: [
              Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i <= widget.stage
                              ? accent
                              : LoopColors.glassBorder,
                        ),
                      ),
                    Container(
                      key: ValueKey(
                        'tracking-dot-$i-${i <= widget.stage ? 'active' : 'pending'}',
                      ),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i <= widget.stage
                            ? accent
                            : LoopColors.surfaceHover,
                        border: Border.all(
                          color: i <= widget.stage
                              ? accent
                              : LoopColors.textSecondary,
                        ),
                        boxShadow: i == widget.stage
                            ? [
                                BoxShadow(
                                  color: accent.withValues(
                                    alpha: .15 + _pulse.value * .25,
                                  ),
                                  blurRadius: 8 + _pulse.value * 6,
                                  spreadRadius: _pulse.value * 2,
                                ),
                              ]
                            : [],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final (i, text) in [
                    t('Plaćeno'),
                    t('Poslano'),
                    t('Stiglo'),
                  ].indexed)
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: i <= widget.stage
                            ? LoopColors.textPrimary
                            : LoopColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}
