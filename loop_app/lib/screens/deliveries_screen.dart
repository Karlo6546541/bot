import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/delivery.dart';
import '../providers/app_providers.dart';
import '../services/delivery_service.dart';
import '../services/file_saver/file_saver.dart';
import '../theme/app_theme.dart';
import '../widgets/community_widgets.dart';
import '../widgets/delivery_picker.dart';
import '../widgets/item_image.dart';
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

/// Kupac bira način dostave za kupljeni/osvojeni predmet (za predmete iz
/// istog livea odabir vrijedi za cijeli paket).
Future<void> pickDelivery(
  BuildContext context,
  WidgetRef ref,
  Delivery delivery,
) async {
  final device = ref.read(appProvider).deviceById(delivery.deviceId);
  final methods = device == null
      ? DeliveryMethod.values.where((m) => m != DeliveryMethod.digital).toList()
      : DeliveryService.methodsFor(device);
  final choice = await showModalBottomSheet<DeliveryChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: LoopColors.background,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => appThemed(
      _ChooseSheet(
        methods: methods,
        savedAddress: ref.read(appProvider).currentUser?.address,
        saved: DeliveryChoice.saved(
          ref.read(appProvider).currentUser?.lastDelivery,
        ),
      ),
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

class DeliveryCard extends ConsumerWidget {
  const DeliveryCard({super.key, required this.delivery});
  final Delivery delivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = delivery;
    final now = DateTime.now();
    final m = d.method;
    final steps = d.steps;
    final current = d.stepIndex(now);
    final delivered = d.isDelivered(now);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('delivery-open-${d.id}'),
        onTap: m == null
            ? null
            : () => DeliveryDetailScreen.open(context, d.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Slika kupljenog predmeta (ako ga još imamo), inače ikona.
                  if (ref.watch(
                        appProvider.select((s) => s.deviceById(d.deviceId)),
                      )
                      case final device?)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ItemThumb(device: device, size: 52),
                    )
                  else
                    Container(
                      width: 52,
                      height: 52,
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
                              ? d.id.startsWith('live-')
                                    ? t('Osvojeno u liveu · odaberi dostavu')
                                    : d.fromAuction
                                    ? t('Osvojeno na aukciji · odaberi dostavu')
                                    : t('Zamjena · odaberi dostavu')
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
                  key: ValueKey('delivery-pick-${d.id}'),
                  onPressed: () => pickDelivery(context, ref, delivery),
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
                if (delivered && d.confirmedAt == null && !d.autoConfirms) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await runWithLoading(
                        context,
                        () =>
                            ref.read(appProvider.notifier).confirmReceipt(d.id),
                        successMessage: t('Hvala! Primitak potvrđen.'),
                      );
                      // Odmah ponudi ocjenu prodavatelja (ako je korisnik).
                      if (ok && d.sellerId != null && context.mounted) {
                        await showReviewDialog(
                          context,
                          ref,
                          deliveryId: d.id,
                          sellerLabel: ref
                              .read(appProvider)
                              .userLabel(d.sellerId),
                        );
                      }
                    },
                    icon: const Icon(Icons.task_alt),
                    label: Text(t('Potvrdi primitak')),
                  ),
                ],
                if (d.canReview) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: ValueKey('review-${d.id}'),
                    onPressed: () => showReviewDialog(
                      context,
                      ref,
                      deliveryId: d.id,
                      sellerLabel: ref.read(appProvider).userLabel(d.sellerId),
                    ),
                    icon: const Icon(Icons.star_outline_rounded),
                    label: Text(
                      t('Ocijeni prodavatelja {0}', [
                        ref.read(appProvider).userLabel(d.sellerId),
                      ]),
                    ),
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

/// Detalji pošiljke: svi koraci s nazivima i datumima.
class DeliveryDetailScreen extends ConsumerWidget {
  const DeliveryDetailScreen({super.key, required this.deliveryId});
  final String deliveryId;

  static Future<void> open(BuildContext context, String id) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DeliveryDetailScreen(deliveryId: id),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final d =
        s.myDeliveries.where((e) => e.id == deliveryId).firstOrNull ??
        s.sellerDeliveries.where((e) => e.id == deliveryId).firstOrNull;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.local_shipping_outlined,
          title: t('Pošiljka nije pronađena'),
        ),
      );
    }
    final now = DateTime.now();
    final steps = d.steps;
    final current = d.stepIndex(now);
    final device = s.deviceById(d.deviceId);
    return Scaffold(
      key: const ValueKey('delivery-detail'),
      appBar: AppBar(title: Text(t('Pošiljka'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              if (device != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ItemThumb(device: device, size: 64),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.deviceName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    if (d.method case final m?)
                      Text(
                        m.label,
                        style: TextStyle(color: LoopColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Prodavač: etiketa s kodom za paketomat (ime i adresa kupca).
          if (d.sellerId == s.currentUserId &&
              d.method != null &&
              d.method != DeliveryMethod.digital) ...[
            const SizedBox(height: 16),
            ShippingLabel(delivery: d),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                children: [
                  for (var i = 0; i < steps.length; i++)
                    _StepRow(
                      key: ValueKey('delivery-step-${steps[i].name}'),
                      label: steps[i].label,
                      at: d.confirmedAt != null && i == steps.length - 1
                          ? d.confirmedAt
                          : d.stepAt(i),
                      done: i <= current,
                      active: i == current,
                      last: i == steps.length - 1,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                if (d.destination != null)
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(t('Dostava na')),
                    subtitle: Text(d.destination!),
                  ),
                if (d.trackingNumber != null)
                  ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(t('Broj pošiljke')),
                    subtitle: Text(d.trackingNumber!),
                    trailing: const Icon(Icons.copy, size: 18),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: d.trackingNumber!));
                      showLoopSnackBar(t('Broj pošiljke kopiran'));
                    },
                  ),
                if (d.sellerId != null)
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(t('Prodavatelj')),
                    subtitle: Text(s.userLabel(d.sellerId)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    super.key,
    required this.label,
    required this.at,
    required this.done,
    required this.active,
    required this.last,
  });
  final String label;
  final DateTime? at;
  final bool done;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          children: [
            _Dot(done: done, active: active),
            if (!last)
              Expanded(
                child: Container(
                  width: 3,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  color: done && !active
                      ? LoopColors.success
                      : LoopColors.surfaceHover,
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                    color: done ? null : LoopColors.textSecondary,
                  ),
                ),
                if (at != null)
                  Text(
                    done
                        ? formatDateTime(at!)
                        : t('očekivano {0}', [formatDateTime(at!)]),
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
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
  const _ChooseSheet({required this.methods, this.savedAddress, this.saved});
  final List<DeliveryMethod> methods;
  final String? savedAddress;

  /// Zapamćeni način dostave iz prošle kupnje.
  final DeliveryChoice? saved;

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
              saved: widget.saved,
              onChanged: (c) => setState(() {
                _choice = c;
                _error = null;
              }),
              onCleared: () => setState(() => _choice = null),
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

/// Etiketa za slanje (prodavač): QR i kod koje paketomat ili kurir
/// skenira — u sebi ima ime i prezime kupca i adresu / paketomat.
class ShippingLabel extends ConsumerWidget {
  const ShippingLabel({super.key, required this.delivery});
  final Delivery delivery;

  /// Sadržaj QR koda (kod pošiljke, primatelj, odredište, način).
  static String payload(Delivery d, String recipient) => [
    'SUBHASTO',
    d.trackingNumber ?? d.id,
    recipient,
    d.destination ?? '',
    d.method?.name ?? '',
  ].join('|');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = delivery;
    final buyer = ref.watch(appProvider.select((s) => s.userById(d.buyerId)));
    final recipient = (buyer?.name.trim().isNotEmpty ?? false)
        ? buyer!.name.trim()
        : (buyer?.handle ?? '');
    final code = d.trackingNumber ?? d.id;
    final locker = d.method == DeliveryMethod.parcelLocker;
    return Card(
      key: const ValueKey('shipping-label'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('📦', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    locker ? t('Kod za paketomat') : t('Etiketa za slanje'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  key: const ValueKey('shipping-qr'),
                  data: payload(d, recipient),
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  showLoopSnackBar(t('Kod kopiran'));
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      code,
                      key: const ValueKey('shipping-code'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy, size: 16),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            Text(
              t('Primatelj'),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
            Text(
              recipient,
              key: const ValueKey('shipping-recipient'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              locker ? t('Paketomat') : t('Adresa'),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
            Text(
              d.destination ?? '—',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('delivery-note'),
              onPressed: () => DeliveryNoteScreen.open(context, d.id),
              icon: const Icon(Icons.description_outlined),
              label: Text(t('Otpremnica')),
            ),
            const SizedBox(height: 12),
            Text(
              locker
                  ? t(
                      'Na bilo kojem BOX NOW paketomatu odaberi "Pošalji paket" i skeniraj QR (ili upiši kod) — paket ide u paketomat kupca.',
                    )
                  : t(
                      'Pokaži QR kuriru ili ispiši etiketu i zalijepi je na paket.',
                    ),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Otpremnica (prodavač): pošiljatelj, primatelj, predmet, način dostave,
/// kod i QR — za ispis ili preuzimanje (HTML koji se ispiše iz preglednika).
class DeliveryNoteScreen extends ConsumerWidget {
  const DeliveryNoteScreen({super.key, required this.deliveryId});
  final String deliveryId;

  static Future<void> open(BuildContext context, String id) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DeliveryNoteScreen(deliveryId: id),
        ),
      );

  static String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final d = s.sellerDeliveries.where((e) => e.id == deliveryId).firstOrNull;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.description_outlined,
          title: t('Pošiljka nije pronađena'),
        ),
      );
    }
    final seller = s.currentUser!;
    final buyer = s.userById(d.buyerId);
    final recipient = (buyer?.name.trim().isNotEmpty ?? false)
        ? buyer!.name.trim()
        : (buyer?.handle ?? '');
    final sender = seller.seller?.tradeName.isNotEmpty ?? false
        ? seller.seller!.tradeName
        : (seller.name.trim().isNotEmpty ? seller.name.trim() : seller.handle);
    final senderAddress = seller.seller?.address ?? seller.address ?? '';
    final code = d.trackingNumber ?? d.id;
    final paid = s.transactions
        .where((x) => x.deviceId == d.deviceId && x.buyerId == d.buyerId)
        .firstOrNull
        ?.price;
    final date = formatDateTime(d.startedAt ?? d.createdAt);
    final rows = <(String, String)>[
      (t('Broj otpremnice'), code),
      (t('Datum'), date),
      (
        t('Pošiljatelj'),
        [sender, senderAddress].where((x) => x.isNotEmpty).join(', '),
      ),
      (t('Primatelj'), recipient),
      (
        d.method == DeliveryMethod.parcelLocker ? t('Paketomat') : t('Adresa'),
        d.destination ?? '—',
      ),
      (t('Način dostave'), d.method?.label ?? '—'),
      (t('Predmet'), '1 × ${d.deviceName}'),
      if (paid != null) (t('Vrijednost'), formatCredits(paid)),
    ];

    Future<void> download() async {
      final png = await QrPainter(
        data: ShippingLabel.payload(d, recipient),
        version: QrVersions.auto,
        gapless: true,
      ).toImageData(400);
      final qr = png == null
          ? ''
          : '<img src="data:image/png;base64,${base64Encode(png.buffer.asUint8List())}" width="180" height="180">';
      final html =
          """<!doctype html><html lang="hr"><head><meta charset="utf-8">
<title>Otpremnica $code</title>
<style>body{font-family:sans-serif;max-width:640px;margin:24px auto;color:#222}
h1{font-size:22px;margin:0 0 4px}table{width:100%;border-collapse:collapse;margin-top:16px}
td{border-bottom:1px solid #ddd;padding:8px 4px;vertical-align:top}td:first-child{color:#666;width:38%}
.code{font-size:26px;font-weight:800;letter-spacing:2px}.qr{text-align:center;margin:16px 0}
@media print{button{display:none}}</style></head><body>
<h1>${_esc(t('Otpremnica'))} — Subhasto</h1>
<div class="qr">$qr<div class="code">${_esc(code)}</div></div>
<table>${rows.map((r) => '<tr><td>${_esc(r.$1)}</td><td>${_esc(r.$2)}</td></tr>').join()}</table>
<p style="color:#666;font-size:13px">${_esc(t('Zalijepi otpremnicu na paket ili je priloži unutra. Kod skenira paketomat ili kurir.'))}</p>
<button onclick="print()">${_esc(t('Ispiši'))}</button></body></html>""";
      final where = await saveBytesFile(
        'otpremnica-$code.html',
        Uint8List.fromList(utf8.encode(html)),
        mime: 'text/html',
      );
      showLoopSnackBar(t('Otpremnica spremljena: {0}', [where]));
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('Otpremnica'))),
      body: ListView(
        key: const ValueKey('delivery-note-screen'),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t('OTPREMNICA'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.white,
                      child: QrImageView(
                        data: ShippingLabel.payload(d, recipient),
                        size: 150,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Divider(height: 24),
                  for (final (k, v) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(
                              k,
                              style: TextStyle(color: LoopColors.textSecondary),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              v,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('delivery-note-download'),
            onPressed: download,
            icon: const Icon(Icons.print_outlined),
            label: Text(t('Preuzmi za ispis')),
          ),
          const SizedBox(height: 8),
          Text(
            t(
              'Zalijepi otpremnicu na paket ili je priloži unutra. Kod skenira paketomat ili kurir.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
