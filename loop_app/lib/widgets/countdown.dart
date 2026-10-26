import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../l10n/tr.dart';

/// Odbrojavanje do kraja aukcije. Osvježava se prema [tickIntervalProvider]
/// (u testovima je statično).
class AuctionCountdown extends ConsumerStatefulWidget {
  const AuctionCountdown({
    super.key,
    required this.endsAt,
    this.style,
    this.showIcon = true,
  });

  final DateTime endsAt;
  final TextStyle? style;
  final bool showIcon;

  /// "2 d 4 h", "3 h 05 min", "04:59", "Završava…"
  static String format(Duration left) {
    if (left <= Duration.zero) return t('Završava…');
    final d = left.inDays;
    final h = left.inHours % 24;
    final m = left.inMinutes % 60;
    final s = left.inSeconds % 60;
    if (d > 0) return t('{0} d {1} h', [d, h]);
    if (h > 0) return t('{0} h {1} min', [h, m.toString().padLeft(2, '0')]);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  ConsumerState<AuctionCountdown> createState() => _AuctionCountdownState();
}

class _AuctionCountdownState extends ConsumerState<AuctionCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final every = ref.read(tickIntervalProvider);
    if (every != null) {
      _timer = Timer.periodic(every, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.endsAt.difference(DateTime.now());
    // Zadnjih 5 minuta: upozorenje (ikona + tekst, ne samo boja).
    final urgent = left < const Duration(minutes: 5);
    final color = urgent ? LoopColors.admin : LoopColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showIcon) ...[
          Icon(
            urgent ? Icons.timer_outlined : Icons.schedule,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 4),
        ],
        Text(
          AuctionCountdown.format(left),
          style: (widget.style ?? const TextStyle(fontSize: 13)).copyWith(
            color: urgent ? LoopColors.admin : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Periodički zaključuje istekle aukcije dok je aplikacija otvorena
/// (nema servera, pa to radi klijent).
class AuctionHeartbeat extends ConsumerStatefulWidget {
  const AuctionHeartbeat({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AuctionHeartbeat> createState() => _AuctionHeartbeatState();
}

class _AuctionHeartbeatState extends ConsumerState<AuctionHeartbeat> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final every = ref.read(tickIntervalProvider);
    // Odmah pri pokretanju, pa svakih nekoliko sekundi.
    WidgetsBinding.instance.addPostFrameCallback((_) => _settle());
    if (every != null) {
      _timer = Timer.periodic(every * 3, (_) => _settle());
    }
  }

  void _settle() {
    if (!mounted) return;
    ref.read(appProvider.notifier).settleExpiredAuctions();
    ref.read(appProvider.notifier).autoConfirmPickups();
    ref.read(appProvider.notifier).publishTraderFlag();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
