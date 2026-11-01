import '../config/features.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_device_screen.dart';
import 'seller_screens.dart' show ensureSellerInfo;

import '../models/auction.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/auction_policy.dart';
import '../services/auction_service.dart';
import '../services/fee.dart';
import '../services/market_filter.dart' show normalizeSearch, searchMatches;
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
  Duration _duration = AuctionService.durations[2].$2;
  String? _error;

  /// Pretraga predmeta (naziv, model, kategorija, opis).
  final _search = TextEditingController();
  String _query = '';

  /// Odabir predmeta je otvoren (nakon odabira se skupi u jedan red).
  bool _picking = true;

  @override
  void initState() {
    super.initState();
    if (widget.deviceId != null) _select(widget.deviceId!);
  }

  @override
  void dispose() {
    _search.dispose();
    _start.dispose();
    super.dispose();
  }

  void _select(String id) {
    final d = ref.read(appProvider).deviceById(id);
    setState(() {
      _deviceId = id;
      _picking = false;
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
    if (blockGuest(context)) return;
    if (!await ensureSellerInfo(context) || !mounted) return;
    final price = _price;
    if (_deviceId == null) return;
    if (price == null || price <= 0) {
      setState(() => _error = t('Unesi početnu cijenu veću od 0'));
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
              message: t('Dodaj predmet pa ga stavi na aukciju.'),
              action: FilledButton.icon(
                key: const ValueKey('auction-new-item'),
                onPressed: () => AddDeviceScreen.open(context),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(t('Novi predmet')),
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Granice se prikazuju tek kad su blizu.
                    if (policy.activeCount(me) >= policy.maxActiveFor(me) - 1 ||
                        policy.createdLast24h(me) >=
                            policy.maxNewPerDayFor(me) - 1) ...[
                      _LimitsCard(
                        active: policy.activeCount(me),
                        maxActive: policy.maxActiveFor(me),
                        today: policy.createdLast24h(me),
                        maxToday: policy.maxNewPerDayFor(me),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      t('1. Odaberi predmet'),
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (selected != null && !_picking)
                      // Odabrani predmet u jednom redu + promjena.
                      _DeviceRow(
                        key: const ValueKey('auction-selected'),
                        device: selected,
                        selected: true,
                        onTap: () => setState(() => _picking = true),
                        trailing: TextButton(
                          key: const ValueKey('auction-change-item'),
                          onPressed: () => setState(() => _picking = true),
                          child: Text(t('Promijeni')),
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('auction-item-search'),
                              controller: _search,
                              textInputAction: TextInputAction.search,
                              onChanged: (v) => setState(() => _query = v),
                              decoration: InputDecoration(
                                hintText: t('Traži svoje predmete…'),
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: t('Očisti'),
                                        icon: const Icon(Icons.close),
                                        onPressed: () => setState(() {
                                          _search.clear();
                                          _query = '';
                                        }),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            key: const ValueKey('auction-new-item'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 52),
                            ),
                            onPressed: () => AddDeviceScreen.open(context),
                            icon: const Icon(Icons.add),
                            label: Text(t('Predmet')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final terms = normalizeSearch(
                            _query,
                          ).split(RegExp(r'\s+')).where((x) => x.isNotEmpty);
                          final shown = [
                            for (final d in eligible)
                              if (terms.isEmpty ||
                                  searchMatches(
                                    '${d.name} ${d.model} '
                                    '${d.category.label} ${d.description}',
                                    terms,
                                  ))
                                d,
                          ];
                          if (shown.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                t('Nema predmeta za tu pretragu.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: LoopColors.textSecondary,
                                ),
                              ),
                            );
                          }
                          return Column(
                            key: const ValueKey('auction-item-list'),
                            children: [
                              for (final d in shown)
                                _DeviceRow(
                                  key: ValueKey('auction-item-${d.id}'),
                                  device: d,
                                  selected: d.id == _deviceId,
                                  onTap: () => _select(d.id),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
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
                          LengthLimitingTextInputFormatter(9),
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
                      if (kBuyNowEnabled)
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
                      if (kBuyNowEnabled) ...[
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
                  ],
                ),
              ),
            ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    super.key,
    required this.device,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final Device device;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = device.category.color;
    final title = '${device.name} ${device.model}'.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadius),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.14) : LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(
              color: selected ? c : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              ItemThumb(device: device, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${device.category.label} · '
                      '${formatCredits(device.price)} · '
                      '${formatDate(device.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    selected ? Icons.check_circle : Icons.chevron_right,
                    color: selected ? c : LoopColors.textSecondary,
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
    required this.maxToday,
  });

  final int active;
  final int maxActive;
  final int maxToday;
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
                meter(t('Objavljeno u 24 h'), today, maxToday),
              ],
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
