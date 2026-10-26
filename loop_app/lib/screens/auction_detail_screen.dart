import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auction.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../theme/app_theme.dart';
import '../widgets/auction_widgets.dart';
import '../widgets/countdown.dart';
import '../widgets/formatters.dart';
import '../widgets/description_card.dart';
import '../widgets/item_image.dart';
import '../widgets/trade_actions.dart';
import 'auctions_screen.dart';
import '../l10n/tr.dart';
import '../widgets/trust_widgets.dart';
import 'public_profile_screen.dart';

/// Detalji aukcije: predmet, trenutna cijena, odbrojavanje, povijest ponuda
/// i obrazac za ponudu (s potvrdom da je ponuda obvezujuća).
class AuctionDetailScreen extends ConsumerStatefulWidget {
  const AuctionDetailScreen({super.key, required this.auctionId});

  final String auctionId;

  static Future<void> open(BuildContext context, String auctionId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AuctionDetailScreen(auctionId: auctionId),
        ),
      );

  @override
  ConsumerState<AuctionDetailScreen> createState() =>
      _AuctionDetailScreenState();
}

class _AuctionDetailScreenState extends ConsumerState<AuctionDetailScreen> {
  Future<void> _cancel(Auction a) async {
    final ok = await confirmDialog(
      context,
      title: t('Otkazati aukciju?'),
      message: t('Predmet ostaje u tvojim predmetima.'),
      confirmLabel: t('Otkaži aukciju'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).cancelAuction(a.id),
      successMessage: t('Aukcija otkazana'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final a = s.auctionById(widget.auctionId);
    final me = s.currentUserId;
    if (a == null || me == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(t('Aukcija ne postoji.'))),
      );
    }
    final device = s.deviceById(a.deviceId);
    final role = AuctionRole.of(a, me);
    final canBid = a.isActive && a.sellerId != me && a.highestBid?.userId != me;
    final myMax = a.autoMaxOf(me);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          device?.name ?? a.deviceName,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [WatchAuctionButton(auctionId: a.id)],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (device != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(kRadius * 1.5),
                  child: ItemGallery(
                    key: ValueKey(device.imagePaths.join('|')),
                    device: device,
                    height: 240,
                  ),
                ),
              const SizedBox(height: 16),
              // Cijena, odbrojavanje i status.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.deviceName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (role != AuctionRole.none) RoleBadge(role: role),
                        ],
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: a.sellerId == me
                            ? null
                            : () =>
                                  PublicProfileScreen.open(context, a.sellerId),
                        child: Text(
                          a.sellerId == me
                              ? t('Tvoja aukcija')
                              : t('Prodaje {0}{1}', [
                                  a.sellerLabel,
                                  device != null
                                      ? ' · ${device.condition.label} · ${device.category.singular}'
                                      : '',
                                ]),
                          style: TextStyle(color: LoopColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.bids.isEmpty
                                      ? t('Početna cijena')
                                      : t('Najviša ponuda'),
                                  style: TextStyle(
                                    color: LoopColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  formatCredits(a.currentPrice),
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Wrap(
                                  spacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  runSpacing: 4,
                                  children: [
                                    BuyerProtectionBadge(compact: true),
                                    WalletChip(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                a.isActive ? t('Završava za') : t('Status'),
                                style: TextStyle(
                                  color: LoopColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              if (a.isActive)
                                AuctionCountdown(
                                  endsAt: a.endsAt,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              else
                                Text(
                                  a.statusLabelFor(
                                    ref.read(appProvider).currentUserId,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (a.isActive) ...[
                        const SizedBox(height: 6),
                        Text(
                          t('Kraj: {0}{1}', [
                            formatDateTime(a.endsAt),
                            device != null
                                ? t(' · procijenjena vrijednost {0}', [
                                    formatCredits(device.price),
                                  ])
                                : '',
                          ]),
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (canBid) ...[
                Text(
                  t('Najmanja ponuda: {0}', [formatCredits(a.minNextBid)]),
                  style: TextStyle(color: LoopColors.textSecondary),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('open-bid'),
                  onPressed: () => showBidSheet(context, ref, a.id),
                  icon: const Icon(Icons.gavel),
                  label: Text(t('Licitiraj')),
                ),
              ],
              if (a.isActive && role == AuctionRole.leading) ...[
                _InfoBox(
                  icon: Icons.lock_outline,
                  text: myMax == null
                      ? t(
                          'Vodiš! Tvoja ponuda je obvezujuća i ne može se povući ni promijeniti dok te netko ne nadmaši. Iznos je blokiran na tvom računu.',
                        )
                      : t(
                          'Vodiš! Automatski licitiramo za tebe do {0} ako te netko pokuša nadmašiti. Ponuda je obvezujuća i ne može se povući.',
                          [formatCredits(myMax)],
                        ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('raise-auto'),
                  onPressed: () => showBidSheet(context, ref, a.id),
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: Text(
                    myMax == null
                        ? t('Postavi automatsku ponudu')
                        : t('Povisi automatsku ponudu'),
                  ),
                ),
              ],
              if (a.canBuyNow && a.sellerId != me) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('detail-buy-now'),
                  onPressed: () => showBidSheet(context, ref, a.id),
                  icon: const Icon(Icons.bolt),
                  label: Text(
                    t('Kupi odmah za {0}', [formatCredits(a.buyNowPrice!)]),
                  ),
                ),
              ],
              if (a.buyNowPrice != null && a.sellerId == me && a.isActive)
                _InfoBox(
                  icon: Icons.bolt,
                  text: t(
                    '"Kupi odmah" za {0} — vrijedi dok ponude ne dosegnu tu cijenu.',
                    [formatCredits(a.buyNowPrice!)],
                  ),
                ),
              if (a.isActive && a.sellerId == me) ...[
                _InfoBox(
                  icon: Icons.info_outline,
                  text: a.bids.isEmpty
                      ? t('Aukciju možeš otkazati dok nema ponuda.')
                      : t(
                          'Aukcija ima ponude i ne može se otkazati. Po završetku dobivaš {0} (provizija je 10 % samo od razlike iznad početne cijene).',
                          [
                            formatCredits(
                              auctionPayout(a.currentPrice, a.startPrice),
                            ),
                          ],
                        ),
                ),
                if (a.bids.isEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _cancel(a),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: LoopColors.error,
                      side: BorderSide(color: LoopColors.error),
                    ),
                    icon: const Icon(Icons.close),
                    label: Text(t('Otkaži aukciju')),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              if (device != null && device.description.isNotEmpty) ...[
                DescriptionCard(text: device.description),
                const SizedBox(height: 12),
              ],
              _BidHistory(auction: a, me: me),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LoopColors.surfaceHover,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: LoopColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}

class _BidHistory extends StatelessWidget {
  const _BidHistory({required this.auction, required this.me});
  final Auction auction;
  final String me;

  @override
  Widget build(BuildContext context) {
    final bids = auction.bids.reversed.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Povijest ponuda ({0})', [bids.length]),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (bids.isEmpty)
              Text(
                t('Još nema ponuda. Početna cijena je {0}.', [
                  formatCredits(auction.startPrice),
                ]),
                style: TextStyle(color: LoopColors.textSecondary),
              ),
            for (var i = 0; i < bids.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      i == 0 ? Icons.emoji_events : Icons.circle,
                      size: i == 0 ? 18 : 8,
                      color: i == 0
                          ? LoopColors.success
                          : LoopColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bids[i].userId == me
                            ? t('Ti')
                            : maskEmail(bids[i].userLabel),
                        style: TextStyle(
                          fontWeight: bids[i].userId == me
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      formatDateTime(bids[i].time),
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatCredits(bids[i].amount),
                      style: TextStyle(
                        fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
