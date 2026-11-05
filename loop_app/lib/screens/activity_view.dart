import '../config/design_variant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/auction.dart';
import '../models/delivery.dart';
import '../models/device.dart';
import '../models/price_offer.dart';
import '../providers/app_providers.dart';
import '../providers/my_activity_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/vision_glass.dart';
import '../widgets/my_online_activity.dart';
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
  const ActivityView({
    super.key,
    this.onBrowse,
    this.initialSection = 'purchases',
  });
  final String initialSection;

  /// Prijelaz na Početnu (gumb na praznom ekranu).
  final VoidCallback? onBrowse;

  @override
  ConsumerState<ActivityView> createState() => _ActivityViewState();
}

enum _Tab { purchases, bids, offers, saved }

class _ActivityViewState extends ConsumerState<ActivityView> {
  late _Tab _tab;
  @override
  void initState() {
    super.initState();
    _tab =
        _Tab.values
            .where((value) => value.name == widget.initialSection)
            .firstOrNull ??
        _Tab.purchases;
  }

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
    final online = ref.watch(myOnlineActivityProvider);
    final onlineOrders =
        online.asData?.value?.orders
            .where((o) => o['buyer_id'] == me)
            .toList() ??
        [];
    final onlineAwards = online.asData?.value?.unclaimedAwards ?? [];

    // ------------------------------------------------------------ kupnje
    final all = [...s.myDeliveries]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final digital = s.myDigitalPurchases;
    String deliveryGroup(Delivery d) {
      if (d.dispute != null) return t('Povrati');
      if (d.confirmedAt != null) return t('Završeno');
      if (d.method == null) return t('Čeka slanje');
      if (d.isDelivered(now)) return t('Stiglo');
      if (d.method == null ||
          (d.handedOverAt == null && d.stepIndex(now) <= 1)) {
        return t('Čeka slanje');
      }
      return t('Na putu');
    }

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
    // Tab je dio kapsule (segmentirana kontrola): odabrani je svijetao.
    Widget tab(_Tab t0, String label, int badge) {
      final on = _tab == t0;
      return InkWell(
        key: ValueKey('activity-tab-${t0.name}'),
        borderRadius: BorderRadius.circular(kSimpleDesign ? 99 : 12),
        onTap: () => setState(() => _tab = t0),
        child: Container(
          constraints: BoxConstraints(minHeight: kSimpleDesign ? 44 : 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? LoopColors.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(kSimpleDesign ? 99 : 12),
          ),
          child: Badge(
            isLabelVisible: !kSimpleDesign && badge > 0,
            label: Text('$badge'),
            backgroundColor: LoopColors.accent,
            textColor: LoopColors.onAccent,
            offset: const Offset(10, -6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: kSimpleDesign ? 15 : 14,
                fontWeight: kSimpleDesign || on
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: on
                    ? LoopColors.background
                    : kSimpleDesign
                    ? LoopColors.textPrimary
                    : LoopColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    final actions = all.where((d) => d.dispute == null && _needsBuyer(d, now));
    Widget section(String label, List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!kSimpleDesign)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
            child: Text(
              label,
              key: ValueKey('activity-section-$label'),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ),
        ...children,
      ],
    );
    Widget auction(Auction a) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).width < 600 ? 136 : 156,
        child: AuctionCard(auction: a, viewerId: me),
      ),
    );
    Widget offer(PriceOffer o) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadius),
          onTap: () {
            final d = s.deviceById(o.deviceId);
            if (d != null) DeviceDetailScreen.open(context, d);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: BargainTile(offer: o, showItem: true),
          ),
        ),
      ),
    );
    final panels = <_Tab, List<Widget>>{
      _Tab.purchases: [
        const MyOnlineActivityPanel(
          filter: 'bought',
          walletStyle: true,
          walletGroup: 'awards',
        ),
        if (all.isEmpty &&
            digital.isEmpty &&
            onlineOrders.isEmpty &&
            onlineAwards.isEmpty &&
            !online.isLoading &&
            !online.hasError)
          _empty(
            t('Još nema kupnji'),
            message: t('Kad nešto kupiš ili osvojiš, pojavit će se ovdje.'),
          ),
        for (final label in [
          t('Čeka plaćanje'),
          t('Čeka slanje'),
          t('Na putu'),
          t('Stiglo'),
          t('Završeno'),
          t('Povrati'),
          t('Otkazano'),
          t('Ostale narudžbe'),
        ])
          if (all.any((d) => deliveryGroup(d) == label) ||
              onlineOrders.any(
                (o) => MyOnlineActivityPanel.groupForOrder(o) == label,
              ))
            section(label, [
              if (onlineOrders.any(
                (o) => MyOnlineActivityPanel.groupForOrder(o) == label,
              ))
                MyOnlineActivityPanel(
                  filter: 'bought',
                  walletStyle: true,
                  walletGroup: label,
                ),
              for (final d in all.where((d) => deliveryGroup(d) == label))
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    kSimpleDesign ? 2 : 18,
                  ),
                  child: DeliveryCard(
                    key: ValueKey('bought-${d.id}'),
                    delivery: d,
                  ),
                ),
            ]),
        if (digital.isNotEmpty)
          section(t('Digitalno'), [
            for (final d in digital) _savedRow(d, key: 'dig-${d.id}'),
          ]),
      ],
      _Tab.bids: [
        if (bidding.isEmpty && ended.isEmpty)
          _empty(
            t('Još nisi licitirao'),
            message: t('Licitiraj na aukciji i ovdje pratiš ponude i pobjede.'),
          ),
        if (outbid.isNotEmpty)
          section(t('Nadmašen'), [for (final a in outbid) auction(a)]),
        if (leading.isNotEmpty)
          section(t('Vodim'), [for (final a in leading) auction(a)]),
        if (ended.isNotEmpty)
          section(t('Završene'), [for (final a in ended) auction(a)]),
      ],
      _Tab.offers: [
        if (offers.isEmpty)
          _empty(
            t('Još nema ponuda'),
            message: t('Na oglasu dodirni "Ponudi cijenu" i predloži svoju.'),
          ),
        for (final label in [
          t('Čeka tvoj odgovor'),
          t('Prihvaćene'),
          t('Ostale ponude'),
        ])
          if (offers.any(
            (o) =>
                (toAnswer.contains(o)
                    ? t('Čeka tvoj odgovor')
                    : o.status == BargainStatus.accepted
                    ? t('Prihvaćene')
                    : t('Ostale ponude')) ==
                label,
          ))
            section(label, [
              for (final o in offers.where(
                (o) =>
                    (toAnswer.contains(o)
                        ? t('Čeka tvoj odgovor')
                        : o.status == BargainStatus.accepted
                        ? t('Prihvaćene')
                        : t('Ostale ponude')) ==
                    label,
              ))
                offer(o),
            ]),
      ],
      _Tab.saved: [
        if (saved.isEmpty)
          _empty(
            t('Još nemaš spremljenih stvari'),
            message: t('Dodirni srce na oglasu ili aukciji da ga spremiš.'),
          ),
        if (savedBuyNow.isNotEmpty)
          section(t('Kupi odmah'), [
            for (final d in savedBuyNow) _savedRow(d, key: 'saved-${d.id}'),
          ]),
        if (savedAuctions.isNotEmpty)
          section(t('Aukcije'), [
            for (final d in savedAuctions)
              _savedRow(
                d,
                auction: s.activeAuctionFor(d.id),
                key: 'saved-${d.id}',
              ),
          ]),
      ],
    };

    final body = panels[_tab]!;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                kSimpleDesign ? 24 : 16,
                kSimpleDesign ? 4 : 8,
                kSimpleDesign ? 24 : 16,
                kSimpleDesign ? 14 : 8,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: VisionGlass(
                  quiet: !kSimpleDesign,
                  blur: false,
                  radius: kSimpleDesign ? 99 : 18,
                  padding: const EdgeInsets.all(4),
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
                padding: EdgeInsets.fromLTRB(
                  kSimpleDesign ? 8 : 0,
                  0,
                  kSimpleDesign ? 8 : 0,
                  kSimpleDesign ? 28 : 96,
                ),
                children: body,
              ),
            ),
          ],
        ),
      ),
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
