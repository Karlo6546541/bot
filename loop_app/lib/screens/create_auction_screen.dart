import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'seller_screens.dart';

import '../models/auction.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/auction_policy.dart';
import '../services/auction_service.dart';
import '../services/fee.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/trade_actions.dart';
import 'auction_detail_screen.dart';
import '../l10n/tr.dart';

/// Objava aukcije za predmet iz vlastitog portfolija.
class CreateAuctionScreen extends ConsumerStatefulWidget {
  const CreateAuctionScreen({super.key, this.deviceId});

  /// Unaprijed odabrani predmet (npr. s ekrana detalja).
  final String? deviceId;

  static Future<void> open(BuildContext context, {String? deviceId}) async {
    if (blockGuest(context)) return;
    if (!await ensureSellerInfo(context) || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateAuctionScreen(deviceId: deviceId),
      ),
    );
  }

  @override
  ConsumerState<CreateAuctionScreen> createState() =>
      _CreateAuctionScreenState();
}

class _CreateAuctionScreenState extends ConsumerState<CreateAuctionScreen> {
  String? _deviceId;
  final _start = TextEditingController();
  final _buyNow = TextEditingController();
  String? _buyNowError;
  Duration _duration = AuctionService.durations[2].$2;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.deviceId != null) _select(widget.deviceId!);
  }

  @override
  void dispose() {
    _start.dispose();
    _buyNow.dispose();
    super.dispose();
  }

  void _select(String id) {
    final d = ref.read(appProvider).deviceById(id);
    setState(() {
      _deviceId = id;
      // Prijedlog: početi od 60% vrijednosti predmeta.
      if (d != null) {
        _start.text = (d.price * 0.6).roundToDouble().toStringAsFixed(0);
      }
      _error = null;
    });
  }

  double? get _price =>
      double.tryParse(_start.text.trim().replaceAll(',', '.'));

  Future<void> _submit() async {
    final price = _price;
    if (_deviceId == null) return;
    if (price == null || price <= 0) {
      setState(() => _error = t('Unesi početnu cijenu veću od 0'));
      return;
    }
    final buyNowText = _buyNow.text.trim();
    final buyNow = buyNowText.isEmpty
        ? null
        : double.tryParse(buyNowText.replaceAll(',', '.'));
    if (buyNowText.isNotEmpty && (buyNow == null || buyNow <= price)) {
      setState(() => _buyNowError = t('Mora biti veće od početne cijene'));
      return;
    }
    Auction? created;
    final ok = await runWithLoading(
      context,
      () async => created = await ref
          .read(appProvider.notifier)
          .createAuction(
            deviceId: _deviceId!,
            startPrice: price,
            duration: _duration,
            buyNowPrice: buyNow,
          ),
      successMessage: t('Aukcija je objavljena'),
    );
    if (!ok || !mounted || created == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AuctionDetailScreen(auctionId: created!.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    // Samo vlastiti predmeti koji već nisu na aukciji.
    final eligible = s.myDevices
        .where((d) => s.activeAuctionFor(d.id) == null)
        .toList();
    final selected = _deviceId == null ? null : s.deviceById(_deviceId!);
    final me = s.currentUserId ?? '';
    final policy = ref.read(auctionServiceProvider).policy;
    final reason = selected == null ? null : policy.blockReason(me, selected);
    final fee = selected == null ? 0.0 : AuctionPolicy.listingFee(selected);

    return Scaffold(
      appBar: AppBar(title: Text(t('Nova aukcija'))),
      body: eligible.isEmpty && selected == null
          ? EmptyState(
              icon: Icons.inventory_2_outlined,
              title: t('Nemaš predmeta za aukciju'),
              message: t('Dodaj predmet ili kupi nešto.'),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _LimitsCard(
                      active: policy.activeCount(me),
                      maxActive: AuctionPolicy.maxActive,
                      today: policy.createdLast24h(me),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t('1. Odaberi predmet'),
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 112,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final d in eligible)
                            _DeviceChoice(
                              device: d,
                              selected: d.id == _deviceId,
                              onTap: () => _select(d.id),
                            ),
                        ],
                      ),
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        t('2. Početna cijena'),
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _start,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          labelText: t('Početna cijena'),
                          suffixText: t('€'),
                          helperText: t('Vrijednost predmeta: {0}', [
                            formatCredits(selected.price),
                          ]),
                          errorText: _error,
                        ),
                        onChanged: (_) => setState(() => _error = null),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('buy-now-price'),
                        controller: _buyNow,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          labelText: t('"Kupi odmah" cijena (neobavezno)'),
                          suffixText: t('€'),
                          helperText: t(
                            'Tko plati ovu cijenu, odmah osvaja predmet.',
                          ),
                          errorText: _buyNowError,
                        ),
                        onChanged: (_) => setState(() => _buyNowError = null),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        t('3. Trajanje'),
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (label, d) in AuctionService.durations)
                            ChoiceChip(
                              label: Text(label),
                              selected: _duration == d,
                              onSelected: (_) => setState(() => _duration = d),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: LoopColors.surface,
                          borderRadius: BorderRadius.circular(kRadius),
                        ),
                        child: Text(
                          t(
                            '• Dok aukcija traje, predmet je zaključan (ne može se prodati).\n• Aukciju možeš otkazati samo dok nema ponuda.\n• Objava je besplatna. Na kraju dobivaš najvišu ponudu umanjenu za 10 % od razlike iznad početne cijene{0}.\n• Ako nitko ne ponudi, predmet ostaje tebi.',
                            [
                              _price != null && _price! > 0
                                  ? t(' (najmanje {0})', [
                                      formatCredits(_price!),
                                    ])
                                  : '',
                            ],
                          ),
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _CompareCard(device: selected, fee: fee),
                      const SizedBox(height: 16),
                      if (reason != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: LoopColors.sunny,
                            borderRadius: BorderRadius.circular(kRadius),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton.icon(
                        // Blokirano pravilima → gumb je onemogućen (razlog je iznad).
                        onPressed: reason == null ? _submit : null,
                        icon: const Icon(Icons.gavel),
                        label: Text(
                          fee > 0
                              ? t('Objavi aukciju · naknada {0}', [
                                  formatCredits(fee),
                                ])
                              : t('Objavi aukciju'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await showListDialog(
                            context,
                            ref,
                            selected,
                          );
                          if (ok && context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.storefront_outlined),
                        label: Text(t('Radije prodaj na Kupi odmah')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _DeviceChoice extends StatelessWidget {
  const _DeviceChoice({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final Device device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = device.category.color;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 150,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.16) : LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(
              color: selected ? c : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ItemThumb(device: device, size: 40),
              const Spacer(),
              Text(
                device.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                formatCredits(device.price),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Koliko aukcija korisnik smije imati i koliko je danas objavio.
class _LimitsCard extends StatelessWidget {
  const _LimitsCard({
    required this.active,
    required this.maxActive,
    required this.today,
  });

  final int active;
  final int maxActive;
  final int today;

  @override
  Widget build(BuildContext context) {
    Widget meter(String label, int value, int max) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
          ),
          Text(
            '$value / $max',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (value / max).clamp(0, 1),
              minHeight: 6,
              color: value >= max ? LoopColors.error : LoopColors.accent,
              backgroundColor: LoopColors.surfaceHover,
            ),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                meter(t('Aktivne aukcije'), active, maxActive),
                const SizedBox(width: 16),
                meter(
                  t('Objavljeno u 24 h'),
                  today,
                  AuctionPolicy.maxNewPerDay,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              t(
                'Aukcije su za vrijedne predmete (od {0}). Za sve ostalo je Market.',
                [formatCredits(AuctionPolicy.minItemValue)],
              ),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Usporedba: prodaj odmah (sigurno, bez naknade) ili aukcija (naknada,
/// ishod neizvjestan).
class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.device, required this.fee});
  final Device device;
  final double fee;

  @override
  Widget build(BuildContext context) {
    Widget col(String emoji, String title, List<String> lines, Color bg) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$emoji $title',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      l,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ),
              ],
            ),
          ),
        );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          col('🏷️', t('Kupi odmah'), [
            t('Prodaješ po svojoj cijeni (dobivaš {0})', [
              formatCredits(sellPayout(device.price)),
            ]),
            t('Provizija 5 %'),
            t('Kupci mogu ponuditi cijenu'),
          ], LoopColors.mint),
          const SizedBox(width: 10),
          col('🔨', t('Aukcija'), [
            t('Objava je besplatna'),
            t('Provizija 10 % samo od razlike iznad početne cijene'),
            t('Ishod nije siguran'),
          ], LoopColors.lilac),
        ],
      ),
    );
  }
}
