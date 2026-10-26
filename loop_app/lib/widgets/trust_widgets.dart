import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

/// "Zaštita kupca": novac čeka kod LOOP-a dok kupac ne potvrdi primitak.
/// Dodir otvara kratko objašnjenje. [dark] za tamnu pozadinu (live, feed).
class BuyerProtectionBadge extends StatelessWidget {
  const BuyerProtectionBadge({
    super.key,
    this.dark = false,
    this.compact = false,
  });

  final bool dark;
  final bool compact;

  static Future<void> explain(
    BuildContext context,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          key: const ValueKey('protection-info'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user, color: LoopColors.buyNow),
                const SizedBox(width: 8),
                Text(
                  t('Zaštita kupca'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final line in [
              t('Plaćaš LOOP-u, ne prodavaču — novac čeka kod nas.'),
              t('Prodavač dobije novac tek kad potvrdiš da je paket stigao.'),
              t(
                'Ako predmet ne stigne ili nije kao u opisu, vraćamo ti novac.',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 18,
                      color: LoopColors.buyNow,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(line)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final color = dark ? const Color(0xFF4ADE80) : LoopColors.buyNow;
    return InkWell(
      key: const ValueKey('buyer-protection'),
      borderRadius: BorderRadius.circular(99),
      onTap: () => explain(context),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user, size: compact ? 13 : 15, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                compact
                    ? t('Zaštita kupca')
                    : t('Zaštita kupca · novac čeka do primitka'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 11 : 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Povjerenje u prodavača: ocjena, broj prodaja, prosječno vrijeme slanja
/// i značka "Provjeren prodavač".
class SellerTrustCard extends ConsumerWidget {
  const SellerTrustCard({super.key, required this.user});
  final AppUser user;

  /// Provjeren: potvrđen e-mail i ispunjeni podaci prodavatelja.
  static bool isVerified(AppUser u) => u.emailVerified && u.seller != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final rating = s.ratingOf(user.id);
    final sales = s.salesCountOf(user.id);
    final shipped = [
      for (final d in s.deliveries)
        if (d.sellerId == user.id && d.startedAt != null)
          d.startedAt!.difference(d.createdAt),
    ];
    final String shipLabel;
    if (shipped.isEmpty) {
      shipLabel = '—';
    } else {
      final avg =
          shipped.fold<int>(0, (a, d) => a + d.inMinutes) / shipped.length;
      final days = (avg / (60 * 24)).ceil();
      shipLabel = days <= 1 ? t('< 1 dan') : t('{0} dana', ['$days']);
    }
    Widget stat(String value, String label, Key key) => Expanded(
      child: Column(
        key: key,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
    return Card(
      key: const ValueKey('seller-trust'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        child: Column(
          children: [
            if (isVerified(user))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  key: const ValueKey('seller-verified'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, color: LoopColors.info, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      t('Provjeren prodavač'),
                      style: TextStyle(
                        color: LoopColors.info,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                stat(
                  rating.count == 0
                      ? '—'
                      : '★ ${rating.average.toStringAsFixed(1)}',
                  rating.count == 0
                      ? t('još bez ocjena')
                      : t('{0} ocjena', ['${rating.count}']),
                  const ValueKey('trust-rating'),
                ),
                stat('$sales', t('prodaja'), const ValueKey('trust-sales')),
                stat(
                  shipLabel,
                  t('prosječno slanje'),
                  const ValueKey('trust-ship'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
