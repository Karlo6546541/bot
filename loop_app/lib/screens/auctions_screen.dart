import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auction.dart';
import '../models/delivery.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../models/loop_transaction.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/live_service.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/countdown.dart';
import '../widgets/empty_state.dart';
import '../widgets/feed.dart' show FeedEntry;
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/user_avatar.dart';
import 'auction_detail_screen.dart';
import 'portfolio_screen.dart';
import 'seller_screens.dart';
import 'deliveries_screen.dart';
import 'device_detail_screen.dart';
import 'live_screens.dart';
import 'login_screen.dart';
import 'swipe_feed_screen.dart';
import '../l10n/tr.dart';

/// Moje: jedan red kartica (bez "Kupujem / Prodajem").
enum AuctionView {
  bought('Kupljeno', Icons.shopping_bag_outlined),
  myBids('Ponude', Icons.back_hand_outlined),
  items('Prodajem', Icons.sell_outlined),
  deliveries('Dostave', Icons.local_shipping_outlined),
  lives('Liveovi', Icons.videocam_outlined);

  const AuctionView(this._label, this.icon);
  final String _label;
  String get label => t(_label);
  final IconData icon;

  /// Ključ kartice (testovi i stari linkovi: Prodajem = "my-selling").
  String get key => this == items ? 'my-selling' : 'my-$name';
}

/// Odnos prijavljenog korisnika prema aukciji (za oznaku na kartici).
enum AuctionRole {
  seller('Tvoja aukcija', Icons.storefront),
  leading('Vodiš', Icons.emoji_events),
  outbid('Nadmašen si', Icons.trending_down),
  won('Osvojeno', Icons.emoji_events),
  none('', Icons.circle);

  const AuctionRole(this._label, this.icon);
  final String _label;
  String get label => t(_label);
  final IconData icon;

  /// Boja ovisi o temi, pa je getter (enum vrijednosti moraju biti const).
  Color get color => switch (this) {
    leading || won => LoopColors.success,
    outbid => LoopColors.error,
    seller || none => LoopColors.textSecondary,
  };

  static AuctionRole of(Auction a, String? me) {
    if (me == null) return none;
    if (a.sellerId == me) return seller;
    final top = a.highestBid?.userId == me;
    if (a.status == AuctionStatus.sold && top) return won;
    if (!a.isActive) return none;
    if (top) return leading;
    if (a.bids.any((b) => b.userId == me)) return outbid;
    return none;
  }
}

/// Jedna kartica u pregledu: live aukcija, obična aukcija ili predmet za
/// Kupi odmah.
class BrowseItem {
  BrowseItem.live(this.show, this.live, this.categories)
    : auction = null,
      device = null;
  BrowseItem.auction(Auction a, this.device)
    : auction = a,
      show = null,
      live = null,
      categories = {?device?.category};
  BrowseItem.item(Device d)
    : device = d,
      auction = null,
      show = null,
      live = null,
      categories = {d.category};

  /// Predmet za Kupi odmah (fiksna cijena).
  bool get isBuyNow => show == null && auction == null;

  final LiveShow? show;
  final LiveState? live;
  final Auction? auction;
  final Device? device;
  final Set<DeviceCategory> categories;

  FeedEntry get entry => show != null
      ? FeedEntry.live(show!.id)
      : auction != null
      ? FeedEntry.auction(auction!.id)
      : FeedEntry.item(device!.id);
}

/// Aukcije u stilu Whatnota: kategorije kao kartice, mreža kartica (prvo
/// live aukcije, zatim aukcije koje najprije završavaju), a dodir na
/// karticu otvara swipe feed (kao TikTok) kroz sve kartice odabrane
/// kategorije — live aukcije su u feedu cijela soba uživo.
class AuctionsScreen extends ConsumerStatefulWidget {
  const AuctionsScreen({super.key});

  @override
  ConsumerState<AuctionsScreen> createState() => _AuctionsScreenState();
}

class _AuctionsScreenState extends ConsumerState<AuctionsScreen> {
  static const _all = 'all';
  static const _live = 'live';
  static const _timed = 'timed';
  static const _buy = 'buy';

  /// [_all], [_live], [_timed], [_buy] ili naziv kategorije.
  String _filter = _all;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Zakazani live sam prelazi u "uživo", a završeni nestaje.
    if (ref.read(tickIntervalProvider) != null) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static List<BrowseItem> _items(AppState s) => browseItems(s);

  bool _matches(BrowseItem i) => switch (_filter) {
    _all => true,
    _live => i.show != null,
    _timed => i.auction != null,
    _buy => i.isBuyNow,
    final name => i.categories.any((c) => c.name == name),
  };

  String _filterLabel() => switch (_filter) {
    _all => t('Za tebe'),
    _live => t('Uživo'),
    _timed => t('Aukcije'),
    _buy => t('Kupi odmah'),
    final name => DeviceCategory.values.firstWhere((c) => c.name == name).label,
  };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId ?? '';
    final all = _items(s);
    final counts = <DeviceCategory, int>{};
    for (final i in all) {
      for (final c in i.categories) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    final cats = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    if (!{_all, _live, _timed, _buy}.contains(_filter) &&
        !cats.any((c) => c.name == _filter)) {
      _filter = _all;
    }
    final list = all.where(_matches).toList();
    final liveCount = all.where((i) => i.live?.isLive ?? false).length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('Istraži'),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('auction-rules'),
                  tooltip: t('Pravila aukcija'),
                  onPressed: () => showAuctionRules(context),
                  icon: const Icon(Icons.info_outline),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  key: const ValueKey('start-live'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kLiveRed,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => CreateLiveShowScreen.open(context),
                  icon: const Icon(Icons.videocam, size: 18),
                  label: Text(t('Live')),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 104,
            child: ListView(
              key: const ValueKey('auction-categories'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              children: [
                _CategoryCard(
                  id: _all,
                  label: t('Za tebe'),
                  icon: Icons.local_fire_department,
                  color: LoopColors.accent,
                  count: all.length,
                  selected: _filter == _all,
                  onTap: () => setState(() => _filter = _all),
                ),
                _CategoryCard(
                  id: _live,
                  label: t('Uživo'),
                  icon: Icons.videocam,
                  color: kLiveRed,
                  count: liveCount,
                  selected: _filter == _live,
                  onTap: () => setState(() => _filter = _live),
                ),
                _CategoryCard(
                  id: _timed,
                  label: t('Aukcije'),
                  icon: Icons.gavel,
                  color: LoopColors.accent,
                  count: all.where((i) => i.auction != null).length,
                  selected: _filter == _timed,
                  onTap: () => setState(() => _filter = _timed),
                ),
                _CategoryCard(
                  id: _buy,
                  label: t('Kupi odmah'),
                  icon: Icons.sell_outlined,
                  color: LoopColors.buyNow,
                  count: all.where((i) => i.isBuyNow).length,
                  selected: _filter == _buy,
                  onTap: () => setState(() => _filter = _buy),
                ),
                for (final c in cats)
                  _CategoryCard(
                    id: c.name,
                    label: c.label,
                    icon: c.icon,
                    color: c.color,
                    count: counts[c]!,
                    selected: _filter == c.name,
                    onTap: () => setState(() => _filter = c.name),
                  ),
              ],
            ),
          ),
        ),
        if (list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: _filter == _live
                  ? Icons.videocam_off_outlined
                  : Icons.gavel,
              title: _filter == _live
                  ? t('Nitko trenutno nije uživo')
                  : t('Ovdje još nema ničega'),
              message: t(
                'Pokreni live — predmeti se licitiraju jedan za drugim, brzo i uz chat.',
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverGrid(
              gridDelegate: const BrowseGridDelegate(),
              delegate: SliverChildBuilderDelegate(
                (context, i) => AuctionBrowseCard(
                  item: list[i],
                  viewerId: me,
                  onTap: () => SwipeFeedScreen.open(
                    context,
                    [for (final x in list) x.entry],
                    i,
                    title: _filterLabel(),
                  ),
                ),
                childCount: list.length,
              ),
            ),
          ),
      ],
    );
  }
}

/// Kategorija kao kartica (ikona, naziv, broj aukcija).
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Material(
      color: selected ? color.withValues(alpha: 0.18) : LoopColors.surface,
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        key: ValueKey('auction-cat-$id'),
        borderRadius: BorderRadius.circular(kRadius),
        onTap: onTap,
        child: Container(
          width: 108,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(
              color: selected ? color : LoopColors.surfaceHover,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: color),
                  ),
                  const Spacer(),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Kartica u mreži: fotografija s oznakom (UŽIVO / odbrojavanje), a ispod
/// prodavatelj, naziv i cijena — kao na Whatnotu.
class AuctionBrowseCard extends ConsumerWidget {
  const AuctionBrowseCard({
    super.key,
    required this.item,
    required this.viewerId,
    required this.onTap,
  });

  final BrowseItem item;
  final String viewerId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final show = item.show;
    final live = item.live;
    final a = item.auction;
    final lot = live?.current ?? live?.next ?? live?.lots.firstOrNull;
    final device = show != null
        ? (lot == null ? null : s.deviceById(lot.lot.deviceId))
        : item.device;
    final sellerId = show?.hostId ?? a?.sellerId ?? device!.ownerId ?? '';
    final seller = s.userById(sellerId);
    final title = show?.title ?? device?.name ?? a!.deviceName;
    final role = a == null ? AuctionRole.none : AuctionRole.of(a, viewerId);
    const pillText = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w900,
      fontSize: 11,
    );
    Widget pill(Widget child, [Color color = Colors.black54]) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );

    final Widget topLeft;
    if (live != null && live.isLive) {
      topLeft = const LiveBadge(small: true);
    } else if (show != null) {
      topLeft = pill(
        Text('📅 ${formatDateTime(show.startsAt)}', style: pillText),
      );
    } else if (a == null) {
      topLeft = pill(
        Text(
          device?.isDigital ?? false ? t('⬇️ Digitalno') : t('🏷️ Kupi odmah'),
          style: pillText,
        ),
        LoopColors.buyNow,
      );
    } else {
      topLeft = pill(
        AuctionCountdown(endsAt: a.endsAt, showIcon: false, style: pillText),
        LoopColors.accent,
      );
    }

    final String price;
    if (live != null) {
      price = live.current != null
          ? t('Sada: {0}', [formatCredits(live.current!.price)])
          : itemsLabel(show!.lots.length);
    } else if (a != null) {
      price = formatCredits(a.currentPrice);
    } else {
      price = formatCredits(s.priceForMe(device!));
    }

    final hot = (live?.hype ?? 0) >= 0.5;
    final reminded =
        show != null &&
        s.wantsReminder(show.id) &&
        (live?.isScheduled ?? false);

    final rating = s.ratingOf(sellerId);
    // Kao Vinted/Whatnot: slika 4:5 s oznakama, ispod cijena velikim
    // slovima, naziv i prodavatelj s ocjenom — sve kartice iste visine
    // (vidi [BrowseGridDelegate]).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey(
          show != null
              ? 'browse-live-${show.id}'
              : a != null
              ? 'browse-auction-${a.id}'
              : 'browse-item-${device!.id}',
        ),
        borderRadius: BorderRadius.circular(kRadius),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kRadius - 4),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    BrowseCardMedia(device: device, cover: show?.coverPath),
                    Positioned(
                      left: 8,
                      top: 8,
                      right: 40,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          topLeft,
                          if (live != null && live.isLive)
                            pill(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.visibility,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 3),
                                  Text('${live.viewers}', style: pillText),
                                ],
                              ),
                            ),
                          if (hot) pill(Text(t('🔥 vruće'), style: pillText)),
                        ],
                      ),
                    ),
                    if (show != null && (live?.isScheduled ?? false))
                      Positioned(
                        right: 4,
                        top: 4,
                        child: IconButton(
                          key: ValueKey('card-remind-${show.id}'),
                          tooltip: t('Podsjeti me'),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black45,
                          ),
                          onPressed: reminded
                              ? null
                              : () => remindMe(context, ref, show.id),
                          icon: Icon(
                            reminded
                                ? Icons.notifications_active
                                : Icons.notifications_none,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      )
                    else if (a != null && a.bids.isNotEmpty)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: pill(
                          Text(
                            a.bids.length == 1
                                ? t('1 ponuda')
                                : t('{0} ponuda', [a.bids.length]),
                            style: pillText,
                          ),
                        ),
                      ),
                    if (role != AuctionRole.none)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: RoleBadge(role: role),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              price,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                height: 1.15,
                color: a == null && show == null ? LoopColors.buyNow : null,
              ),
            ),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                UserAvatar(user: seller, size: 16),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    seller?.handle ?? show?.hostLabel ?? a?.sellerLabel ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (rating.count > 0)
                  Text(
                    '★ ${rating.average.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mreža kartica [AuctionBrowseCard]: stupci do [maxTileWidth], a visina
/// pločice izračunata iz širine (slika 4:5 + tri retka teksta) — sve
/// kartice jednako visoke, bez preljeva.
class BrowseGridDelegate extends SliverGridDelegate {
  const BrowseGridDelegate({
    this.maxTileWidth = 240,
    this.spacing = 12,
    this.runSpacing = 18,
  });

  final double maxTileWidth;
  final double spacing;
  final double runSpacing;

  /// Visina teksta ispod slike (cijena, naziv, prodavatelj).
  static const textHeight = 76.0;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final w = constraints.crossAxisExtent;
    final cols = ((w + spacing) / (maxTileWidth + spacing)).ceil().clamp(2, 99);
    final tileW = (w - spacing * (cols - 1)) / cols;
    final tileH = tileW * 5 / 4 + textHeight;
    return SliverGridRegularTileLayout(
      crossAxisCount: cols,
      mainAxisStride: tileH + runSpacing,
      crossAxisStride: tileW + spacing,
      childMainAxisExtent: tileH,
      childCrossAxisExtent: tileW,
      reverseCrossAxis: false,
    );
  }

  @override
  bool shouldRelayout(BrowseGridDelegate oldDelegate) =>
      oldDelegate.maxTileWidth != maxTileWidth ||
      oldDelegate.spacing != spacing ||
      oldDelegate.runSpacing != runSpacing;
}

/// Fotografija predmeta preko cijele kartice (ili ilustracija kategorije).
class BrowseCardMedia extends StatelessWidget {
  const BrowseCardMedia({super.key, required this.device, this.cover});
  final Device? device;

  /// Naslovna slika livea (ima prednost pred fotografijom predmeta).
  final String? cover;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final c = cover;
    if (c != null) {
      return LocalPhoto(
        path: c,
        cacheWidth: 480,
        fallback: d == null
            ? const ColoredBox(color: Color(0xFF7A3418))
            : ItemIllustration(category: d.category, iconSize: 40),
      );
    }
    if (d == null) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF3A1C71), kLiveRed]),
        ),
      );
    }
    final illustration = ItemIllustration(category: d.category, iconSize: 40);
    if (d.imagePaths.isEmpty) return illustration;
    return LocalPhoto(
      path: d.imagePaths.first,
      cacheWidth: 480,
      fallback: illustration,
    );
  }
}

/// Moje aukcije kao zaseban ekran (npr. iz obavijesti).
class MyAuctionsScreen extends StatelessWidget {
  const MyAuctionsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const MyAuctionsScreen()));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Moje'))),
    body: const MyAuctionsView(),
  );
}

/// "Moje": ponude, aukcije koje prodajem, moji liveovi i završene.
class MyAuctionsView extends ConsumerStatefulWidget {
  const MyAuctionsView({super.key, this.onBrowse});

  /// Prijelaz na Istraži (gumb na praznom ekranu).
  final VoidCallback? onBrowse;

  @override
  ConsumerState<MyAuctionsView> createState() => _MyAuctionsViewState();
}

class _MyAuctionsViewState extends ConsumerState<MyAuctionsView> {
  /// Najprije ono što je kupljeno (i čeka odabir dostave).
  AuctionView _view = AuctionView.bought;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    // Gost: umjesto praznih popisa poziv na prijavu.
    if (s.currentUser?.isGuest ?? true) {
      return EmptyState(
        key: const ValueKey('my-guest'),
        icon: Icons.person_outline,
        title: t('Prijavi se za svoje kupnje i prodaje'),
        message: t(
          'Ovdje pratiš što si kupio, svoje ponude, predmete i pakete za poslati.',
        ),
        action: FilledButton.icon(
          key: const ValueKey('my-guest-login'),
          onPressed: () => LoginScreen.open(context),
          icon: const Icon(Icons.login),
          label: Text(t('Prijavi se')),
        ),
      );
    }
    final me = s.currentUserId ?? '';
    final user = s.currentUser!;
    final bids = s.auctions
        .where((a) => a.bids.any((b) => b.userId == me))
        .toList();
    final lives = s.liveShows.where((l) => l.hostId == me).toList();
    // Kupljeno: prvo ono što čeka odabir dostave, zatim ostalo.
    final bought = [...s.myDeliveries]
      ..sort((a, b) {
        if (a.awaitingChoice != b.awaitingChoice) {
          return a.awaitingChoice ? -1 : 1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
    // Dostave: što šaljem i što stiže meni, na jednom mjestu.
    final toShip = s.toShip;
    final now = DateTime.now();
    final incoming = [
      for (final d in bought)
        if (d.method != DeliveryMethod.digital &&
            !d.awaitingChoice &&
            d.confirmedAt == null)
          d,
    ];
    final doneDeliveries = [
      for (final d in [...bought, ...s.sellerDeliveries])
        if (d.method != null &&
            d.method != DeliveryMethod.digital &&
            (d.confirmedAt != null || (d.sellerId == me && d.isDelivered(now))))
          d,
    ];
    final waiting =
        toShip.length + bought.where((d) => d.awaitingChoice).length;
    final pins = PickupPinsScreen.waiting(s.myDeliveries, now);
    // Otpremnice: svi paketi koje šaljem (kupac je odabrao dostavu).
    final notes =
        [
          for (final d in s.sellerDeliveries)
            if (d.method != null && d.method != DeliveryMethod.digital) d,
        ]..sort(
          (a, b) => (b.startedAt ?? b.createdAt).compareTo(
            a.startedAt ?? a.createdAt,
          ),
        );

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              for (final v in AuctionView.values)
                _MyTab(
                  view: v,
                  selected: _view == v,
                  badge: v == AuctionView.deliveries ? waiting : 0,
                  onTap: () => setState(() => _view = v),
                ),
            ],
          ),
        ),
        // PIN-ovi za preuzimanje: paketi koji me čekaju u paketomatu.
        if (pins.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Material(
              color: const Color(0xFF6BBE45).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(kRadius),
              child: ListTile(
                key: const ValueKey('my-pins'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kRadius),
                ),
                leading: const Text('📬', style: TextStyle(fontSize: 24)),
                title: Text(
                  t('PIN-ovi za preuzimanje'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  t('{0} u paketomatu — dodirni za PIN', ['${pins.length}']),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => PickupPinsScreen.open(context),
              ),
            ),
          ),
        // Otpremnice: zasebna kategorija (vlastiti ekran, BOX NOW).
        if (notes.isNotEmpty || _view == AuctionView.deliveries)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Material(
              color: LoopColors.surface,
              borderRadius: BorderRadius.circular(kRadius),
              child: ListTile(
                key: const ValueKey('my-notes'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kRadius),
                ),
                leading: const Icon(Icons.description_outlined),
                title: Text(
                  t('Otpremnice'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  t('{0} · kodovi i PIN-ovi za BOX NOW', ['${notes.length}']),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => DeliveryNotesScreen.open(context),
              ),
            ),
          ),
        // Zarada samo pod Prodajem.
        if (_view == AuctionView.items)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Card(
              child: ListTile(
                leading: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: LoopColors.textSecondary,
                ),
                title: Text(t('Zarada za isplatu')),
                subtitle: Text(
                  formatCredits(user.credits),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                trailing: FilledButton(
                  key: const ValueKey('profile-payout'),
                  onPressed: user.credits > 0
                      ? () => showPayoutDialog(context, ref)
                      : null,
                  child: Text(t('Isplati')),
                ),
              ),
            ),
          ),
      ],
    );
    if (_view == AuctionView.items) {
      return Column(
        children: [
          header,
          const Expanded(child: MyItemsView()),
        ],
      );
    }

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
      ),
    );

    final List<Widget> slivers = switch (_view) {
      AuctionView.bought when bought.isEmpty && s.myDigitalPurchases.isEmpty => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.shopping_bag_outlined,
            title: t('Još ništa nisi kupio'),
            message: t(
              'Ovdje su tvoje kupnje i pobjede — odabereš dostavu i pratiš paket.',
            ),
            action: widget.onBrowse == null
                ? null
                : FilledButton.icon(
                    key: const ValueKey('my-empty-browse'),
                    onPressed: widget.onBrowse,
                    icon: const Icon(Icons.explore_outlined),
                    label: Text(t('Istraži')),
                  ),
          ),
        ),
      ],
      AuctionView.bought => [
        SliverList.list(
          children: [
            for (final d in bought)
              if (d.awaitingChoice)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: DeliveryCard(
                    key: ValueKey('bought-${d.id}'),
                    delivery: d,
                  ),
                ),
          ],
        ),
        SliverToBoxAdapter(child: _PortfolioHeader(deliveries: bought)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.68,
            ),
            delegate: SliverChildListDelegate([
              for (final d in bought)
                if (!d.awaitingChoice) _BoughtTile(delivery: d),
              for (final dev in s.myDigitalPurchases) _BoughtTile(digital: dev),
            ]),
          ),
        ),
      ],
      AuctionView.myBids when bids.isEmpty => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.back_hand_outlined,
            title: t('Još nisi dao nijednu ponudu'),
            message: t(
              'Licitiraj u liveu ili na aukciji — tvoje ponude bit će ovdje.',
            ),
          ),
        ),
      ],
      AuctionView.myBids => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420,
              mainAxisExtent: MediaQuery.sizeOf(context).width < 600
                  ? 136
                  : 156,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => AuctionCard(auction: bids[i], viewerId: me),
              childCount: bids.length,
            ),
          ),
        ),
      ],
      AuctionView.deliveries
          when toShip.isEmpty &&
              incoming.isEmpty &&
              doneDeliveries.isEmpty &&
              !bought.any((d) => d.awaitingChoice) =>
        [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.local_shipping_outlined,
              title: t('Nema pošiljki'),
              message: t(
                'Ovdje su paketi koje šalješ i koji stižu tebi — s kodom za paketomat.',
              ),
            ),
          ),
        ],
      AuctionView.deliveries => [
        SliverList.list(
          key: const ValueKey('my-deliveries-list'),
          children: [
            if (bought.any((d) => d.awaitingChoice)) ...[
              section(t('⏳ Odaberi dostavu')),
              for (final d in bought)
                if (d.awaitingChoice)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: DeliveryCard(delivery: d),
                  ),
            ],
            if (toShip.isNotEmpty) ...[
              section(t('📤 Za poslati ({0})', ['${toShip.length}'])),
              for (final d in toShip)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _ToShipCard(delivery: d),
                ),
            ],
            if (incoming.isNotEmpty) ...[
              section(t('📥 Stiže meni')),
              for (final d in incoming)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: DeliveryCard(delivery: d),
                ),
            ],
            if (doneDeliveries.isNotEmpty) ...[
              section(t('✓ Završeno')),
              for (final d in doneDeliveries)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: d.sellerId == me
                      ? _ToShipCard(delivery: d)
                      : DeliveryCard(delivery: d),
                ),
            ],
            const SizedBox(height: 96),
          ],
        ),
      ],
      AuctionView.lives when lives.isEmpty => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.videocam_outlined,
            title: t('Još nisi bio uživo'),
            message: t('Pokreni live i prodaj prvi predmet.'),
            action: FilledButton.icon(
              key: const ValueKey('my-empty-live'),
              style: FilledButton.styleFrom(
                backgroundColor: kLiveRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => CreateLiveShowScreen.open(context),
              icon: const Icon(Icons.videocam),
              label: Text(t('Kreni uživo')),
            ),
          ),
        ),
      ],
      AuctionView.lives => [
        SliverList.list(
          children: [
            for (final l in lives)
              _MyLiveTile(show: l, state: s.liveStateOf(l)),
            const SizedBox(height: 96),
          ],
        ),
      ],
      AuctionView.items => const [],
    };

    return Column(
      children: [
        header,
        Expanded(child: CustomScrollView(slivers: slivers)),
      ],
    );
  }
}

/// Kartica u "Moje" (pet jednakih, bez listanja).
class _MyTab extends StatelessWidget {
  const _MyTab({
    required this.view,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final AuctionView view;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected ? LoopColors.textPrimary : LoopColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  backgroundColor: LoopColors.accent,
                  child: Icon(
                    view.icon,
                    size: 20,
                    color: selected
                        ? LoopColors.background
                        : LoopColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    view.label,
                    key: ValueKey(view.key),
                    maxLines: 1,
                    style: TextStyle(
                      color: selected
                          ? LoopColors.background
                          : LoopColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Moj live: naslov, stanje i prodano (dodir otvara sobu).
class _MyLiveTile extends StatelessWidget {
  const _MyLiveTile({required this.show, required this.state});
  final LiveShow show;
  final LiveState state;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('my-live-${show.id}'),
    leading: CircleAvatar(
      backgroundColor: state.isLive ? kLiveRed : LoopColors.surfaceHover,
      child: Icon(
        Icons.videocam,
        color: state.isLive ? Colors.white : LoopColors.textSecondary,
      ),
    ),
    title: Text(show.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      state.isLive
          ? t('Uživo sada')
          : state.isScheduled
          ? formatDateTime(show.startsAt)
          : t('Prodano {0} od {1} predmeta', [
              '${state.soldCount}',
              '${show.lots.length}',
            ]),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => LiveRoomScreen.open(context, show.id),
  );
}

/// Pravila aukcija (obvezujuće ponude, plaćanje karticom, produljenje).
Future<void> showAuctionRules(
  BuildContext context,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: LoopColors.surface,
  builder: (_) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('Pravila aukcija'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Text(
          t(
            '🔒  Ponuda je obvezujuća — ne može se povući ni smanjiti.\n\n🥇  Dok vodiš, ne možeš licitirati ponovno (možeš povisiti automatsku ponudu).\n\n💳  Pobjednik plaća karticom kad aukcija završi — ništa se ne blokira unaprijed.\n\n⏱️  Ponuda u zadnjoj minuti produljuje aukciju za 1 minutu.\n\n🎁  Pobjednik dobiva predmet i ne plaća naknadu. Prodavatelju se odbija 10 % samo od razlike iznad početne cijene.',
          ),
          style: const TextStyle(height: 1.4, fontSize: 15),
        ),
        const SizedBox(height: 16),
        Text(
          t('Live aukcije'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          t(
            '🔴  Predmeti se licitiraju jedan za drugim — brze licitacije od 5 ili 10 sekundi.\n\n⚡  Svaka ponuda dodaje 2 s na sat.\n\n👆  Povuci gore ili dolje za sljedeći live ili aukciju.',
          ),
          style: const TextStyle(height: 1.4, fontSize: 15),
        ),
      ],
    ),
  ),
);

/// Kartica aukcije: slika, naziv, trenutna cijena, broj ponuda,
/// odbrojavanje i oznaka odnosa korisnika (vodiš / nadmašen si …).
class AuctionCard extends ConsumerWidget {
  const AuctionCard({super.key, required this.auction, required this.viewerId});

  final Auction auction;
  final String viewerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = auction;
    final device = ref.watch(
      appProvider.select((s) => s.deviceById(a.deviceId)),
    );
    final role = AuctionRole.of(a, viewerId);
    final cat = device?.category;

    return Material(
      color: LoopColors.surface,
      borderRadius: BorderRadius.circular(kRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => AuctionDetailScreen.open(context, a.id),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(
              color: role == AuctionRole.leading || role == AuctionRole.won
                  ? LoopColors.success.withValues(alpha: 0.5)
                  : role == AuctionRole.outbid
                  ? LoopColors.error.withValues(alpha: 0.5)
                  : (cat?.color ?? LoopColors.surfaceHover).withValues(
                      alpha: 0.25,
                    ),
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (device != null)
                    ItemThumb(device: device, size: 52)
                  else
                    const SizedBox(width: 52, height: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device?.name ?? a.deviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          a.sellerId == viewerId
                              ? t('Prodaješ ti')
                              : t('Prodaje {0}', [a.sellerLabel]),
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
                  if (role != AuctionRole.none) RoleBadge(role: role),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.bids.isEmpty
                              ? t('Početna cijena')
                              : t('Najviša ponuda'),
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatCredits(a.currentPrice),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        a.bids.length == 1
                            ? t('1 ponuda')
                            : t('{0} ponuda', [a.bids.length]),
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (a.isActive)
                        AuctionCountdown(endsAt: a.endsAt)
                      else
                        Text(
                          a.statusLabelFor(ref.read(appProvider).currentUserId),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Oznaka odnosa korisnika prema aukciji (ikona + tekst, nikad samo boja).
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});
  final AuctionRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: role.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(role.icon, size: 14, color: role.color),
          const SizedBox(width: 4),
          Text(
            role.label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// "marko@loop.com" → "m***o@loop.com" (ponuđači su djelomično skriveni).
String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 1) return email;
  final name = email.substring(0, at);
  final masked = name.length <= 2
      ? '${name[0]}***'
      : '${name[0]}***${name[name.length - 1]}';
  return '$masked${email.substring(at)}';
}

/// Sve kartice za pregled: live aukcije (prvo uživo, pa zakazane), zatim
/// aukcije koje najprije završavaju.
/// Sve kartice za pregled: liveovi (u tijeku pa zakazani), aukcije koje
/// najprije završavaju i — uz [buyNow] — predmeti za Kupi odmah.
List<BrowseItem> browseItems(AppState s, {bool buyNow = true}) {
  final now = DateTime.now();
  return [
    for (final (show, live) in s.activeLives)
      BrowseItem.live(show, live, {
        if (show.category != null) DeviceCategory.fromName(show.category),
        for (final l in show.lots) ?s.deviceById(l.deviceId)?.category,
      }),
    for (final a in [
      ...s.activeAuctions,
    ]..sort((a, b) => a.endsAt.compareTo(b.endsAt)))
      if (!s.isBlocked(a.sellerId) && !a.isExpired(now))
        BrowseItem.auction(a, s.deviceById(a.deviceId)),
    if (buyNow)
      // Digitalni proizvodi se više ne prikazuju (pojednostavljeno).
      for (final d in s.marketDevices)
        if (d.isListed) BrowseItem.item(d),
  ];
}

/// Prodavatelj: paket za poslati — što, kome i kamo.
class _ToShipCard extends ConsumerWidget {
  const _ToShipCard({required this.delivery});
  final Delivery delivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = delivery;
    final s = ref.watch(appProvider);
    final buyer = s.userById(d.buyerId);
    final device = s.deviceById(d.deviceId);
    return Card(
      key: ValueKey('to-ship-${d.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => DeliveryDetailScreen.open(context, d.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (device != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ItemThumb(device: device, size: 52),
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
                    const SizedBox(height: 4),
                    Text(
                      t('Kupac: {0}', [
                        buyer?.name.isNotEmpty == true
                            ? '${buyer!.name} (${buyer.handle})'
                            : s.userLabel(d.buyerId),
                      ]),
                    ),
                    Text(
                      '${d.method?.label ?? ''}'
                      '${d.destination != null ? ' · ${d.destination}' : ''}',
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      d.status(DateTime.now()).label,
                      style: TextStyle(
                        color: LoopColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Kod za paketomat / etiketa (ime i adresa kupca).
              IconButton.filledTonal(
                key: ValueKey('to-ship-code-${d.id}'),
                tooltip: t('Kod za paketomat'),
                onPressed: () => DeliveryDetailScreen.open(context, d.id),
                icon: const Icon(Icons.qr_code_2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zaglavlje portfolija: broj kupljenih stvari i ukupno plaćeno.
class _PortfolioHeader extends ConsumerWidget {
  const _PortfolioHeader({required this.deliveries});
  final List<Delivery> deliveries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId;
    final paid = s.transactions
        .where(
          (t) =>
              t.buyerId == me &&
              t.type != TransactionType.payout &&
              t.type != TransactionType.delivery,
        )
        .fold<double>(0, (a, t) => a + t.price);
    final count = deliveries.length + s.myDigitalPurchases.length;
    return Padding(
      key: const ValueKey('bought-portfolio'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          const Text('🗂️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Moj portfolio'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                Text(
                  '${itemsLabel(count)} · ${t('ukupno {0}', [formatCredits(paid)])}',
                  style: TextStyle(color: LoopColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kupljena stvar u portfoliju: slika, naziv, plaćeno i stanje pošiljke.
class _BoughtTile extends ConsumerWidget {
  const _BoughtTile({this.delivery, this.digital});
  final Delivery? delivery;
  final Device? digital;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final d = delivery;
    final device = digital ?? s.deviceById(d!.deviceId);
    final id = digital?.id ?? d!.deviceId;
    final name = digital?.name ?? d!.deviceName;
    final paid = s.itemPaid(id, s.currentUserId);
    final (String label, Color color) = digital != null
        ? (t('⬇️ Digitalno'), LoopColors.info)
        : d!.isDelivered(DateTime.now())
        ? (t('✓ Stiglo'), LoopColors.buyNow)
        : (d.status(DateTime.now()).label, LoopColors.accent);
    return InkWell(
      key: ValueKey('bought-tile-$id'),
      borderRadius: BorderRadius.circular(kRadius),
      onTap: () => digital != null
          ? DeviceDetailScreen.open(context, digital!)
          : DeliveryDetailScreen.open(context, d!.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRadius - 4),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BrowseCardMedia(device: device),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            paid == null ? '' : t('Plaćeno {0}', [formatCredits(paid)]),
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
