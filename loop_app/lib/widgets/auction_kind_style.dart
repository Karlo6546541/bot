import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/auction.dart';
import '../theme/app_theme.dart';

/// Izgled vrste aukcije (boja, ikona, opisi) — isti na kartici, popisu i
/// detaljima. Klasična: rastući graf · holandska: padajući · zatvorena:
/// omotnica.
extension AuctionKindStyle on AuctionKind {
  Color get color => switch (this) {
    AuctionKind.classic => LoopColors.classic,
    AuctionKind.dutch => LoopColors.dutch,
    AuctionKind.sealed => LoopColors.sealed,
  };

  IconData get icon => switch (this) {
    AuctionKind.classic => Icons.trending_up,
    AuctionKind.dutch => Icons.trending_down,
    AuctionKind.sealed => Icons.mail_outline,
  };

  /// Natpis iznad cijene na kartici.
  String get priceCaption => switch (this) {
    AuctionKind.classic => t('Trenutna ponuda'),
    AuctionKind.dutch => t('Cijena sada'),
    AuctionKind.sealed => t('Najmanja ponuda'),
  };
}

/// Mala oznaka vrste aukcije (ikona + naziv) na površini kartice.
class AuctionKindBadge extends StatelessWidget {
  const AuctionKindBadge({super.key, required this.kind});
  final AuctionKind kind;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
    decoration: BoxDecoration(
      color: LoopColors.surface,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(kind.icon, size: 14, color: kind.color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            kind.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: kind.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
