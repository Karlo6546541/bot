import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/delivery.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/label_options.dart';
import 'shipping_profiles_screen.dart';
import '../services/boxnow/boxnow_demo.dart';
import '../services/delivery_service.dart';
import '../services/file_saver/file_saver.dart';
import '../theme/app_theme.dart';
import '../widgets/community_widgets.dart';
import '../widgets/delivery_picker.dart';
import '../widgets/item_image.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';
import '../widgets/loop_snackbar.dart';
import 'messages_screen.dart' show ChatScreen;
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

  /// Filtar kupnji: `null` = sve, `true` = u tijeku, `false` = završeno.
  bool? _open;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(appProvider.select((s) => s.myDeliveries));
    bool done(Delivery d) => d.confirmedAt != null;
    final list = [
      for (final d in all)
        if (_open == null || _open == !done(d)) d,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    Widget chip(String key, String label, bool? value) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('purchases-$key'),
        label: Text(label),
        selected: _open == value,
        showCheckmark: false,
        onSelected: (_) => setState(() => _open = value),
      ),
    );
    final open = all.where((d) => !done(d)).length;
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('all', t('Sve'), null),
          chip('open', '${t('U tijeku')} · $open', true),
          chip('done', t('Završeno'), false),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t('Kupnje'))),
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
                    chips,
                    const SizedBox(height: 10),
                    Text(
                      t(
                        '🚚 Demo: dostava je ubrzana — umjesto dana traje nekoliko minuta, pa statuse možeš pratiti uživo.',
                      ),
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          t('Ovdje nema kupnji.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: LoopColors.textSecondary),
                        ),
                      ),
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
  final st = ref.read(appProvider);
  // Prodavač: iz pošiljke (predmet je već kod kupca nakon pobjede).
  final options = device == null
      ? [
          for (final m in DeliveryMethod.values)
            if (m != DeliveryMethod.digital) DeliveryOption(m),
        ]
      : DeliveryService.optionsFor(
          device,
          from: st.userById(delivery.sellerId)?.country ?? 'HR',
          to: st.currentUser?.country ?? 'HR',
        );
  final choice = await showModalBottomSheet<DeliveryChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: LoopColors.background,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => appThemed(
      _ChooseSheet(
        options: options,
        size: ParcelSize.fromName(device?.parcelSize),
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
        .chooseDelivery(
          delivery.id,
          choice.method,
          choice.destination,
          carrier: choice.carrier,
        ),
    successMessage: t('Dostava je krenula 🚚'),
  );
}

/// Stanje kupnje za kupca (oznaka u popisu kupnji).
String purchaseStatus(Delivery d, DateTime now) {
  if (d.confirmedAt != null) return t('Završeno');
  if (d.method == null) return t('Odaberi dostavu');
  if (d.method == DeliveryMethod.digital) return t('Preuzmi datoteku');
  if (d.isDelivered(now)) return t('Dostavljeno');
  if (d.handedOverAt == null && d.stepIndex(now) <= 1) {
    return t('Otpremnica izrađena');
  }
  return d.status(now).label;
}

/// Koliko dana kupac još može tražiti povrat od trgovca (14 dana od
/// primitka); `null` kad povrat ne vrijedi (privatni prodavatelj).
int? returnDaysLeft(Delivery d, bool business, DateTime now) {
  if (!business) return null;
  final from = d.confirmedAt ?? (d.isDelivered(now) ? d.eta() : null);
  if (from == null) return 14;
  final left = 14 - now.difference(from).inDays;
  return left < 0 ? 0 : left;
}

/// Traka napretka dostave u akcentu (kao Whatnot).
class DeliveryProgressBar extends StatelessWidget {
  const DeliveryProgressBar({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: Stack(
      children: [
        Container(height: 6, color: LoopColors.surfaceHover),
        FractionallySizedBox(
          widthFactor: value.clamp(0.04, 1.0),
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  LoopColors.accent.withValues(alpha: 0.7),
                  LoopColors.accent,
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: LoopColors.surfaceHover,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11),
    ),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value, {this.accent = false});
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label: ',
          style: TextStyle(color: LoopColors.textSecondary),
        ),
        TextSpan(
          text: value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: accent ? LoopColors.accent : null,
          ),
        ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 13),
  );
}

/// Pomoć s kupnjom: prava kupca i prijava problema.
Future<void> showPurchaseHelp(BuildContext context, WidgetRef ref, Delivery d) {
  final s = ref.read(appProvider);
  final seller = s.userById(d.sellerId);
  final business = seller?.seller?.isBusiness ?? false;
  final left = returnDaysLeft(d, business, DateTime.now());
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          key: const ValueKey('purchase-help'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('Pomoć s ovom kupnjom'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              d.confirmedAt == null
                  ? t(
                      'Ako paket ne stigne ili je predmet bitno drukčiji od opisa, prijavi problem prije potvrde primitka.',
                    )
                  : t(
                      'Primitak je potvrđen. Za problem se najprije javi prodavatelju porukom.',
                    ),
            ),
            if (left != null) ...[
              const SizedBox(height: 8),
              Text(
                left > 0
                    ? t(
                        'Prodavatelj je trgovac: imaš pravo na povrat još {0} dana.',
                        ['$left'],
                      )
                    : t('Rok od 14 dana za povrat od trgovca je istekao.'),
                key: const ValueKey('purchase-return-days'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: 14),
            if (d.sellerId != null)
              OutlinedButton.icon(
                key: const ValueKey('purchase-help-message'),
                onPressed: () {
                  Navigator.pop(ctx);
                  ChatScreen.open(context, d.sellerId!, deviceId: d.deviceId);
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(t('Piši prodavatelju')),
              ),
            const SizedBox(height: 8),
            if (d.sellerId != null)
              FilledButton.icon(
                key: const ValueKey('purchase-help-report'),
                onPressed: () {
                  Navigator.pop(ctx);
                  showReportSheet(
                    context,
                    ref,
                    targetType: 'user',
                    targetId: d.sellerId!,
                    targetLabel: s.userLabel(d.sellerId),
                  );
                },
                icon: const Icon(Icons.report_outlined),
                label: Text(t('Prijavi problem')),
              ),
          ],
        ),
      ),
    ),
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
                        _StatusPill(
                          key: ValueKey('purchase-status-${d.id}'),
                          label: purchaseStatus(d, now),
                          color: d.confirmedAt != null
                              ? LoopColors.success
                              : m == null
                              ? LoopColors.accent
                              : LoopColors.textSecondary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.deviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (ref
                                .read(appProvider)
                                .itemPaid(d.deviceId, d.buyerId)
                            case final paid?)
                          _InfoLine(t('Cijena'), formatCredits(paid)),
                        _InfoLine(t('Kupljeno'), formatDate(d.createdAt)),
                        if (!delivered && d.eta() != null)
                          _InfoLine(
                            t('Dostava očekivana'),
                            formatDate(d.eta()!),
                          ),
                        if (d.sellerId != null)
                          _InfoLine(
                            t('Od'),
                            '@${ref.read(appProvider).userLabel(d.sellerId)}',
                            accent: true,
                          ),
                        Text(
                          m == null
                              ? d.id.startsWith('live-')
                                    ? t('Osvojeno u liveu · odaberi dostavu')
                                    : d.fromAuction
                                    ? t('Osvojeno na aukciji · odaberi dostavu')
                                    : t('Zamjena · odaberi dostavu')
                              : '${d.carrier ?? m.label}${d.destination != null ? ' · ${d.destination}' : ''}',
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
                // Traka napretka dostave (kao Whatnot).
                DeliveryProgressBar(
                  value: steps.length <= 1 ? 1 : current / (steps.length - 1),
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
                        d.autoConfirms
                            ? t('Preuzeto iz paketomata ✅')
                            : t('Primitak potvrđen ✅'),
                        style: TextStyle(color: LoopColors.success),
                      ),
                  ],
                ),
                // Paket je u paketomatu: PIN za preuzimanje odmah na kartici.
                if (d.autoConfirms &&
                    d.confirmedAt == null &&
                    d.status(now) == DeliveryStatus.inLocker &&
                    d.buyerId == ref.read(appProvider).currentUserId) ...[
                  const SizedBox(height: 12),
                  PickupPinBox(delivery: d),
                ],
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
    final buyer = d.buyerId == s.currentUserId;
    final eta = d.eta();
    final delivered = d.isDelivered(now);
    Widget action(
      String key,
      IconData icon,
      String title,
      String? subtitle,
      VoidCallback onTap, {
      bool highlight = false,
    }) => ListTile(
      key: ValueKey(key),
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: highlight ? LoopColors.accent : LoopColors.surfaceHover,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: highlight ? LoopColors.onAccent : null,
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
    final business = s.userById(d.sellerId)?.seller?.isBusiness ?? false;
    final left = returnDaysLeft(d, business, now);
    return Scaffold(
      key: const ValueKey('delivery-detail'),
      appBar: AppBar(title: Text(d.deviceName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (buyer && d.method != null) ...[
            Container(
              key: const ValueKey('order-status'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: LoopColors.surface,
                borderRadius: BorderRadius.circular(kRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    purchaseStatus(d, now),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  if (eta != null && !delivered)
                    Text(
                      t('Očekivano do {0}', [formatDate(eta)]),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  const SizedBox(height: 12),
                  DeliveryProgressBar(
                    value: steps.length <= 1 ? 1 : current / (steps.length - 1),
                  ),
                  const SizedBox(height: 10),
                  if (d.destination != null && eta != null)
                    Text(
                      delivered
                          ? t('Pošiljka je dostavljena na {0}.', [
                              d.destination!,
                            ])
                          : t('Pošiljka bi trebala stići na {0} do {1}.', [
                              d.destination!,
                              formatDate(eta),
                            ]),
                      style: TextStyle(color: LoopColors.textSecondary),
                    ),
                  const SizedBox(height: 8),
                  if (d.sellerId != null)
                    action(
                      'order-message',
                      Icons.chat_bubble_outline,
                      t('Poruka prodavatelju'),
                      null,
                      () => ChatScreen.open(
                        context,
                        d.sellerId!,
                        deviceId: d.deviceId,
                      ),
                    ),
                  action(
                    'order-help',
                    Icons.help_outline,
                    t('Pomoć s ovom kupnjom'),
                    left != null && left > 0
                        ? t('Pravo na povrat još {0} dana.', ['$left'])
                        : d.confirmedAt == null
                        ? t('Problem prijavi prije potvrde primitka.')
                        : null,
                    () => showPurchaseHelp(context, ref, d),
                  ),
                  if (d.trackingNumber != null)
                    action(
                      'order-track',
                      Icons.local_shipping_outlined,
                      t('Prati pošiljku'),
                      d.trackingNumber,
                      () {
                        Clipboard.setData(
                          ClipboardData(text: d.trackingNumber!),
                        );
                        showLoopSnackBar(
                          t('Broj pošiljke kopiran: {0}', [d.trackingNumber!]),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
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
                    if (d.method != null)
                      Text(
                        d.serviceLabel,
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
          // Paketomat (BOX NOW, GLS, DPD — demo): broj, PIN-ovi i praćenje.
          if (d.method == DeliveryMethod.parcelLocker) ...[
            const SizedBox(height: 16),
            BoxNowCard(delivery: d, seller: d.sellerId == s.currentUserId),
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
  const _ChooseSheet({
    required this.options,
    this.savedAddress,
    this.saved,
    this.size = ParcelSize.small,
  });
  final List<DeliveryOption> options;
  final ParcelSize size;
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
              options: widget.options,
              size: widget.size,
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
                        carrier: _choice!.carrier,
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
                  ? BoxNowDemo.network(d).dropOffHint
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
    final recipient = deliveryRecipient(s, d);
    final code = d.trackingNumber ?? d.id;
    final rows = deliveryNoteRows(s, d);

    Future<void> download() => downloadDeliveryNotes(ref, [d]);

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

/// Ime primatelja na otpremnici.
String deliveryRecipient(AppState s, Delivery d) {
  final buyer = s.userById(d.buyerId);
  return (buyer?.name.trim().isNotEmpty ?? false)
      ? buyer!.name.trim()
      : (buyer?.handle ?? '');
}

/// Retci otpremnice za pošiljku [d] (pošiljatelj je trenutni korisnik).
List<(String, String)> deliveryNoteRows(AppState s, Delivery d) {
  final seller = s.currentUser!;
  final recipient = deliveryRecipient(s, d);
  final sender = seller.seller?.tradeName.isNotEmpty ?? false
      ? seller.seller!.tradeName
      : (seller.name.trim().isNotEmpty ? seller.name.trim() : seller.handle);
  final senderAddress = seller.seller?.address ?? seller.address ?? '';
  final code = d.trackingNumber ?? d.id;
  final paid = s.itemPaid(d.deviceId, d.buyerId);
  final date = formatDateTime(d.startedAt ?? d.createdAt);
  return <(String, String)>[
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
    (t('Način dostave'), d.method == null ? '—' : d.serviceLabel),
    (t('Predmet'), '1 × ${d.deviceName}'),
    if (s.deviceById(d.deviceId)?.shipping case final sp?) ...[
      (t('Težina'), sp.weightLabel),
      if (sp.hasDimensions) (t('Dimenzije'), sp.dimensionsLabel),
    ],
    if (paid != null) (t('Vrijednost'), formatCredits(paid)),
    if (d.method == DeliveryMethod.parcelLocker) ...[
      (
        t('{0} broj pošiljke', [BoxNowDemo.network(d).brand]),
        BoxNowDemo.parcelId(d),
      ),
      (t('PIN za predaju'), BoxNowDemo.dropOffPin(d)),
    ],
  ];
}

String _esc(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Sprema otpremnice za [list] u jedan HTML za ispis (svaka na svojoj
/// stranici), u veličini iz zadanih postavki otpremnice.
Future<void> downloadDeliveryNotes(WidgetRef ref, List<Delivery> list) async {
  if (list.isEmpty) return;
  final s = ref.read(appProvider);
  final options = LabelOptions.of(ref.read(storageProvider), s.currentUserId);
  final pages = StringBuffer();
  for (final d in list) {
    final code = d.trackingNumber ?? d.id;
    final rows = deliveryNoteRows(s, d);
    final png = await QrPainter(
      data: ShippingLabel.payload(d, deliveryRecipient(s, d)),
      version: QrVersions.auto,
      gapless: true,
    ).toImageData(400);
    final qr = png == null
        ? ''
        : '<img src="data:image/png;base64,${base64Encode(png.buffer.asUint8List())}" width="180" height="180">';
    pages.write('''<section class="note">
<h1>${_esc(t('Otpremnica'))} — Subhasto</h1>
<div class="qr">$qr<div class="code">${_esc(code)}</div></div>
<table>${rows.map((r) => '<tr><td>${_esc(r.$1)}</td><td>${_esc(r.$2)}</td></tr>').join()}</table>
${options.packingList ? '<p class="slip"><b>${_esc(t('Sadržaj paketa'))}:</b> 1 × ${_esc(d.deviceName)}</p>' : ''}
<p style="color:#666;font-size:13px">${_esc(t('Zalijepi otpremnicu na paket ili je priloži unutra. Kod skenira paketomat ili kurir.'))}</p>
</section>''');
  }
  final page = options.size == LabelSize.a4 ? 'A4' : '105mm 148mm';
  final title = list.length == 1
      ? 'Otpremnica ${list.first.trackingNumber ?? list.first.id}'
      : 'Otpremnice (${list.length})';
  final html =
      """<!doctype html><html lang="hr"><head><meta charset="utf-8">
<title>$title</title>
<style>@page{size:$page;margin:8mm}body{font-family:sans-serif;max-width:640px;margin:24px auto;color:#222}
h1{font-size:22px;margin:0 0 4px}table{width:100%;border-collapse:collapse;margin-top:16px}
td{border-bottom:1px solid #ddd;padding:8px 4px;vertical-align:top}td:first-child{color:#666;width:38%}
.code{font-size:26px;font-weight:800;letter-spacing:2px}.qr{text-align:center;margin:16px 0}
.note{page-break-after:always}.note:last-of-type{page-break-after:auto}
@media print{button{display:none}}</style></head><body>
$pages
<button onclick="print()">${_esc(t('Ispiši'))}</button></body></html>""";
  final name = list.length == 1
      ? 'otpremnica-${list.first.trackingNumber ?? list.first.id}.html'
      : 'otpremnice-${list.length}.html';
  final where = await saveBytesFile(
    name,
    Uint8List.fromList(utf8.encode(html)),
    mime: 'text/html',
  );
  showLoopSnackBar(
    list.length == 1
        ? t('Otpremnica spremljena: {0}', [where])
        : t('Otpremnice spremljene: {0}', [where]),
  );
}

/// Paketomat (demo): broj pošiljke, PIN za predaju (prodavač) ili PIN za
/// preuzimanje (kupac, kad paket stigne) i praćenje kao kod dostavljača
/// (BOX NOW, GLS, DPD).
class BoxNowCard extends StatelessWidget {
  const BoxNowCard({super.key, required this.delivery, required this.seller});
  final Delivery delivery;
  final bool seller;

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final network = BoxNowDemo.network(d);
    final green = Color(network.color);
    final now = DateTime.now();
    final idx = d.stepIndex(now);
    final inLocker =
        d.steps.indexOf(DeliveryStatus.inLocker) <= idx &&
        d.confirmedAt == null;
    Widget pin(String label, String value, Key key) => Container(
      key: key,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: green),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
    return Card(
      key: const ValueKey('boxnow-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: green,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    network.brand,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t('Pošiljka {0}', [BoxNowDemo.parcelId(d)]),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  t('demo'),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            if (d.destination != null) ...[
              const SizedBox(height: 6),
              Text(
                d.destination!,
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
              ),
            ],
            if (seller && idx <= 1)
              pin(
                t('PIN za predaju na paketomatu'),
                BoxNowDemo.dropOffPin(d),
                const ValueKey('boxnow-dropoff-pin'),
              ),
            if (!seller && inLocker)
              pin(
                t('PIN za preuzimanje'),
                BoxNowDemo.pickupPin(d),
                const ValueKey('boxnow-pickup-pin'),
              ),
            const SizedBox(height: 12),
            for (final (label, at, done) in BoxNowDemo.events(d, now))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      done ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 18,
                      color: done ? green : LoopColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                          color: done ? null : LoopColors.textSecondary,
                        ),
                      ),
                    ),
                    if (at != null && done)
                      Text(
                        formatDateTime(at),
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 11,
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

/// Grupa pošiljke u Otpremi prodavača (čipovi filtra).
enum ShipGroup {
  /// Kupac još bira način dostave.
  awaitingBuyer,

  /// Spremno za predaju dostavljaču (otpremnica, rok 48 h).
  readyToShip,

  /// Predano dostavljaču, putuje.
  shipped,

  /// Dostavljeno ili preuzeto.
  delivered;

  static ShipGroup of(Delivery d, DateTime now) {
    if (d.confirmedAt != null || d.isDelivered(now)) return delivered;
    if (d.method == null) return awaitingBuyer;
    if (d.handedOverAt == null) return readyToShip;
    return shipped;
  }

  String get label => switch (this) {
    awaitingBuyer => t('Čeka kupca'),
    readyToShip => t('Za predaju'),
    shipped => t('Poslano'),
    delivered => t('Dostavljeno'),
  };
}

/// Otprema (prodavač), kao Whatnot Fulfillment: čipovi po stanju, popis
/// pošiljaka s odabirom, skupne radnje (otpremnice, označi kao predano) i
/// zadane postavke otpremnice.
class DeliveryNotesScreen extends ConsumerStatefulWidget {
  const DeliveryNotesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const DeliveryNotesScreen()));

  @override
  ConsumerState<DeliveryNotesScreen> createState() =>
      _DeliveryNotesScreenState();
}

class _DeliveryNotesScreenState extends ConsumerState<DeliveryNotesScreen> {
  /// `null` = sve pošiljke.
  ShipGroup? _group;
  final Set<String> _selected = {};

  Future<void> _markHandedOver(List<Delivery> list) async {
    final n = list.length;
    await runWithLoading(context, () async {
      for (final d in list) {
        await ref.read(appProvider.notifier).markHandedOver(d.id);
      }
    }, successMessage: t('Označeno kao predano: {0}', ['$n']));
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final now = DateTime.now();
    final all =
        [
          for (final d in s.sellerDeliveries)
            if (d.method != DeliveryMethod.digital) d,
        ]..sort(
          (a, b) => (b.startedAt ?? b.createdAt).compareTo(
            a.startedAt ?? a.createdAt,
          ),
        );
    final counts = {for (final g in ShipGroup.values) g: 0};
    for (final d in all) {
      counts[ShipGroup.of(d, now)] = counts[ShipGroup.of(d, now)]! + 1;
    }
    final shown = _group == null
        ? all
        : all.where((d) => ShipGroup.of(d, now) == _group).toList();
    final ready = [
      for (final d in all)
        if (ShipGroup.of(d, now) == ShipGroup.readyToShip) d,
    ];
    _selected.removeWhere((id) => !ready.any((d) => d.id == id));
    final selected = [
      for (final d in ready)
        if (_selected.contains(d.id)) d,
    ];
    final muted = TextStyle(color: LoopColors.textSecondary, fontSize: 13);

    Widget chip(String key, String label, bool on, VoidCallback tap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey(key),
        label: Text(label),
        selected: on,
        showCheckmark: false,
        onSelected: (_) => setState(tap),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(t('Otprema'))),
      bottomNavigationBar: selected.isEmpty
          ? null
          : SafeArea(
              child: Container(
                key: const ValueKey('ship-bulk'),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: LoopColors.surface,
                  border: Border(
                    top: BorderSide(color: LoopColors.surfaceHover),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t('Skupne radnje · odabrano {0}', ['${selected.length}']),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const ValueKey('ship-bulk-notes'),
                      onPressed: () => downloadDeliveryNotes(ref, selected),
                      icon: const Icon(Icons.print_outlined),
                      label: Text(
                        t('Preuzmi otpremnice ({0})', ['${selected.length}']),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('ship-bulk-handed'),
                      onPressed: () => _markHandedOver(selected),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: Text(t('Označi sve kao predano')),
                    ),
                  ],
                ),
              ),
            ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            key: const ValueKey('my-notes-list'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    chip(
                      'notes-filter-all',
                      t('Sve'),
                      _group == null,
                      () => _group = null,
                    ),
                    for (final g in [
                      ShipGroup.readyToShip,
                      ShipGroup.awaitingBuyer,
                      ShipGroup.shipped,
                      ShipGroup.delivered,
                    ])
                      chip(
                        'notes-filter-${g.name}',
                        counts[g]! > 0 ? '${g.label} · ${counts[g]}' : g.label,
                        _group == g,
                        () => _group = g,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _group?.label ?? t('Sve pošiljke'),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          t('{0} pošiljaka za predaju', ['${ready.length}']),
                          key: const ValueKey('ship-ready-count'),
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  if (ready.isNotEmpty &&
                      (_group == null || _group == ShipGroup.readyToShip))
                    TextButton(
                      key: const ValueKey('ship-select-all'),
                      onPressed: () => setState(() {
                        if (selected.length == ready.length) {
                          _selected.clear();
                        } else {
                          _selected.addAll(ready.map((d) => d.id));
                        }
                      }),
                      child: Text(
                        selected.length == ready.length
                            ? t('Poništi odabir')
                            : t('Odaberi sve'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 44,
                        color: LoopColors.textSecondary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        all.isEmpty
                            ? t('Još nema otpremnica')
                            : t('Sve je riješeno'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        t('Ovdje se pojavljuju paketi tvojih prodaja.'),
                        style: muted,
                      ),
                    ],
                  ),
                )
              else
                for (final d in shown)
                  _ShipmentRow(
                    d: d,
                    group: ShipGroup.of(d, now),
                    device: s.deviceById(d.deviceId),
                    buyer: s.userById(d.buyerId)?.handle ?? '',
                    now: now,
                    selected: _selected.contains(d.id),
                    onSelect: ShipGroup.of(d, now) == ShipGroup.readyToShip
                        ? (v) => setState(
                            () => v
                                ? _selected.add(d.id)
                                : _selected.remove(d.id),
                          )
                        : null,
                  ),
              const SizedBox(height: 18),
              const _LabelOptionsCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShipmentRow extends StatelessWidget {
  const _ShipmentRow({
    required this.d,
    required this.group,
    required this.buyer,
    required this.now,
    required this.selected,
    this.device,
    this.onSelect,
  });

  final Delivery d;
  final Device? device;
  final ShipGroup group;
  final String buyer;
  final DateTime now;
  final bool selected;
  final ValueChanged<bool>? onSelect;

  @override
  Widget build(BuildContext context) {
    final due = d.handOverDue;
    final late =
        group == ShipGroup.readyToShip && due != null && now.isAfter(due);
    final (color, label) = switch (group) {
      ShipGroup.readyToShip when late => (LoopColors.error, t('Kasni')),
      ShipGroup.readyToShip => (LoopColors.accent, group.label),
      ShipGroup.awaitingBuyer => (LoopColors.textSecondary, group.label),
      ShipGroup.shipped => (LoopColors.info, group.label),
      ShipGroup.delivered => (LoopColors.success, group.label),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        child: InkWell(
          key: ValueKey('note-${d.id}'),
          borderRadius: BorderRadius.circular(kRadius),
          onTap: () => DeliveryNoteScreen.open(context, d.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
            child: Row(
              children: [
                if (onSelect != null)
                  Checkbox(
                    key: ValueKey('ship-select-${d.id}'),
                    value: selected,
                    onChanged: (v) => onSelect!(v ?? false),
                  )
                else
                  const SizedBox(width: 12),
                if (device != null)
                  ItemThumb(device: device!, size: 52)
                else
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: LoopColors.surfaceHover,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.inventory_2_outlined),
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
                        [
                          if (buyer.isNotEmpty) '@$buyer',
                          if (d.method != null) d.serviceLabel,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (group == ShipGroup.readyToShip && due != null)
                        Text(
                          t('Predaj do {0}', [formatDateTime(due)]),
                          style: TextStyle(
                            color: late
                                ? LoopColors.error
                                : LoopColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Zadane postavke otpremnice": vrijede za sve buduće otpremnice.
class _LabelOptionsCard extends ConsumerStatefulWidget {
  const _LabelOptionsCard();

  @override
  ConsumerState<_LabelOptionsCard> createState() => _LabelOptionsCardState();
}

class _LabelOptionsCardState extends ConsumerState<_LabelOptionsCard> {
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final storage = ref.read(storageProvider);
    final options = LabelOptions.of(storage, s.currentUserId);
    final user = s.currentUser;
    final returnAddress = user?.address ?? user?.seller?.address ?? '';

    Future<void> save(LabelOptions o) async {
      await o.save(storage, s.currentUserId);
      if (mounted) setState(() {});
    }

    Widget row(String key, String title, String value, VoidCallback onTap) =>
        InkWell(
          key: ValueKey(key),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        value,
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: LoopColors.textSecondary,
                ),
              ],
            ),
          ),
        );

    String sizeLabel(LabelSize v) => switch (v) {
      LabelSize.a6 => t('A6 (10 × 15 cm), naljepnica'),
      LabelSize.a4 => t('A4, običan papir'),
    };

    return Material(
      key: const ValueKey('label-options'),
      color: LoopColors.surface,
      borderRadius: BorderRadius.circular(kRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Zadane postavke otpremnice'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              t('Vrijede za sve otpremnice koje još nisu ispisane.'),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            row(
              'label-size',
              t('Veličina otpremnice'),
              sizeLabel(options.size),
              () async {
                final v = await showModalBottomSheet<LabelSize>(
                  context: context,
                  showDragHandle: true,
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final size in LabelSize.values)
                          ListTile(
                            key: ValueKey('label-size-${size.name}'),
                            title: Text(sizeLabel(size)),
                            trailing: size == options.size
                                ? Icon(Icons.check, color: LoopColors.accent)
                                : null,
                            onTap: () => Navigator.pop(ctx, size),
                          ),
                      ],
                    ),
                  ),
                );
                if (v != null) await save(options.copyWith(size: v));
              },
            ),
            Divider(height: 1, color: LoopColors.surfaceHover),
            SwitchListTile(
              key: const ValueKey('label-packing'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                t('Popis sadržaja paketa'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                t('Ispisuje se na otpremnici.'),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
              ),
              value: options.packingList,
              onChanged: (v) => save(options.copyWith(packingList: v)),
            ),
            Divider(height: 1, color: LoopColors.surfaceHover),
            row(
              'label-profiles',
              t('Profili dostave'),
              (user?.shippingProfiles.isEmpty ?? true)
                  ? t('Težina, dimenzije i predmeti po paketu')
                  : user!.shippingProfiles.map((p) => p.name).join(', '),
              () => ShippingProfilesScreen.open(context),
            ),
            Divider(height: 1, color: LoopColors.surfaceHover),
            row(
              'label-return',
              t('Adresa za povrat'),
              returnAddress.isEmpty ? t('Dodaj adresu') : returnAddress,
              () => ensureCheckout(context, ref, force: true),
            ),
          ],
        ),
      ),
    );
  }
}

/// PIN za preuzimanje iz paketomata (kupac) — veliko i jasno.
class PickupPinBox extends ConsumerWidget {
  const PickupPinBox({super.key, required this.delivery});
  final Delivery delivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = delivery;
    final pin = BoxNowDemo.pickupPin(d);
    final green = Color(BoxNowDemo.network(d).color);
    return Container(
      key: ValueKey('pickup-pin-${d.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: green, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('📬', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('Paket te čeka u paketomatu'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (d.destination != null)
                      Text(
                        d.destination!,
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
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: pin));
                  showLoopSnackBar(t('PIN kopiran'));
                },
                child: Column(
                  children: [
                    Text(
                      t('PIN'),
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      pin,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: ValueKey('pickup-open-${d.id}'),
            style: FilledButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => showPickupDialog(context, ref, d),
            icon: const Icon(Icons.lock_open),
            label: Text(t('Preuzmi paket — upiši PIN')),
          ),
        ],
      ),
    );
  }
}

/// "Zaslon paketomata": kupac upisuje PIN i otvara pretinac.
Future<void> showPickupDialog(
  BuildContext context,
  WidgetRef ref,
  Delivery d,
) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('{0} paketomat', [BoxNowDemo.network(d).brand])),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('Odaberi "Preuzmi paket" i upiši PIN iz poruke.')),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('pickup-pin-field'),
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(hintText: '••••••', counterText: ''),
            onSubmitted: (_) => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(t('Odustani')),
        ),
        FilledButton(
          key: const ValueKey('pickup-pin-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(t('Otvori pretinac')),
        ),
      ],
    ),
  );
  final pin = c.text;
  c.dispose();
  if (ok != true || !context.mounted) return;
  await runWithLoading(
    context,
    () => ref.read(appProvider.notifier).pickUpParcel(d.id, pin),
    successMessage: t('Pretinac je otvoren — paket je preuzet ✅'),
  );
}

/// PIN-ovi za preuzimanje (zasebna kategorija u Moje): svi paketi koji
/// kupca čekaju u paketomatima.
class PickupPinsScreen extends ConsumerWidget {
  const PickupPinsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PickupPinsScreen()));

  /// Paketi koji čekaju u paketomatu (kupac).
  static List<Delivery> waiting(List<Delivery> mine, DateTime now) => [
    for (final d in mine)
      if (d.autoConfirms &&
          d.confirmedAt == null &&
          d.status(now) == DeliveryStatus.inLocker)
        d,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final list = waiting(s.myDeliveries, DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text(t('PIN-ovi za preuzimanje'))),
      body: list.isEmpty
          ? EmptyState(
              icon: Icons.markunread_mailbox_outlined,
              title: t('Nema paketa u paketomatu'),
              message: t(
                'Kad paket stigne u tvoj paketomat (BOX NOW, GLS ili DPD), ovdje dobiješ PIN za otvaranje pretinca.',
              ),
            )
          : ListView(
              key: const ValueKey('pickup-pins-list'),
              padding: const EdgeInsets.all(16),
              children: [
                for (final d in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.deviceName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        PickupPinBox(delivery: d),
                      ],
                    ),
                  ),
                Text(
                  t(
                    'Na paketomatu odaberi "Preuzmi paket" i upiši PIN — pretinac se otvori. Preuzimanje se u aplikaciji potvrdi samo.',
                  ),
                  style: TextStyle(color: LoopColors.textSecondary),
                ),
              ],
            ),
    );
  }
}
