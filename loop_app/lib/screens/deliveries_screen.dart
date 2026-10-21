import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delivery.dart';
import '../providers/app_providers.dart';
import '../services/delivery_service.dart';
import '../theme/app_theme.dart';
import '../widgets/delivery_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';
import '../l10n/tr.dart';

/// Moje dostave: pošiljke s vremenskom crtom statusa.
class DeliveriesScreen extends ConsumerStatefulWidget {
  const DeliveriesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const DeliveriesScreen()));

  @override
  ConsumerState<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends ConsumerState<DeliveriesScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Statusi se mijenjaju s vremenom — osvježi prikaz.
    final every = ref.read(tickIntervalProvider);
    if (every != null) {
      _timer = Timer.periodic(every * 2, (_) {
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
    final list = ref.watch(appProvider.select((s) => s.myDeliveries));
    return Scaffold(
      appBar: AppBar(title: Text(t('Moje dostave'))),
      body: list.isEmpty
          ? EmptyState(
              icon: Icons.local_shipping_outlined,
              title: t('Još nema dostava'),
              message: t(
                'Kad nešto kupiš ili osvojiš na aukciji, pošiljka će se pojaviti ovdje.',
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: LoopColors.sky,
                        borderRadius: BorderRadius.circular(kRadius),
                      ),
                      child: Text(
                        t(
                          '🚚 Demo: dostava je ubrzana — umjesto dana traje nekoliko minuta, pa statuse možeš pratiti uživo.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final d in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DeliveryCard(delivery: d),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class DeliveryCard extends ConsumerWidget {
  const DeliveryCard({super.key, required this.delivery});
  final Delivery delivery;

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final device = ref.read(appProvider).deviceById(delivery.deviceId);
    final methods = device == null
        ? DeliveryMethod.values
              .where((m) => m != DeliveryMethod.digital)
              .toList()
        : DeliveryService.methodsFor(device);
    final choice = await showModalBottomSheet<DeliveryChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: LoopColors.background,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _ChooseSheet(
        methods: methods,
        savedAddress: ref.read(appProvider).currentUser?.address,
      ),
    );
    if (choice == null || !context.mounted) return;
    await runWithLoading(
      context,
      () => ref
          .read(appProvider.notifier)
          .chooseDelivery(delivery.id, choice.method, choice.destination),
      successMessage: t('Dostava je krenula 🚚'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = delivery;
    final now = DateTime.now();
    final m = d.method;
    final steps = d.steps;
    final current = d.stepIndex(now);
    final delivered = d.isDelivered(now);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: delivered ? LoopColors.mint : LoopColors.peach,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    m == null
                        ? Icons.help_outline
                        : delivered
                        ? Icons.check_circle_outline
                        : deliveryIcon(m),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        m == null
                            ? t('Osvojeno na aukciji · odaberi dostavu')
                            : '${m.label}${d.destination != null ? ' · ${d.destination}' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (m == null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _choose(context, ref),
                icon: const Icon(Icons.local_shipping_outlined),
                label: Text(t('Odaberi dostavu')),
              ),
            ] else ...[
              const SizedBox(height: 14),
              // Vremenska crta statusa.
              Row(
                children: [
                  for (var i = 0; i < steps.length; i++) ...[
                    _Dot(done: i <= current, active: i == current),
                    if (i < steps.length - 1)
                      Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: i < current
                                ? LoopColors.success
                                : LoopColors.surfaceHover,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                steps[current].label,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (d.trackingNumber != null)
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: d.trackingNumber!),
                        );
                        showLoopSnackBar(t('Broj pošiljke kopiran'));
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            d.trackingNumber!,
                            style: TextStyle(
                              color: LoopColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.copy,
                            size: 14,
                            color: LoopColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  if (!delivered && d.eta() != null)
                    Text(
                      t('Stiže oko {0}', [formatDateTime(d.eta()!)]),
                      style: TextStyle(color: LoopColors.textSecondary),
                    ),
                  if (d.confirmedAt != null)
                    Text(
                      t('Primitak potvrđen ✅'),
                      style: TextStyle(color: LoopColors.success),
                    ),
                ],
              ),
              if (delivered && d.confirmedAt == null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => runWithLoading(
                    context,
                    () => ref.read(appProvider.notifier).confirmReceipt(d.id),
                    successMessage: t('Hvala! Primitak potvrđen.'),
                  ),
                  icon: const Icon(Icons.task_alt),
                  label: Text(t('Potvrdi primitak')),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.done, required this.active});
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 18 : 12,
      height: active ? 18 : 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? LoopColors.success : LoopColors.surfaceHover,
        border: active ? Border.all(color: LoopColors.mint, width: 4) : null,
      ),
    );
  }
}

class _ChooseSheet extends StatefulWidget {
  const _ChooseSheet({required this.methods, this.savedAddress});
  final List<DeliveryMethod> methods;
  final String? savedAddress;

  @override
  State<_ChooseSheet> createState() => _ChooseSheetState();
}

class _ChooseSheetState extends State<_ChooseSheet> {
  DeliveryChoice? _choice;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('Kako želiš preuzeti predmet?'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            DeliveryPicker(
              methods: widget.methods,
              savedAddress: widget.savedAddress,
              onChanged: (c) => setState(() {
                _choice = c;
                _error = null;
              }),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: LoopColors.error)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _choice == null
                  ? null
                  : () {
                      final err = DeliveryService.validate(
                        _choice!.method,
                        _choice!.destination,
                      );
                      if (err != null) {
                        setState(() => _error = err);
                        return;
                      }
                      Navigator.pop(context, _choice);
                    },
              child: Text(
                _choice == null || _choice!.method.cost == 0
                    ? t('Potvrdi dostavu')
                    : t('Potvrdi · {0}', [formatCredits(_choice!.method.cost)]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
