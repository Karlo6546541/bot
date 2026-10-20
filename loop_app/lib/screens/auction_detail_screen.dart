import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auction.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../theme/app_theme.dart';
import '../widgets/countdown.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/trade_actions.dart';
import 'auctions_screen.dart';

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
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double? get _parsed =>
      double.tryParse(_amount.text.trim().replaceAll(',', '.'));

  Future<void> _bid(Auction a) async {
    final amount = _parsed;
    final credits = ref.read(appProvider).currentUser?.credits ?? 0;
    // Iste provjere radi i servis; ovdje samo za brzu poruku uz polje.
    String? error;
    if (amount == null) {
      error = 'Unesi iznos';
    } else if (amount < a.minNextBid) {
      error = 'Najmanje ${formatCredits(a.minNextBid)}';
    } else if (amount > credits) {
      error = 'Imaš samo ${formatCredits(credits)}';
    }
    setState(() => _error = error);
    if (error != null) return;

    final ok = await confirmDialog(
      context,
      title: 'Potvrdi ponudu',
      message:
          'Nudiš ${formatCredits(amount!)} za "${a.deviceName}".\n\n'
          '• Ponuda je obvezujuća i NE MOŽE se povući.\n'
          '• Iznos se blokira s tvojih kredita dok te netko ne nadmaši.\n'
          '• Ako pobijediš, predmet automatski prelazi u tvoj portfolio.',
      confirmLabel: 'Licitiraj',
    );
    if (!ok || !mounted) return;
    final done = await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).placeBid(a.id, amount),
      successMessage: 'Ponuda prihvaćena — vodiš!',
    );
    if (done) _amount.clear();
  }

  Future<void> _cancel(Auction a) async {
    final ok = await confirmDialog(
      context,
      title: 'Otkazati aukciju?',
      message: 'Predmet ostaje u tvom portfoliju.',
      confirmLabel: 'Otkaži aukciju',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).cancelAuction(a.id),
      successMessage: 'Aukcija otkazana',
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
        body: const Center(child: Text('Aukcija ne postoji.')),
      );
    }
    final device = s.deviceById(a.deviceId);
    final role = AuctionRole.of(a, me);
    final credits = s.currentUser?.credits ?? 0;
    final canBid = a.isActive && a.sellerId != me && a.highestBid?.userId != me;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          device?.name ?? a.deviceName,
          overflow: TextOverflow.ellipsis,
        ),
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
                      Text(
                        a.sellerId == me
                            ? 'Tvoja aukcija'
                            : 'Prodaje ${a.sellerLabel}'
                                  '${device != null ? ' · ${device.condition.label} · ${device.category.singular}' : ''}',
                        style: const TextStyle(color: LoopColors.textSecondary),
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
                                      ? 'Početna cijena'
                                      : 'Najviša ponuda',
                                  style: const TextStyle(
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
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                a.isActive ? 'Završava za' : 'Status',
                                style: const TextStyle(
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
                                  a.status.label,
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
                          'Kraj: ${formatDateTime(a.endsAt)}'
                          '${device != null ? ' · procijenjena vrijednost ${formatCredits(device.price)}' : ''}',
                          style: const TextStyle(
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
              if (canBid) _bidForm(a, credits),
              if (a.isActive && role == AuctionRole.leading)
                const _InfoBox(
                  icon: Icons.lock_outline,
                  text:
                      'Vodiš! Tvoja ponuda je obvezujuća i ne može se povući '
                      'ni promijeniti dok te netko ne nadmaši. Iznos je '
                      'blokiran na tvom računu.',
                ),
              if (a.isActive && a.sellerId == me) ...[
                _InfoBox(
                  icon: Icons.info_outline,
                  text: a.bids.isEmpty
                      ? 'Aukciju možeš otkazati dok nema ponuda.'
                      : 'Aukcija ima ponude i ne može se otkazati. Po završetku '
                            'dobivaš ${formatCredits(sellPayout(a.currentPrice))} '
                            '(najviša ponuda − 5% fee).',
                ),
                if (a.bids.isEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _cancel(a),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: LoopColors.error,
                      side: const BorderSide(color: LoopColors.error),
                    ),
                    icon: const Icon(Icons.close),
                    label: const Text('Otkaži aukciju'),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              _BidHistory(auction: a, me: me),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bidForm(Auction a, double credits) {
    final min = a.minNextBid;
    final canAfford = credits >= min;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Najmanja ponuda: ${formatCredits(min)} · '
              'imaš ${formatCredits(credits)}',
              style: const TextStyle(color: LoopColors.textSecondary),
            ),
            const SizedBox(height: 10),
            if (!canAfford)
              const _InfoBox(
                icon: Icons.block,
                text:
                    'Nemaš dovoljno kredita za najmanju sljedeću ponudu. '
                    'Ponuda ne može biti veća od tvojih kredita.',
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in {
                    min,
                    roundCredits(min + a.minIncrement),
                    roundCredits(min + a.minIncrement * 3),
                  })
                    if (v <= credits)
                      ActionChip(
                        label: Text(formatCredits(v)),
                        onPressed: () => setState(() {
                          _amount.text = v.toStringAsFixed(2);
                          _error = null;
                        }),
                      ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Tvoja ponuda',
                  suffixText: 'LC',
                  errorText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _bid(a),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _bid(a),
                icon: const Icon(Icons.gavel),
                label: const Text('Licitiraj'),
              ),
            ],
          ],
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
              'Povijest ponuda (${bids.length})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (bids.isEmpty)
              Text(
                'Još nema ponuda. Početna cijena je '
                '${formatCredits(auction.startPrice)}.',
                style: const TextStyle(color: LoopColors.textSecondary),
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
                            ? 'Ti'
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
                      style: const TextStyle(
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
