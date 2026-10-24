import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auction.dart';
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
import 'seller_screens.dart';
import 'deliveries_screen.dart';
import 'create_auction_screen.dart';
import 'live_screens.dart';
import 'swipe_feed_screen.dart';
import '../l10n/tr.dart';

/// Moje: na kojima licitiram, koje prodajem, moji liveovi i završene.
enum AuctionView {
  // Kupujem
  bought('Kupljeno', Icons.shopping_bag_outlined, selling: false),
  myBids('Ponude', Icons.back_hand_outlined, selling: false),
  // Prodajem
  items('Predmeti', Icons.inventory_2_outlined, selling: true),
  mine('Aukcije', Icons.gavel, selling: true),
  lives('Liveovi', Icons.videocam_outlined, selling: true);

  const AuctionView(this._label, this.icon, {required this.selling});
  final String _label;
  String get label => t(_label);
  final IconData icon;

  /// Dio "Prodajem" (inače "Kupujem").
  final bool selling;
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
                  color: const Color(0xFF1FA463),
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
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                childAspectRatio: 0.52,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
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
        Text(t('🏷️ Kupi odmah'), style: pillText),
        const Color(0xFF1FA463),
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
          : t('{0} predmeta', ['${show!.lots.length}']);
    } else if (a != null) {
      price = formatCredits(a.currentPrice);
    } else {
      price = formatCredits(s.priceForMe(device!));
    }

    final category = item.categories.firstOrNull;
    final hot = (live?.hype ?? 0) >= 0.5;
    final reminded =
        show != null &&
        s.wantsReminder(show.id) &&
        (live?.isScheduled ?? false);

    // Kao Whatnot: prodavatelj iznad slike, slika s oznakama, ispod naslov
    // i kategorija.
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
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  UserAvatar(user: seller, size: 22),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      seller?.handle ?? show?.hostLabel ?? a?.sellerLabel ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (s.ratingOf(sellerId).count > 0)
                    Text(
                      '★ ${s.ratingOf(sellerId).average.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kRadius - 4),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CardMedia(device: device, cover: show?.coverPath),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                          stops: [0.6, 1],
                        ),
                      ),
                    ),
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
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              price,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                shadows: [
                                  Shadow(blurRadius: 6, color: Colors.black54),
                                ],
                              ),
                            ),
                          ),
                          if (role != AuctionRole.none) RoleBadge(role: role),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.2,
              ),
            ),
            Text(
              [?category?.label, if (hot) t('🔥 vruće')].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fotografija predmeta preko cijele kartice (ili ilustracija kategorije).
class _CardMedia extends StatelessWidget {
  const _CardMedia({required this.device, this.cover});
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

  List<Auction> _filter(AppState s, String me) => switch (_view) {
    AuctionView.myBids =>
      s.auctions.where((a) => a.bids.any((b) => b.userId == me)).toList(),
    AuctionView.mine => s.auctions.where((a) => a.sellerId == me).toList(),
    AuctionView.lives || AuctionView.bought || AuctionView.items => const [],
  };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId ?? '';
    final list = _filter(s, me);
    final lives = s.liveShows.where((l) => l.hostId == me).toList();
    // Kupljeno: prvo ono što čeka odabir dostave, zatim u dostavi.
    final bought = [...s.myDeliveries]
      ..sort((a, b) {
        if (a.awaitingChoice != b.awaitingChoice) {
          return a.awaitingChoice ? -1 : 1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
    final empty = switch (_view) {
      AuctionView.lives => lives.isEmpty,
      AuctionView.bought => bought.isEmpty,
      _ => list.isEmpty,
    };

    final selling = _view.selling;
    final user = s.currentUser;
    // Moje = dvije stvari: što kupujem i što prodajem.
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: Text(t('Kupujem'), key: const ValueKey('my-buying')),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: Text(t('Prodajem'), key: const ValueKey('my-selling')),
              ),
            ],
            selected: {selling},
            onSelectionChanged: (v) => setState(
              () => _view = v.first ? AuctionView.items : AuctionView.bought,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              for (final v in AuctionView.values)
                if (v.selling == selling)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(v.icon, size: 18),
                      label: Text(v.label, key: ValueKey('my-${v.name}')),
                      selected: _view == v,
                      onSelected: (_) => setState(() => _view = v),
                    ),
                  ),
            ],
          ),
        ),
        // Zarada (Prodajem): iznos i isplata.
        if (selling && user != null)
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

    return Column(
      children: [
        header,
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (empty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: switch (_view) {
                      AuctionView.lives => Icons.videocam_outlined,
                      AuctionView.bought => Icons.shopping_bag_outlined,
                      _ => Icons.gavel,
                    },
                    title: switch (_view) {
                      AuctionView.bought => t('Još ništa nisi kupio'),
                      AuctionView.myBids => t('Još nisi dao nijednu ponudu'),
                      AuctionView.mine ||
                      AuctionView.items => t('Nemaš svojih aukcija'),
                      AuctionView.lives => t('Još nisi bio uživo'),
                    },
                    message: switch (_view) {
                      AuctionView.bought => t(
                        'Ovdje su tvoje kupnje i pobjede — odabereš dostavu i pratiš paket.',
                      ),
                      AuctionView.myBids => t(
                        'Licitiraj u liveu ili na aukciji — tvoje ponude bit će ovdje.',
                      ),
                      _ => t('Pokreni aukciju ili live i prodaj prvi predmet.'),
                    },
                    action: switch (_view) {
                      AuctionView.myBids || AuctionView.bought =>
                        widget.onBrowse == null
                            ? null
                            : FilledButton.icon(
                                key: const ValueKey('my-empty-browse'),
                                onPressed: widget.onBrowse,
                                icon: const Icon(Icons.explore_outlined),
                                label: Text(t('Istraži')),
                              ),
                      AuctionView.mine ||
                      AuctionView.items => FilledButton.icon(
                        key: const ValueKey('my-empty-auction'),
                        onPressed: () => CreateAuctionScreen.open(context),
                        icon: const Icon(Icons.gavel),
                        label: Text(t('Nova aukcija')),
                      ),
                      AuctionView.lives => FilledButton.icon(
                        key: const ValueKey('my-empty-live'),
                        style: FilledButton.styleFrom(
                          backgroundColor: kLiveRed,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => CreateLiveShowScreen.open(context),
                        icon: const Icon(Icons.videocam),
                        label: Text(t('Kreni uživo')),
                      ),
                    },
                  ),
                )
              else if (_view == AuctionView.bought)
                SliverList.list(
                  children: [
                    for (final d in bought)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: DeliveryCard(
                          key: ValueKey('bought-${d.id}'),
                          delivery: d,
                        ),
                      ),
                    const SizedBox(height: 96),
                  ],
                )
              else if (_view == AuctionView.lives)
                SliverList.list(
                  children: [
                    for (final l in lives)
                      _MyLiveTile(show: l, state: s.liveStateOf(l)),
                    const SizedBox(height: 96),
                  ],
                )
              else
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
                      (context, i) =>
                          AuctionCard(auction: list[i], viewerId: me),
                      childCount: list.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
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
            '🔴  Predmeti se licitiraju jedan za drugim, svaki 20–60 sekundi.\n\n⚡  Ponuda u zadnjih 10 s vraća sat na 10 s.\n\n👆  Povuci gore ili dolje za sljedeći live ili aukciju.',
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
                          a.status.label,
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
        if (d.isListed && !d.isDigital) BrowseItem.item(d),
  ];
}
