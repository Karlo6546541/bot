import '../services/app_location/app_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auction.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../theme/app_theme.dart';
import '../widgets/auction_widgets.dart';
import '../widgets/countdown.dart';
import '../widgets/dutch_price.dart';
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
          settings: AppPlace.of('auction', auctionId).settings,
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

  Future<void> _takeDutch(Auction a, double price) async {
    final ok = await confirmDialog(
      context,
      title: t('Kupiti za {0}?', [formatCredits(price)]),
      message: t('Cijena pada, ali kupnja je obvezujuća po ovom iznosu.'),
      confirmLabel: t('Kupi'),
    );
    if (!ok || !mounted) return;
    await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).takeDutchAuction(a.id, price: price),
      successMessage: t('Kupljeno!'),
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
    final canBid =
        a.kind == AuctionKind.classic &&
        a.isActive &&
        a.sellerId != me &&
        a.highestBid?.userId != me;
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
                          if (a.kind != AuctionKind.classic)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Chip(
                                key: const ValueKey('auction-kind'),
                                label: Text(a.kind.label),
                                visualDensity: VisualDensity.compact,
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
                                  a.isDutch && a.isActive
                                      ? t('Trenutna cijena (pada)')
                                      : a.bidsHidden
                                      ? t('Najmanja ponuda')
                                      : a.bids.isEmpty
                                      ? t('Početna cijena')
                                      : t('Najviša ponuda'),
                                  style: TextStyle(
                                    color: LoopColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                if (a.isDutch && a.isActive)
                                  DutchPrice(
                                    auction: a,
                                    builder: (_, price) => Text(
                                      formatCredits(price),
                                      key: const ValueKey('dutch-price'),
                                      style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  )
                                else
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
              if (a.isDutch && a.isActive && a.sellerId != me) ...[
                _InfoBox(
                  icon: Icons.south,
                  text: t(
                    'Holandska aukcija: cijena pada do {0}. Tko prvi pristane na trenutnu cijenu — kupuje.',
                    [formatCredits(a.floorPrice)],
                  ),
                ),
                const SizedBox(height: 8),
                DutchPrice(
                  auction: a,
                  builder: (_, price) => FilledButton(
                    key: const ValueKey('dutch-take'),
                    onPressed: () => _takeDutch(a, price),
                    child: Text(t('Kupi za {0}', [formatCredits(price)])),
                  ),
                ),
              ],
              if (a.isSealed && a.isActive && a.sellerId != me)
                _SealedBidBox(auction: a, me: me),
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
              if (a.isActive && a.sellerId == me) ...[
                _InfoBox(
                  icon: Icons.info_outline,
                  text: a.bidsHidden
                      ? t(
                          'Zatvorena aukcija: ponude su skrivene do kraja (zasad {0}). Aukciju možeš otkazati dok nema ponuda.',
                          ['${a.bids.length}'],
                        )
                      : a.isDutch
                      ? t(
                          'Holandska aukcija: cijena pada do {0}. Prodaje se prvom kupcu koji pristane na trenutnu cijenu.',
                          [formatCredits(a.floorPrice)],
                        )
                      : a.bids.isEmpty
                      ? t('Aukciju možeš otkazati dok nema ponuda.')
                      : t(
                          'Aukcija ima ponude i ne može se otkazati. Po završetku dobivaš {0} (provizija je 10 % samo od razlike iznad početne cijene).',
                          [
                            formatCredits(
                              auctionPayout(a.currentPrice, a.commissionBase),
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
    if (auction.bidsHidden) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: LoopColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('Ponude su skrivene do kraja aukcije ({0})', [
                    '${auction.bids.length}',
                  ]),
                  key: const ValueKey('sealed-hidden'),
                ),
              ),
            ],
          ),
        ),
      );
    }
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

/// Zatvorena aukcija: jedna skrivena ponuda koju korisnik smije samo povisiti.
class _SealedBidBox extends ConsumerStatefulWidget {
  const _SealedBidBox({required this.auction, required this.me});
  final Auction auction;
  final String me;

  @override
  ConsumerState<_SealedBidBox> createState() => _SealedBidBoxState();
}

class _SealedBidBoxState extends ConsumerState<_SealedBidBox> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final amount = double.tryParse(_c.text.trim().replaceAll(',', '.'));
    if (amount == null) {
      showLoopSnackBar(t('Upiši iznos ponude.'), error: true);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: t('Poslati zatvorenu ponudu {0}?', [formatCredits(amount)]),
      message: t(
        'Ponuda je obvezujuća i skrivena do kraja. Možeš je samo povisiti. Pobjednik plaća svoj iznos.',
      ),
      confirmLabel: t('Pošalji ponudu'),
    );
    if (!ok || !mounted) return;
    await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).placeBid(widget.auction.id, amount),
      successMessage: t('Ponuda poslana'),
    );
    if (mounted) _c.clear();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.auction;
    final mine = [
      for (final b in a.bids)
        if (b.userId == widget.me) b,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoBox(
          icon: Icons.lock_outline,
          text: mine.isEmpty
              ? t(
                  'Zatvorena aukcija: pošalji jednu skrivenu ponudu (najmanje {0}). Najviša pobjeđuje i plaća svoj iznos.',
                  [formatCredits(a.startPrice)],
                )
              : t(
                  'Tvoja zatvorena ponuda je {0}. Možeš je samo povisiti do kraja aukcije.',
                  [formatCredits(mine.last.amount)],
                ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('sealed-amount'),
          controller: _c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: mine.isEmpty
                ? t('Tvoja zatvorena ponuda (€)')
                : t('Nova viša ponuda (€)'),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('sealed-submit'),
          onPressed: _send,
          icon: const Icon(Icons.lock_outline),
          label: Text(t('Pošalji ponudu')),
        ),
      ],
    );
  }
}
