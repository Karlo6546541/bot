import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../models/price_offer.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'trade_actions.dart';

// ------------------------------------------------------------ dijeljenje

/// Javna adresa aplikacije (kad se ne pokreće na webu).
const kPublicUrl = 'https://karlo6546541.github.io/bot/';

/// Poveznica na oglas (`?item=<id>`) ili trgovinu (`?shop=<korisnik>`).
String publicLink({String? item, String? shop}) {
  final base = kIsWeb ? Uri.base : Uri.parse(kPublicUrl);
  final root = '${base.scheme}://${base.authority}${base.path}';
  final query = item != null
      ? 'item=${Uri.encodeQueryComponent(item)}'
      : 'shop=${Uri.encodeQueryComponent(shop ?? '')}';
  return '$root?$query';
}

/// Kopira poveznicu u međuspremnik (za slanje porukom, objavu…).
Future<void> shareLink(String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  showLoopSnackBar(t('Poveznica je kopirana — zalijepi je gdje želiš.'));
}

class ShareButton extends StatelessWidget {
  const ShareButton({super.key, required this.url, this.tooltip});
  final String url;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('share'),
    tooltip: tooltip ?? t('Podijeli'),
    icon: const Icon(Icons.ios_share),
    onPressed: () => shareLink(url),
  );
}

// ----------------------------------------------------------- oznake cijene

/// Mala oznaka "−20%".
class DiscountBadge extends StatelessWidget {
  const DiscountBadge({super.key, required this.percent, this.small = false});
  final int percent;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: 2),
    decoration: BoxDecoration(
      color: LoopColors.error,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      '−$percent%',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: small ? 11 : 13,
      ),
    ),
  );
}

/// Oznaka plaćenog isticanja.
class PromotedBadge extends StatelessWidget {
  const PromotedBadge({super.key, this.small = false});
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: 2),
    decoration: BoxDecoration(
      color: LoopColors.sunny,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      t('⭐ Istaknuto'),
      style: TextStyle(
        color: Colors.black87,
        fontWeight: FontWeight.w800,
        fontSize: small ? 11 : 13,
      ),
    ),
  );
}

/// Cijena s prekriženom redovnom cijenom kad je niža (popust ili
/// dogovorena cijena).
class PriceTag extends StatelessWidget {
  const PriceTag({
    super.key,
    required this.device,
    required this.price,
    this.fontSize = 16,
    this.center = false,
  });

  final Device device;
  final double price;
  final double fontSize;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final cut = price < device.basePrice;
    return Wrap(
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Text(
          formatCredits(price),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: cut ? LoopColors.error : null,
          ),
        ),
        if (cut)
          Text(
            formatCredits(device.basePrice),
            style: TextStyle(
              fontSize: fontSize * 0.62,
              color: LoopColors.textSecondary,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        if (device.hasDiscount)
          DiscountBadge(percent: device.discountPercent, small: fontSize < 20),
      ],
    );
  }
}

// --------------------------------------------------------------- praćenje

class FollowButton extends ConsumerWidget {
  const FollowButton({super.key, required this.userId, this.compact = false});
  final String userId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(
      appProvider.select((s) => s.isFollowing(userId)),
    );
    final me = ref.watch(appProvider.select((s) => s.currentUserId));
    if (me == null || me == userId) return const SizedBox.shrink();
    Future<void> toggle() async {
      if (blockGuest(context)) return;
      try {
        final now = await ref.read(appProvider.notifier).toggleFollow(userId);
        showLoopSnackBar(
          now
              ? t('Pratiš — javit ćemo ti nove oglase i popuste.')
              : t('Više ne pratiš ovaj račun.'),
        );
      } on TradeException catch (e) {
        showLoopSnackBar(e.message, error: true);
      }
    }

    final label = Text(following ? t('Pratiš') : t('Prati'));
    final icon = Icon(
      following ? Icons.check : Icons.person_add_alt_1,
      size: 18,
    );
    final style = compact
        ? const ButtonStyle(visualDensity: VisualDensity.compact)
        : null;
    return following
        ? OutlinedButton.icon(
            key: const ValueKey('follow'),
            style: style,
            onPressed: toggle,
            icon: icon,
            label: label,
          )
        : FilledButton.icon(
            key: const ValueKey('follow'),
            style: style,
            onPressed: toggle,
            icon: icon,
            label: label,
          );
  }
}

// --------------------------------------------------------------- popusti

/// Vlasnik postavlja popust na oglas: postotak i trajanje.
Future<void> showDiscountSheet(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  final result = await showModalBottomSheet<(int, Duration?)>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: LoopColors.background,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => _DiscountSheet(device: device),
  );
  if (result == null || !context.mounted) return;
  final (percent, duration) = result;
  await runWithLoading(
    context,
    () => ref
        .read(appProvider.notifier)
        .setDiscount(device.id, percent, duration: duration),
    successMessage: percent == 0
        ? t('Popust je uklonjen')
        : t('Popust −{0}% je aktivan — pratitelji su obaviješteni', [
            '$percent',
          ]),
  );
}

String durationLabel(Duration? d) => switch (d?.inDays) {
  null => t('Trajno'),
  1 => t('1 dan'),
  final n => t('{0} dana', ['$n']),
};

class _DiscountSheet extends StatefulWidget {
  const _DiscountSheet({required this.device});
  final Device device;

  @override
  State<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<_DiscountSheet> {
  late int _percent = widget.device.hasDiscount
      ? widget.device.discountPercent
      : 10;
  Duration? _duration = const Duration(days: 3);

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final newPrice = (d.basePrice * (100 - _percent)).roundToDouble() / 100;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('Popust na "{0}"', [d.name]),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'Pratitelji i oni kojima je predmet na listi želja dobit će obavijest.',
              ),
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '−$_percent%',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  formatCredits(d.basePrice),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatCredits(newPrice),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: LoopColors.error,
                  ),
                ),
              ],
            ),
            Slider(
              key: const ValueKey('discount-slider'),
              value: _percent.toDouble(),
              min: 5,
              max: Device.maxDiscount.toDouble(),
              divisions: (Device.maxDiscount - 5) ~/ 5,
              label: '−$_percent%',
              onChanged: (v) => setState(() => _percent = v.round()),
            ),
            const SizedBox(height: 8),
            Text(
              t('Trajanje'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final dur in TradeService.discountDurations)
                  ChoiceChip(
                    label: Text(durationLabel(dur)),
                    selected: _duration == dur,
                    onSelected: (_) => setState(() => _duration = dur),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('apply-discount'),
              onPressed: () => Navigator.pop(context, (_percent, _duration)),
              icon: const Icon(Icons.local_offer_outlined),
              label: Text(t('Postavi popust')),
            ),
            if (d.hasDiscount) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context, (0, null)),
                child: Text(t('Ukloni popust')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opis aktivnog popusta: "−20% do 24.10.2026." ili "−20% trajno".
String discountLabel(Device d) => d.discountUntil == null
    ? t('−{0}% trajno', ['${d.discountPercent}'])
    : t('−{0}% do {1}', [
        '${d.discountPercent}',
        formatDateTime(d.discountUntil!),
      ]);

// --------------------------------------------------------------- cjenkanje

/// Unos iznosa (ponuda ili protuponuda).
Future<double?> _amountDialog(
  BuildContext context, {
  required String title,
  required String message,
  required double suggestion,
  required double max,
}) => showDialog<double>(
  context: context,
  builder: (_) => _AmountDialog(
    title: title,
    message: message,
    suggestion: suggestion,
    max: max,
  ),
);

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.message,
    required this.suggestion,
    required this.max,
  });
  final String title;
  final String message;
  final double suggestion;
  final double max;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _c = TextEditingController(
    text: formatNumber(widget.suggestion).replaceAll('.', ''),
  );
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double? get _value =>
      double.tryParse(_c.text.trim().replaceAll('.', '').replaceAll(',', '.'));

  void _submit() {
    final v = _value;
    if (v == null || v <= 0) {
      setState(() => _error = t('Unesi ispravan iznos'));
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.message,
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final p in const [5, 10, 15, 20])
                  ActionChip(
                    label: Text('−$p%'),
                    onPressed: () => setState(() {
                      _c.text = formatNumber(
                        roundCredits(widget.max * (100 - p) / 100),
                      ).replaceAll('.', '');
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('amount-field'),
              controller: _c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: t('Iznos'),
                suffixText: '€',
                errorText: _error,
                helperText: v == null
                    ? null
                    : t('S naknadom kupac plaća {0}', [
                        formatCredits(buyTotal(v)),
                      ]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Odustani')),
        ),
        FilledButton(
          key: const ValueKey('amount-submit'),
          onPressed: _submit,
          child: Text(t('Pošalji')),
        ),
      ],
    );
  }
}

/// Kupac nudi cijenu za oglas.
Future<void> showBargainDialog(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  if (blockGuest(context)) return;
  final ask = device.askPrice;
  final amount = await _amountDialog(
    context,
    title: t('Ponudi cijenu'),
    message: t(
      'Cijena je {0}. Prodavatelj može prihvatiti, odbiti ili dati protuponudu. Prihvaćena cijena vrijedi 48 sati samo za tebe.',
      [formatCredits(ask)],
    ),
    suggestion: roundCredits(ask * 0.9),
    max: ask,
  );
  if (amount == null || !context.mounted) return;
  await runWithLoading(
    context,
    () => ref.read(appProvider.notifier).makeBargain(device.id, amount),
    successMessage: t('Ponuda je poslana prodavatelju'),
  );
}

/// Kartica za kupca: gumb "Ponudi cijenu" ili stanje moje ponude.
class BuyerBargainCard extends ConsumerWidget {
  const BuyerBargainCard({super.key, required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(
      appProvider.select((s) => s.myBargainFor(device.id)),
    );
    final c = ref.read(appProvider.notifier);
    if (offer == null) {
      return OutlinedButton.icon(
        key: const ValueKey('make-offer'),
        onPressed: () => showBargainDialog(context, ref, device),
        icon: const Icon(Icons.price_change_outlined),
        label: Text(t('Ponudi cijenu')),
      );
    }
    final String text;
    final List<Widget> actions;
    switch (offer.status) {
      case BargainStatus.accepted:
        text = t('✅ Dogovorena cijena {0} vrijedi do {1}. Kupi gumbom iznad.', [
          formatCredits(offer.agreedPrice),
          formatDateTime(offer.validUntil!),
        ]);
        actions = const [];
      case BargainStatus.countered:
        text = t('↩️ Prodavatelj nudi {0} (tvoja ponuda: {1}).', [
          formatCredits(offer.counterAmount!),
          formatCredits(offer.amount),
        ]);
        actions = [
          FilledButton(
            key: const ValueKey('accept-counter'),
            onPressed: () => runWithLoading(
              context,
              () => c.acceptCounter(offer.id),
              successMessage: t('Dogovoreno! Sada možeš kupiti po toj cijeni.'),
            ),
            child: Text(t('Prihvati')),
          ),
          OutlinedButton(
            onPressed: () => runWithLoading(
              context,
              () => c.declineBargain(offer.id),
              successMessage: t('Odbijeno'),
            ),
            child: Text(t('Odbij')),
          ),
        ];
      default:
        text = t('⏳ Ponudio si {0} — čeka se odgovor prodavatelja.', [
          formatCredits(offer.amount),
        ]);
        actions = [
          TextButton(
            onPressed: () => runWithLoading(
              context,
              () => c.cancelBargain(offer.id),
              successMessage: t('Ponuda je povučena'),
            ),
            child: Text(t('Povuci ponudu')),
          ),
        ];
    }
    return Card(
      color: LoopColors.mint,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(text, key: const ValueKey('bargain-status')),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kartica za prodavatelja: ponude kupaca za ovaj oglas.
class SellerBargainsCard extends ConsumerWidget {
  const SellerBargainsCard({super.key, required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final list = state.bargainsToAnswer
        .where((o) => o.deviceId == device.id)
        .toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('Ponude kupaca ({0})', [list.length]),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            for (final o in list) BargainTile(offer: o),
          ],
        ),
      ),
    );
  }
}

/// Jedna ponuda s akcijama za onoga tko treba odgovoriti.
class BargainTile extends ConsumerWidget {
  const BargainTile({super.key, required this.offer, this.showItem = false});
  final PriceOffer offer;
  final bool showItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final me = state.currentUserId;
    final c = ref.read(appProvider.notifier);
    final iAmSeller = offer.sellerId == me;
    final other = state.userLabel(iAmSeller ? offer.buyerId : offer.sellerId);
    final now = DateTime.now();
    final stale = offer.staleAt(now);
    final status = stale
        ? BargainStatus.expired
        : offer.status == BargainStatus.accepted && !offer.usableAt(now)
        ? BargainStatus.expired
        : offer.status;

    final title = iAmSeller
        ? t('{0} nudi {1}', [other, formatCredits(offer.amount)])
        : t('Ponudio si {0} ({1})', [formatCredits(offer.amount), other]);
    final details = [
      if (showItem) '"${offer.deviceName}"',
      t('cijena {0}', [formatCredits(offer.listPrice)]),
      if (offer.counterAmount != null)
        t('protuponuda {0}', [formatCredits(offer.counterAmount!)]),
      status.label,
    ].join(' · ');

    final actions = <Widget>[
      if (!stale && iAmSeller && offer.status == BargainStatus.pending) ...[
        FilledButton(
          key: ValueKey('accept-bargain-${offer.id}'),
          onPressed: () => runWithLoading(
            context,
            () => c.acceptBargain(offer.id),
            successMessage: t('Prihvaćeno — kupac ima 48 sati za kupnju'),
          ),
          child: Text(t('Prihvati')),
        ),
        OutlinedButton(
          key: ValueKey('counter-bargain-${offer.id}'),
          onPressed: () async {
            final v = await _amountDialog(
              context,
              title: t('Protuponuda'),
              message: t('Kupac nudi {0}, cijena je {1}.', [
                formatCredits(offer.amount),
                formatCredits(offer.listPrice),
              ]),
              suggestion: roundCredits((offer.amount + offer.listPrice) / 2),
              max: offer.listPrice,
            );
            if (v == null || !context.mounted) return;
            await runWithLoading(
              context,
              () => c.counterBargain(offer.id, v),
              successMessage: t('Protuponuda je poslana'),
            );
          },
          child: Text(t('Protuponuda')),
        ),
        TextButton(
          onPressed: () => runWithLoading(
            context,
            () => c.declineBargain(offer.id),
            successMessage: t('Odbijeno'),
          ),
          child: Text(t('Odbij')),
        ),
      ],
      if (!stale && !iAmSeller && offer.status == BargainStatus.countered) ...[
        FilledButton(
          onPressed: () => runWithLoading(
            context,
            () => c.acceptCounter(offer.id),
            successMessage: t('Dogovoreno! Sada možeš kupiti po toj cijeni.'),
          ),
          child: Text(t('Prihvati')),
        ),
        TextButton(
          onPressed: () => runWithLoading(
            context,
            () => c.declineBargain(offer.id),
            successMessage: t('Odbijeno'),
          ),
          child: Text(t('Odbij')),
        ),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            details,
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: actions),
          ],
        ],
      ),
    );
  }
}
