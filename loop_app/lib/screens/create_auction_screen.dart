import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auction.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/auction_service.dart';
import '../services/fee.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/trade_actions.dart';
import 'auction_detail_screen.dart';

/// Objava aukcije za predmet iz vlastitog portfolija.
class CreateAuctionScreen extends ConsumerStatefulWidget {
  const CreateAuctionScreen({super.key, this.deviceId});

  /// Unaprijed odabrani predmet (npr. s ekrana detalja).
  final String? deviceId;

  static Future<void> open(BuildContext context, {String? deviceId}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CreateAuctionScreen(deviceId: deviceId),
        ),
      );

  @override
  ConsumerState<CreateAuctionScreen> createState() =>
      _CreateAuctionScreenState();
}

class _CreateAuctionScreenState extends ConsumerState<CreateAuctionScreen> {
  String? _deviceId;
  final _start = TextEditingController();
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
      setState(() => _error = 'Unesi početnu cijenu veću od 0');
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
      successMessage: 'Aukcija je objavljena',
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

    return Scaffold(
      appBar: AppBar(title: const Text('Nova aukcija')),
      body: eligible.isEmpty && selected == null
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Nemaš predmeta za aukciju',
              message: 'Dodaj predmet u portfolio ili kupi nešto u Marketu.',
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      '1. Odaberi predmet',
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
                      const Text(
                        '2. Početna cijena',
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
                          labelText: 'Početna cijena',
                          suffixText: 'kredita',
                          helperText:
                              'Vrijednost predmeta: ${formatCredits(selected.price)}',
                          errorText: _error,
                        ),
                        onChanged: (_) => setState(() => _error = null),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '3. Trajanje',
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
                          '• Dok aukcija traje, predmet je zaključan (ne može se '
                          'prodati).\n'
                          '• Aukciju možeš otkazati samo dok nema ponuda.\n'
                          '• Na kraju dobivaš najvišu ponudu − 5% fee'
                          '${_price != null && _price! > 0 ? ' (najmanje ${formatCredits(sellPayout(_price!))})' : ''}.\n'
                          '• Ako nitko ne ponudi, predmet ostaje tebi.',
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.gavel),
                        label: const Text('Objavi aukciju'),
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
