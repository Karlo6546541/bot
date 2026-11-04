import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/auction.dart';
import '../models/delivery.dart';
import '../models/device.dart';
import '../models/price_offer.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/shop_widgets.dart' show BargainTile;
import 'auction_detail_screen.dart';
import 'auctions_screen.dart' show AuctionCard;
import 'deliveries_screen.dart' show DeliveryCard;
import 'device_detail_screen.dart';
import 'login_screen.dart';

/// Kupčeva strana "Moje" (kao Whatnot Activity): Kupnje, Licitacije,
/// Ponude i Spremljeno. Prodavačke stvari (aukcije, liveovi, otpremnice)
/// su u Seller Hubu; kupac samo dobiva obavijest i broj za praćenje.
class ActivityView extends ConsumerStatefulWidget {
  const ActivityView({super.key, this.onBrowse});

  /// Prijelaz na Početnu (gumb na praznom ekranu).
  final VoidCallback? onBrowse;

  @override
  ConsumerState<ActivityView> createState() => _ActivityViewState();
}

enum _Tab { purchases, bids, offers, saved }

class _ActivityViewState extends ConsumerState<ActivityView> {
  _Tab _tab = _Tab.purchases;
  final _chip = {for (final t in _Tab.values) t: 'all'};

  String get _f => _chip[_tab]!;

  Widget _empty(String title, {String? message}) => Padding(
    padding: const EdgeInsets.only(top: 56),
    child: EmptyState(
      icon: Icons.inbox_outlined,
      title: title,
      message: message,
      action: widget.onBrowse == null
          ? null
          : FilledButton(
              key: const ValueKey('activity-browse'),
              onPressed: widget.onBrowse,
              child: Text(t('Istraži')),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    if (s.currentUser?.isGuest ?? true) {
      return EmptyState(
        key: const ValueKey('my-guest'),
        icon: Icons.person_outline,
        title: t('Prijavi se za svoje kupnje i licitacije'),
        message: t('Ovdje pratiš što si kupio, licitiraš i spremio.'),
        action: FilledButton.icon(
          key: const ValueKey('my-guest-login'),
          onPressed: () => LoginScreen.open(context),
          icon: const Icon(Icons.login),
          label: Text(t('Prijavi se')),
        ),
      );
    }
    final me = s.currentUserId ?? '';
    final now = DateTime.now();

    // ------------------------------------------------------------ kupnje
    final all = [...s.myDeliveries]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final inProgress = [
      for (final d in all)
        if (d.confirmedAt == null) d,
    ];
    final completed = [
      for (final d in all)
        if (d.confirmedAt != null) d,
    ];
    final returns = [
      for (final d in all)
        if (d.dispute != null) d,
    ];
    final digital = s.myDigitalPurchases;
    final purchases = switch (_f) {
      'open' => inProgress,
      'done' => completed,
      'returns' => returns,
      _ => all,
    };

    // -------------------------------------------------------- licitacije
    final bidding = [
      for (final a in s.auctions)
        if (a.isActive &&
            !a.isExpired(now) &&
            a.sellerId != me &&
            a.bids.any((b) => b.userId == me))
          a,
    ]..sort((a, b) => a.endsAt.compareTo(b.endsAt));
    final leading = [
      for (final a in bidding)
        if (a.highestBid?.userId == me) a,
    ];
    final outbid = [
      for (final a in bidding)
        if (a.highestBid?.userId != me) a,
    ];
    final ended = [
      for (final a in s.auctions)
        if ((!a.isActive || a.isExpired(now)) &&
            a.sellerId != me &&
            a.bids.any((b) => b.userId == me))
          a,
    ]..sort((a, b) => b.endsAt.compareTo(a.endsAt));
    final bids = switch (_f) {
      'leading' => leading,
      'outbid' => outbid,
      'ended' => ended,
      _ => [...bidding, ...ended],
    };

    // ------------------------------------------------------------ ponude
    final offers =
        [
          for (final o in s.myBargains)
            if (o.buyerId == me) o,
        ]..sort(
          (a, b) => (b.updatedAt ?? b.createdAt).compareTo(
            a.updatedAt ?? a.createdAt,
          ),
        );
    final toAnswer = s.bargainsToAnswer.where((o) => o.buyerId == me).toSet();
    final shownOffers = switch (_f) {
      'answer' => [
        for (final o in offers)
          if (toAnswer.contains(o)) o,
      ],
      'accepted' => [
        for (final o in offers)
          if (o.status == BargainStatus.accepted) o,
      ],
      _ => offers,
    };

    // -------------------------------------------------------- spremljeno
    final saved = [
      for (final id in s.currentUser?.favorites ?? const <String>[])
        ?s.deviceById(id),
    ];
    bool isAuction(Device d) => s.activeAuctionFor(d.id) != null;
    final savedAuctions = [
      for (final d in saved)
        if (isAuction(d)) d,
    ];
    final savedBuyNow = [
      for (final d in saved)
        if (!isAuction(d)) d,
    ];
    final shownSaved = switch (_f) {
      'auction' => savedAuctions,
      'buynow' => savedBuyNow,
      _ => saved,
    };

    Widget chips(List<(String, String)> items) => SizedBox(
      height: 48,
      child: ListView(
        key: ValueKey('activity-chips-${_tab.name}'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        children: [
          for (final (id, label) in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('activity-chip-$id'),
                label: Text(label),
                selected: _f == id,
                showCheckmark: false,
                onSelected: (_) => setState(() => _chip[_tab] = id),
              ),
            ),
        ],
      ),
    );

    // Tab je dio kapsule (segmentirana kontrola): odabrani je svijetao.
    Widget tab(_Tab t0, String label, int badge) {
      final on = _tab == t0;
      return InkWell(
        key: ValueKey('activity-tab-${t0.name}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _tab = t0),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? LoopColors.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Badge(
            isLabelVisible: badge > 0,
            label: Text('$badge'),
            backgroundColor: LoopColors.accent,
            textColor: LoopColors.onAccent,
            offset: const Offset(10, -6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? LoopColors.background : LoopColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    final actions = all.where((d) => d.dispute == null && _needsBuyer(d, now));
    final body = switch (_tab) {
      _Tab.purchases => [
        chips([
          ('all', t('Sve')),
          ('open', t('U tijeku')),
          ('done', t('Završeno')),
          ('returns', t('Povrati')),
        ]),
        if (purchases.isEmpty && digital.isEmpty)
          _empty(
            t('Još nema kupnji'),
            message: t('Kad nešto kupiš ili osvojiš, pojavit će se ovdje.'),
          )
        else ...[
          for (final d in purchases)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: DeliveryCard(key: ValueKey('bought-${d.id}'), delivery: d),
            ),
          if (_f == 'all' || _f == 'done')
            for (final dev in digital) _savedRow(dev, key: 'dig-${dev.id}'),
        ],
      ],
      _Tab.bids => [
        chips([
          ('all', t('Sve')),
          ('leading', t('Vodim')),
          ('outbid', t('Nadmašen')),
          ('ended', t('Završene')),
        ]),
        if (bids.isEmpty)
          _empty(
            t('Još nisi licitirao'),
            message: t('Licitiraj na aukciji i ovdje pratiš ponude i pobjede.'),
          )
        else
          for (final a in bids)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).width < 600 ? 136 : 156,
                child: AuctionCard(auction: a, viewerId: me),
              ),
            ),
      ],
      _Tab.offers => [
        chips([
          ('all', t('Sve')),
          ('answer', t('Čeka tvoj odgovor')),
          ('accepted', t('Prihvaćene')),
        ]),
        if (shownOffers.isEmpty)
          _empty(
            t('Još nema ponuda'),
            message: t('Na oglasu dodirni "Ponudi cijenu" i predloži svoju.'),
          )
        else
          for (final o in shownOffers)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(kRadius),
                  onTap: () {
                    final d = s.deviceById(o.deviceId);
                    if (d != null) DeviceDetailScreen.open(context, d);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: BargainTile(offer: o, showItem: true),
                  ),
                ),
              ),
            ),
      ],
      _Tab.saved => [
        chips([
          ('all', t('Sve')),
          ('buynow', t('Kupi odmah')),
          ('auction', t('Aukcije')),
        ]),
        if (shownSaved.isEmpty)
          _empty(
            t('Još nemaš spremljenih stvari'),
            message: t('Dodirni srce na oglasu ili aukciji da ga spremiš.'),
          )
        else
          for (final d in shownSaved)
            _savedRow(
              d,
              auction: s.activeAuctionFor(d.id),
              key: 'saved-${d.id}',
            ),
      ],
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: LoopColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tab(_Tab.purchases, t('Kupnje'), actions.length),
                  tab(_Tab.bids, t('Licitacije'), outbid.length),
                  tab(_Tab.offers, t('Ponude'), toAnswer.length),
                  tab(_Tab.saved, t('Spremljeno'), 0),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            key: ValueKey('activity-list-${_tab.name}'),
            padding: const EdgeInsets.only(bottom: 96),
            children: body,
          ),
        ),
      ],
    );
  }

  /// Kupac mora nešto napraviti: potvrditi primitak ili preuzeti paket.
  static bool _needsBuyer(Delivery d, DateTime now) =>
      d.method != null &&
      d.method != DeliveryMethod.digital &&
      d.confirmedAt == null &&
      d.isDelivered(now);

  Widget _savedRow(Device d, {Auction? auction, required String key}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Material(
          color: LoopColors.surface,
          borderRadius: BorderRadius.circular(kRadius),
          child: InkWell(
            key: ValueKey(key),
            borderRadius: BorderRadius.circular(kRadius),
            onTap: () => auction != null
                ? AuctionDetailScreen.open(context, auction.id)
                : DeviceDetailScreen.open(context, d),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ItemThumb(device: d, size: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          auction != null
                              ? t('Aukcija · trenutno {0}', [
                                  formatCredits(
                                    auction.highestBid?.amount ??
                                        auction.startPrice,
                                  ),
                                ])
                              : d.isDigital
                              ? t('Digitalno')
                              : t('Kupi odmah'),
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (auction == null && !d.isDigital)
                    Text(
                      formatCredits(d.shownPrice),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  Icon(Icons.chevron_right, color: LoopColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      );
}
