import '../providers/my_activity_provider.dart';
import '../widgets/my_online_activity.dart';
import '../config/features.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/country_widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auction.dart';
import '../models/delivery.dart';
import '../models/device.dart';
import '../models/live_show.dart';
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
import 'deliveries_screen.dart';
import 'device_detail_screen.dart';
import 'live_screens.dart';
import '../services/trade_service.dart' show TradeException;
import '../widgets/loop_snackbar.dart';
import 'login_screen.dart';
import 'swipe_feed_screen.dart';
import '../l10n/tr.dart';

/// Moje: četiri taba — Licitiram (aukcije na kojima licitiram i pobjede),
/// Aukcije (moje aukcije i predmeti), Live (kupljeno i prodano u liveu) i
/// Otpremnice (paketi za poslati).
enum MyTab {
  buying('Licitiram', Icons.gavel),
  selling('Aukcije', Icons.sell_outlined),
  live('Live', Icons.videocam_outlined),
  notes('Otpremnice', Icons.description_outlined);

  const MyTab(this._label, this.icon);
  final String _label;
  String get label => t(_label);
  final IconData icon;

  /// Ključ taba (testovi i stari linkovi: Aukcije = "my-selling").
  String get key => switch (this) {
    buying => 'my-buying',
    selling => 'my-selling',
    live => 'my-live',
    notes => 'my-notes-tab',
  };
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
                if (kBuyNowEnabled)
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
    this.reason,
  });

  final BrowseItem item;
  final String viewerId;
  final VoidCallback onTap;

  /// Zašto je predložen ("Jer pratiš @ana") — samo u "Za tebe".
  final String? reason;

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
        FittedBox(
          fit: BoxFit.scaleDown,
          child: AuctionCountdown(
            endsAt: a.endsAt,
            showIcon: false,
            style: pillText,
          ),
        ),
        LoopColors.accent,
      );
    }

    final String price;
    if (live != null) {
      price = live.cardLabel;
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
    // Kao Whatnot: prodavatelj iznad slike 4:5 s oznakama, ispod naziv
    // i cijena — sve kartice iste visine (vidi [BrowseGridDelegate]).
    final sellerRow = Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: Row(
        children: [
          UserAvatar(user: seller, size: 20),
          const SizedBox(width: 6),
          if (seller != null) ...[
            CountryBadge(
              code: seller.country,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              seller?.handle ?? show?.hostLabel ?? a?.sellerLabel ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
    );
    return Material(
      color: Colors.transparent,
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
            sellerRow,
            AspectRatio(
              aspectRatio: 4 / 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kRadius),
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
                    if (reason != null)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            key: const ValueKey('card-reason'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '✨ $reason',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: pillText,
                            ),
                          ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    price,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.2,
                      color: a == null && show == null
                          ? LoopColors.buyNow
                          : LoopColors.textSecondary,
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

  /// Visina prodavatelja iznad i teksta ispod slike (naziv, cijena).
  static const textHeight = 92.0;

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
  const MyAuctionsScreen({super.key, this.initialTab = MyTab.buying});

  final MyTab initialTab;

  static Future<void> open(BuildContext context, {MyTab initialTab = MyTab.buying}) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => MyAuctionsScreen(initialTab: initialTab)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Moje'))),
    body: MyAuctionsView(initialTab: initialTab),
  );
}

/// "Moje": Kupujem i Prodajem, a na vrhu samo ono što traži tvoju akciju.
class MyAuctionsView extends ConsumerStatefulWidget {
  const MyAuctionsView({super.key, this.onBrowse, this.initialTab = MyTab.buying});

  final MyTab initialTab;

  /// Prijelaz na Istraži (gumb na praznom ekranu).
  final VoidCallback? onBrowse;

  @override
  ConsumerState<MyAuctionsView> createState() => _MyAuctionsViewState();
}

class _MyAuctionsViewState extends ConsumerState<MyAuctionsView> {
  late MyTab _tab = widget.initialTab;

  /// Brzi prečac (filter) po tabu; 'all' = sve.
  String _buyFilter = 'all';
  String _sellFilter = 'all';
  String _liveFilter = 'all';
  String _notesFilter = 'all';

  /// Prikazani su i stariji završeni liveovi.
  bool _allLives = false;

  /// Brzi prečaci: chipovi s brojačima (prazni se skrivaju, osim odabranog).
  Widget _chips(
    List<(String, String, int)> items,
    String selected,
    ValueChanged<String> onSelect,
  ) => SizedBox(
    height: 44,
    child: ListView(
      key: const ValueKey('my-chips'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      children: [
        for (final (id, label, n) in items)
          if (id == 'all' || n > 0 || id == selected)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: ValueKey('my-chip-$id'),
                label: Text(id == 'all' ? label : '$label ($n)'),
                selected: id == selected,
                onSelected: (_) => onSelect(id),
              ),
            ),
      ],
    ),
  );

  Widget _auctionGrid(List<Auction> list, String me, {Key? key}) =>
      SliverPadding(
        key: key,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 420,
            mainAxisExtent: MediaQuery.sizeOf(context).width < 600 ? 136 : 156,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => AuctionCard(auction: list[i], viewerId: me),
            childCount: list.length,
          ),
        ),
      );

  Widget _note(String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: LoopColors.textSecondary),
      ),
    ),
  );

  Widget _section(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _pad(Widget child) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: child);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    // Gost: umjesto praznih popisa poziv na prijavu.
    if (s.currentUser?.isGuest ?? true) {
      return EmptyState(
        key: const ValueKey('my-guest'),
        icon: Icons.person_outline,
        title: t('Prijavi se za svoje licitacije i prodaje'),
        message: t(
          'Ovdje pratiš što si osvojio, svoje aukcije, liveove i pakete za poslati.',
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
    final online = ref.watch(myOnlineActivityProvider).asData?.value;
    final onlineBought =
        online?.orders.where((o) => o['buyer_id'] == me).toList() ?? [];
    final onlineSold =
        online?.orders.where((o) => o['seller_id'] == me).toList() ?? [];
    final onlineToShip = onlineSold.where((o) => o['status'] == 'paid').length;
    final onlineSent = onlineSold
        .where((o) => o['status'] == 'shipped' || o['status'] == 'delivered')
        .length;
    final onlineActions =
        (online?.unclaimedAwards.length ?? 0) +
        onlineBought.where((o) => o['status'] == 'awaiting_payment').length;
    final user = s.currentUser!;
    final now = DateTime.now();

    // ----------------------------------------------- dostave kupca (po izvoru)
    bool isLive(Delivery d) => d.id.startsWith('live-');
    bool physical(Delivery d) => d.method != DeliveryMethod.digital;
    final bought = [...s.myDeliveries]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    /// Popisi dostava kupca za aukcije ([live] = false) ili liveove.
    ({
      List<Delivery> actions,
      List<Delivery> confirm,
      List<Delivery> onTheWay,
      List<Delivery> done,
    })
    buyer(bool live) {
      final mine = [
        for (final d in bought)
          if (isLive(d) == live) d,
      ];
      final choose = [
        for (final d in mine)
          if (d.awaitingChoice) d,
      ];
      final pickup = [
        for (final d in mine)
          if (physical(d) &&
              d.autoConfirms &&
              d.confirmedAt == null &&
              d.status(now) == DeliveryStatus.inLocker)
            d,
      ];
      final confirm = [
        for (final d in mine)
          if (d.method != null &&
              physical(d) &&
              !d.autoConfirms &&
              d.confirmedAt == null &&
              d.isDelivered(now))
            d,
      ];
      return (
        actions: [...choose, ...pickup, ...confirm],
        confirm: [...pickup, ...confirm],
        onTheWay: [
          for (final d in mine)
            if (d.method != null &&
                physical(d) &&
                d.confirmedAt == null &&
                !d.isDelivered(now) &&
                !pickup.contains(d))
              d,
        ],
        done: [
          for (final d in mine)
            if (d.confirmedAt != null || d.method == DeliveryMethod.digital) d,
        ],
      );
    }

    final auc = buyer(false);
    final lv = buyer(true);
    final toShip = s.toShip;
    final shipLive = [
      for (final d in toShip)
        if (isLive(d)) d,
    ];
    final notes =
        [
          for (final d in s.sellerDeliveries)
            if (d.method != null && d.method != DeliveryMethod.digital) d,
        ]..sort(
          (a, b) => (b.startedAt ?? b.createdAt).compareTo(
            a.startedAt ?? a.createdAt,
          ),
        );
    final soldLive = [
      for (final d in s.sellerDeliveries)
        if (isLive(d) && d.sellerId == me) d,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final lives = [...s.liveShows.where((l) => l.hostId == me)]
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    final recentLives = [
      for (final l in lives)
        if (_allLives ||
            !s.liveStateOf(l).isOver ||
            now.difference(l.startsAt) < const Duration(days: 3))
          l,
    ];

    // --------------------------------------------------------------- aukcije
    final bidding =
        s.auctions
            .where(
              (a) =>
                  a.isActive &&
                  !a.isExpired(now) &&
                  a.sellerId != me &&
                  a.bids.any((b) => b.userId == me),
            )
            .toList()
          ..sort((a, b) => a.endsAt.compareTo(b.endsAt));
    final leading = [
      for (final a in bidding)
        if (a.highestBid?.userId == me) a,
    ];
    final outbid = [
      for (final a in bidding)
        if (a.highestBid?.userId != me) a,
    ];
    final lost =
        s.auctions
            .where(
              (a) =>
                  !a.isActive &&
                  a.sellerId != me &&
                  a.highestBid?.userId != me &&
                  a.bids.any((b) => b.userId == me),
            )
            .toList()
          ..sort((a, b) => b.endsAt.compareTo(a.endsAt));
    final myActive =
        s.auctions
            .where((a) => a.sellerId == me && a.isActive && !a.isExpired(now))
            .toList()
          ..sort((a, b) => a.endsAt.compareTo(b.endsAt));
    final myEnded =
        s.auctions
            .where((a) => a.sellerId == me && (!a.isActive || a.isExpired(now)))
            .toList()
          ..sort((a, b) => b.endsAt.compareTo(a.endsAt));

    Widget sectionBox(String title, {Widget? trailing}) =>
        SliverToBoxAdapter(child: _section(title, trailing: trailing));

    Widget tabButton(MyTab t0, int badge) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: _tab == t0 ? LoopColors.textPrimary : LoopColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: ValueKey(t0.key),
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _tab = t0),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Badge(
                    isLabelVisible: badge > 0,
                    label: Text('$badge'),
                    backgroundColor: LoopColors.accent,
                    child: Icon(
                      t0.icon,
                      size: 20,
                      color: _tab == t0
                          ? LoopColors.background
                          : LoopColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      t0.label,
                      maxLines: 1,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: _tab == t0
                            ? LoopColors.background
                            : LoopColors.textPrimary,
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

    final tabs = Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Row(
        children: [
          tabButton(MyTab.buying, auc.actions.length),
          tabButton(MyTab.selling, 0),
          tabButton(
            MyTab.live,
            lv.actions.length + shipLive.length + onlineActions + onlineToShip,
          ),
          tabButton(MyTab.notes, toShip.length + onlineToShip),
        ],
      ),
    );

    Widget body(List<Widget> slivers, {Key? key}) => Expanded(
      child: CustomScrollView(
        key: key,
        slivers: [
          if (_tab == MyTab.live || _tab == MyTab.notes)
            SliverToBoxAdapter(
              child: MyOnlineActivityPanel(
                shipmentsOnly: _tab == MyTab.notes,
                filter: _tab == MyTab.notes ? _notesFilter : _liveFilter,
              ),
            ),
          ...slivers,
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );

    // Odjeljci dostava kupca (zajednički za Licitiram i Live).
    List<Widget> actionSlivers(List<Delivery> list) => [
      sectionBox(t('⚡ Treba tvoju akciju ({0})', ['${list.length}'])),
      SliverList.list(
        key: const ValueKey('my-actions'),
        children: [
          for (final d in list)
            _pad(DeliveryCard(key: ValueKey('bought-${d.id}'), delivery: d)),
        ],
      ),
    ];
    List<Widget> onWaySlivers(List<Delivery> list) => [
      sectionBox(t('📥 Na putu do tebe ({0})', ['${list.length}'])),
      SliverList.list(
        key: const ValueKey('my-on-the-way'),
        children: [for (final d in list) _pad(DeliveryCard(delivery: d))],
      ),
    ];
    // Osvojeno: obične stvari (s dostavom) i digitalno (datoteke) odvojeno.
    final liveDigitalIds = {
      for (final x in s.transactions)
        if (x.id.startsWith('livebuy-') && x.buyerId == me) x.deviceId,
    };
    final digLive = [
      for (final d in s.myDigitalPurchases)
        if (liveDigitalIds.contains(d.id)) d,
    ];
    final digAuc = [
      for (final d in s.myDigitalPurchases)
        if (!liveDigitalIds.contains(d.id)) d,
    ];
    final physDone = [
      for (final d in auc.done)
        if (d.method != DeliveryMethod.digital) d,
    ];
    final physDoneLive = [
      for (final d in lv.done)
        if (d.method != DeliveryMethod.digital) d,
    ];
    SliverPadding tiles(List<Widget> children) => SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.68,
        ),
        delegate: SliverChildListDelegate(children),
      ),
    );
    List<Widget> doneSlivers(List<Delivery> list, String title) => [
      sectionBox(title),
      tiles([for (final d in list) _BoughtTile(delivery: d)]),
    ];
    List<Widget> digitalSlivers(List<Device> list) => [
      sectionBox(t('💾 Digitalno ({0})', ['${list.length}'])),
      tiles([for (final dev in list) _BoughtTile(digital: dev)]),
    ];

    // ============================================================ Licitiram
    if (_tab == MyTab.buying) {
      final f = _buyFilter;
      final doneCount = physDone.length;
      final empty =
          auc.actions.isEmpty &&
          bidding.isEmpty &&
          auc.onTheWay.isEmpty &&
          doneCount == 0 &&
          digAuc.isEmpty &&
          lost.isEmpty;
      final slivers = <Widget>[
        if (f == 'all') ...[
          if (empty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.gavel,
                title: t('Još nisi licitirao'),
                message: t(
                  'Licitiraj na aukciji — ovdje pratiš ponude, pobjede i paket.',
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
          if (auc.actions.isNotEmpty) ...actionSlivers(auc.actions),
          if (bidding.isNotEmpty) ...[
            sectionBox(t('Licitiram ({0})', ['${bidding.length}'])),
            _auctionGrid(bidding, me, key: const ValueKey('my-bidding')),
          ],
          if (auc.onTheWay.isNotEmpty) ...onWaySlivers(auc.onTheWay),
          if (doneCount > 0)
            ...doneSlivers(physDone, t('✓ Osvojeno ({0})', ['$doneCount'])),
          if (digAuc.isNotEmpty) ...digitalSlivers(digAuc),
        ] else if (f == 'action') ...[
          if (auc.actions.isEmpty)
            _note(t('Ništa ne čeka tvoju akciju.'))
          else
            ...actionSlivers(auc.actions),
        ] else if (f == 'confirm') ...[
          if (auc.confirm.isEmpty)
            _note(t('Nema paketa za preuzimanje ili potvrdu.'))
          else ...[
            sectionBox(t('📬 Potvrda paketa ({0})', ['${auc.confirm.length}'])),
            SliverList.list(
              children: [
                for (final d in auc.confirm)
                  _pad(
                    DeliveryCard(key: ValueKey('bought-${d.id}'), delivery: d),
                  ),
              ],
            ),
          ],
        ] else if (f == 'leading') ...[
          if (leading.isEmpty)
            _note(t('Trenutno nigdje ne voziš.'))
          else
            _auctionGrid(leading, me, key: const ValueKey('my-bidding')),
        ] else if (f == 'outbid') ...[
          if (outbid.isEmpty)
            _note(t('Nitko te nije nadmašio.'))
          else
            _auctionGrid(outbid, me, key: const ValueKey('my-bidding')),
        ] else if (f == 'digital') ...[
          if (digAuc.isEmpty)
            _note(t('Još nemaš kupljenih digitalnih proizvoda.'))
          else
            ...digitalSlivers(digAuc),
        ] else if (f == 'way') ...[
          if (auc.onTheWay.isEmpty)
            _note(t('Ništa ti trenutno ne stiže.'))
          else
            ...onWaySlivers(auc.onTheWay),
        ] else ...[
          if (doneCount == 0 && lost.isEmpty)
            _note(t('Još nema završenih aukcija.')),
          if (doneCount > 0)
            ...doneSlivers(physDone, t('✓ Osvojeno ({0})', ['$doneCount'])),
          if (lost.isNotEmpty) ...[
            sectionBox(t('Nisam pobijedio ({0})', ['${lost.length}'])),
            _auctionGrid(lost, me, key: const ValueKey('my-lost')),
          ],
        ],
      ];
      return Column(
        children: [
          tabs,
          _chips(
            [
              ('all', t('Sve'), 0),
              ('action', t('Treba akciju'), auc.actions.length),
              ('confirm', t('Potvrda paketa'), auc.confirm.length),
              ('leading', t('Vodim'), leading.length),
              ('outbid', t('Nadmašen'), outbid.length),
              ('way', t('Na putu'), auc.onTheWay.length),
              ('done', t('Završeno'), doneCount + lost.length),
              ('digital', t('Digitalno'), digAuc.length),
            ],
            f,
            (v) => setState(() => _buyFilter = v),
          ),
          body(slivers, key: const ValueKey('my-bought')),
        ],
      );
    }

    // =============================================================== Aukcije
    if (_tab == MyTab.selling) {
      final f = _sellFilter;
      final activeSlivers = <Widget>[
        sectionBox(t('⏱ Na aukciji ({0})', ['${myActive.length}'])),
        _auctionGrid(myActive, me, key: const ValueKey('my-active-auctions')),
      ];
      List<Widget> endedSlivers(int? limit) => [
        sectionBox(
          t('✓ Završene aukcije ({0})', ['${myEnded.length}']),
          trailing: limit != null && myEnded.length > limit
              ? TextButton(
                  key: const ValueKey('my-ended-all'),
                  onPressed: () => setState(() => _sellFilter = 'ended'),
                  child: Text(t('Sve')),
                )
              : null,
        ),
        _auctionGrid(
          limit == null ? myEnded : myEnded.take(limit).toList(),
          me,
          key: const ValueKey('my-ended-auctions'),
        ),
      ];
      final chips = _chips(
        [
          ('all', t('Sve'), 0),
          ('active', t('Na aukciji'), myActive.length),
          ('ended', t('Završene'), myEnded.length),
          ('saved', t('Spremljeno'), 0),
        ],
        f,
        (v) => setState(() => _sellFilter = v),
      );
      if (f == 'all' || f == 'saved') {
        return Column(
          children: [
            tabs,
            chips,
            Expanded(
              child: MyItemsView(
                fixedFilter: f == 'saved' ? ItemStatus.draft : null,
                leading: f == 'saved'
                    ? const []
                    : [
                        if (myActive.isNotEmpty) ...activeSlivers,
                        if (myEnded.isNotEmpty) ...endedSlivers(3),
                        sectionBox(t('Moji predmeti')),
                      ],
              ),
            ),
          ],
        );
      }
      return Column(
        children: [
          tabs,
          chips,
          body(
            f == 'active'
                ? (myActive.isEmpty
                      ? [_note(t('Nemaš aukcija koje traju.'))]
                      : activeSlivers)
                : (myEnded.isEmpty
                      ? [_note(t('Još nema završenih aukcija.'))]
                      : endedSlivers(null)),
          ),
        ],
      );
    }

    // ================================================================== Live
    if (_tab == MyTab.live) {
      final f = _liveFilter;
      final liveBoughtSlivers = <Widget>[
        if (lv.actions.isNotEmpty) ...actionSlivers(lv.actions),
        if (lv.onTheWay.isNotEmpty) ...onWaySlivers(lv.onTheWay),
        if (physDoneLive.isNotEmpty)
          ...doneSlivers(
            physDoneLive,
            t('✓ Kupljeno u liveu ({0})', ['${physDoneLive.length}']),
          ),
        if (digLive.isNotEmpty) ...digitalSlivers(digLive),
      ];
      final soldSlivers = <Widget>[
        sectionBox(t('💸 Prodano u liveu ({0})', ['${soldLive.length}'])),
        SliverList.list(
          key: const ValueKey('my-live-sold'),
          children: [for (final d in soldLive) _pad(_ToShipCard(delivery: d))],
        ),
      ];
      final liveSlivers = <Widget>[
        sectionBox(
          t('🔴 Moji liveovi'),
          trailing: lives.length > recentLives.length || _allLives
              ? TextButton(
                  key: const ValueKey('my-lives-all'),
                  onPressed: () => setState(() => _allLives = !_allLives),
                  child: Text(_allLives ? t('Samo nedavni') : t('Svi')),
                )
              : null,
        ),
        SliverList.list(
          key: const ValueKey('my-lives'),
          children: [
            for (final l in recentLives)
              _MyLiveTile(show: l, state: s.liveStateOf(l)),
          ],
        ),
      ];
      final startLive = SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: FilledButton.icon(
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
      );
      final emptyAll =
          liveBoughtSlivers.isEmpty &&
          soldLive.isEmpty &&
          lives.isEmpty &&
          (online == null ||
              (online.rooms.isEmpty &&
                  online.bids.isEmpty &&
                  online.awards.isEmpty &&
                  online.orders.isEmpty));
      final slivers = <Widget>[
        if (f == 'all') ...[
          startLive,
          if (emptyAll)
            _note(
              t(
                'Još nema kupnji ni prodaja u liveu. Licitiraj ili pokreni live.',
              ),
            ),
          ...liveBoughtSlivers,
          if (soldLive.isNotEmpty) ...soldSlivers,
          if (lives.isNotEmpty) ...liveSlivers,
        ] else if (f == 'bought') ...[
          if (liveBoughtSlivers.isEmpty &&
              onlineBought.isEmpty &&
              (online?.unclaimedAwards.isEmpty ?? true))
            _note(t('Još nisi ništa kupio u liveu.'))
          else
            ...liveBoughtSlivers,
        ] else if (f == 'sold') ...[
          if (soldLive.isEmpty && onlineSold.isEmpty)
            _note(t('Još nisi ništa prodao u liveu.'))
          else
            ...soldSlivers,
        ] else ...[
          startLive,
          if (lives.isEmpty && (online?.rooms.isEmpty ?? true))
            _note(t('Još nisi bio uživo.'))
          else
            ...liveSlivers,
        ],
      ];
      return Column(
        children: [
          tabs,
          _chips(
            [
              ('all', t('Sve'), 0),
              (
                'bought',
                t('Kupljeno'),
                lv.actions.length +
                    lv.onTheWay.length +
                    physDoneLive.length +
                    digLive.length +
                    onlineBought.length +
                    (online?.unclaimedAwards.length ?? 0),
              ),
              ('sold', t('Prodano'), soldLive.length + onlineSold.length),
              (
                'mine',
                t('Moji liveovi'),
                lives.length + (online?.rooms.length ?? 0),
              ),
            ],
            f,
            (v) => setState(() => _liveFilter = v),
          ),
          body(slivers),
        ],
      );
    }

    // ========================================================== Otpremnice
    final f = _notesFilter;
    final sentNotes = [
      for (final d in notes)
        if (d.confirmedAt != null || d.isDelivered(now)) d,
    ];
    final handedNotes = [
      for (final d in notes)
        if (d.handedOverAt != null &&
            !(d.confirmedAt != null || d.isDelivered(now)))
          d,
    ];
    final shipSlivers = <Widget>[
      sectionBox(t('📦 Za poslati ({0})', ['${toShip.length}'])),
      SliverList.list(
        key: const ValueKey('my-deliveries-list'),
        children: [for (final d in toShip) _pad(_ToShipCard(delivery: d))],
      ),
    ];
    final noteSlivers = <Widget>[
      sectionBox(t('🧾 Sve otpremnice ({0})', ['${notes.length}'])),
      SliverList.list(
        key: const ValueKey('my-notes-list'),
        children: [
          for (final d in notes)
            _pad(
              Material(
                color: LoopColors.surface,
                borderRadius: BorderRadius.circular(kRadius),
                child: ListTile(
                  key: ValueKey('note-${d.id}'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kRadius),
                  ),
                  leading: const Icon(Icons.description_outlined),
                  title: Text(
                    d.trackingNumber ?? d.id,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  subtitle: Text(
                    '${d.deviceName}\n${s.userById(d.buyerId)?.handle ?? ''}'
                    ' · ${formatDateTime(d.startedAt ?? d.createdAt)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    d.status(now).label,
                    style: TextStyle(
                      color: d.isDelivered(now)
                          ? LoopColors.buyNow
                          : LoopColors.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () => DeliveryNoteScreen.open(context, d.id),
                ),
              ),
            ),
        ],
      ),
    ];
    final noteList = switch (f) {
      'ship' =>
        toShip.isEmpty
            ? (onlineToShip == 0
                  ? [_note(t('Nemaš paketa za poslati.'))]
                  : <Widget>[])
            : shipSlivers,
      'handed' =>
        handedNotes.isEmpty
            ? [_note(t('Još nema paketa predanih dostavljaču.'))]
            : [
                sectionBox(
                  t('📦 Predano dostavljaču ({0})', ['${handedNotes.length}']),
                ),
                SliverList.list(
                  children: [
                    for (final d in handedNotes) _pad(_ToShipCard(delivery: d)),
                  ],
                ),
              ],
      'sent' =>
        sentNotes.isEmpty && onlineSent == 0
            ? [_note(t('Još nema poslanih paketa.'))]
            : [
                sectionBox(t('✓ Poslano ({0})', ['${sentNotes.length}'])),
                SliverList.list(
                  children: [
                    for (final d in sentNotes) _pad(_ToShipCard(delivery: d)),
                  ],
                ),
              ],
      _ =>
        notes.isEmpty && toShip.isEmpty && onlineSold.isEmpty
            ? [
                _note(
                  t(
                    'Kad kupac odabere dostavu, ovdje dobiješ otpremnicu s kodom za paketomat.',
                  ),
                ),
              ]
            : [
                if (toShip.isNotEmpty) ...shipSlivers,
                if (notes.isNotEmpty) ...noteSlivers,
              ],
    };
    return Column(
      children: [
        tabs,
        _chips(
          [
            ('all', t('Sve'), 0),
            ('ship', t('Za poslati'), toShip.length + onlineToShip),
            ('handed', t('Predano'), handedNotes.length),
            ('sent', t('Poslano'), sentNotes.length + onlineSent),
          ],
          f,
          (v) => setState(() => _notesFilter = v),
        ),
        body(noteList),
      ],
    );
  }
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
List<BrowseItem> browseItems(AppState s, {bool buyNow = kBuyNowEnabled}) {
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
                          '${d.method == null ? '' : d.serviceLabel}'
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
              if (d.method != null && d.method != DeliveryMethod.digital) ...[
                const SizedBox(height: 10),
                d.handedOverAt != null
                    ? Text(
                        t('✓ Predano dostavljaču'),
                        key: ValueKey('to-ship-handed-${d.id}'),
                        style: TextStyle(
                          color: LoopColors.buyNow,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : FilledButton.icon(
                        key: ValueKey('to-ship-handover-${d.id}'),
                        onPressed: () async {
                          try {
                            await ref
                                .read(appProvider.notifier)
                                .markHandedOver(d.id);
                            showLoopSnackBar(
                              t('Zabilježeno: paket je predan.'),
                            );
                          } on TradeException catch (e) {
                            showLoopSnackBar(e.message, error: true);
                          }
                        },
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                        label: Text(t('Predao sam paket')),
                      ),
              ],
              // Otpremnica nastaje sama čim kupac odabere dostavu.
              if (d.method != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: ValueKey('to-ship-note-${d.id}'),
                  onPressed: () => DeliveryNoteScreen.open(context, d.id),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: Text(t('Otpremnica · ispiši ili preuzmi')),
                ),
              ],
            ],
          ),
        ),
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
