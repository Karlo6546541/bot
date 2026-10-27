import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../widgets/trust_widgets.dart';
import '../models/auction.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/fee.dart';
import '../services/delivery_service.dart';
import '../services/feed_watch_time.dart';
import '../models/delivery.dart';
import '../widgets/photo_viewer.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/auction_widgets.dart';
import '../widgets/category_style.dart';
import '../widgets/countdown.dart';
import '../widgets/feed.dart' show FeedEntry;
import '../widgets/item_image.dart';
import '../widgets/mini_live.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/trade_actions.dart';
import '../widgets/user_avatar.dart';
import 'auction_detail_screen.dart';
import 'deliveries_screen.dart';
import 'device_detail_screen.dart';
import 'live_screens.dart';
import 'public_profile_screen.dart';

enum FeedFeedback { less, hide, seller, settings }

/// Objave preko cijelog ekrana koje se listaju gore/dolje (kao TikTok).
/// Oglas: lajk, ponudi cijenu, podijeli, kupi. Aukcija: licitiraj,
/// zvono, odbrojavanje. Live aukcija: cijela soba uživo.
class SwipeFeedScreen extends ConsumerStatefulWidget {
  const SwipeFeedScreen({
    super.key,
    required this.entries,
    this.initialIndex = 0,
    this.title,
    this.embedded = false,
    this.active = true,
    this.onPage,
    this.onScrollState,
    this.reasonOf,
    this.onWatch,
    this.onDetails,
    this.onFeedback,
    this.endPage,
  });

  final void Function(FeedEntry entry, Duration visibleTime)? onWatch;
  final void Function(FeedEntry entry)? onDetails;
  final void Function(FeedEntry entry, FeedFeedback action)? onFeedback;
  final Widget? endPage;
  final List<FeedEntry> entries;
  final int initialIndex;

  /// Ugrađeno u početnu ("Za tebe"): bez gumba Natrag i bez zadnje
  /// stranice — roditelj sam dodaje objave (beskonačan feed).
  final bool embedded;

  /// Je li feed vidljiv (live se gleda samo tada).
  final bool active;

  /// Prelazak na drugu objavu: s koje ([from]), koliko se gledala i na
  /// koju ([to]) — za učenje ukusa u "Za tebe".
  final void Function(int from, Duration dwell, int to)? onPage;
  final ValueChanged<bool>? onScrollState;

  /// Razlog preporuke ("Jer pratiš @ana") — oznaka na vrhu objave.
  final String? Function(FeedEntry)? reasonOf;

  /// Naslov na vrhu (zadano "Za tebe").
  final String? title;

  static Future<void> open(
    BuildContext context,
    List<FeedEntry> entries,
    int index, {
    String? title,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          SwipeFeedScreen(entries: entries, initialIndex: index, title: title),
    ),
  );

  @override
  ConsumerState<SwipeFeedScreen> createState() => _SwipeFeedScreenState();
}

class _SwipeFeedScreenState extends ConsumerState<SwipeFeedScreen>
    with WidgetsBindingObserver, RouteAware {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  final _watch = FeedWatchTime();
  final _recorded = <String>{};
  Timer? _viewTimer;
  ModalRoute<dynamic>? _route;
  bool _routeVisible = true;
  bool _foreground = true;
  bool _visible = false;
  bool _scrolling = false;
  Timer? _preloadTimer;
  final _preloaded = <String>{};

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _scrolling = true;
      _viewTimer?.cancel();
      _preloadTimer?.cancel();
      _watch.setVisible(false);
      _flushWatch();
      widget.onScrollState?.call(true);
    } else if (notification is ScrollEndNotification) {
      _scrolling = false;
      _watch.setVisible(_visible);
      widget.onScrollState?.call(false);
      if (_visible) {
        _scheduleView();
        _schedulePreload();
      }
    }
    return false;
  }

  void _schedulePreload() {
    _preloadTimer?.cancel();
    if (!_visible || _scrolling) return;
    _preloadTimer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted || !_visible || _scrolling) return;
      final state = ref.read(appProvider);
      for (final entry in widget.entries.skip(_index + 1).take(2)) {
        if (entry.isLive) continue;
        final id =
            entry.deviceId ?? state.auctionById(entry.auctionId!)?.deviceId;
        final d = id == null ? null : state.deviceById(id);
        if (d == null || d.imagePaths.isEmpty) continue;
        final path = d.imagePaths.first;
        if (!_preloaded.add(path)) continue;
        if (_preloaded.length > 12) _preloaded.remove(_preloaded.first);
        final provider = LocalPhoto.providerFor(path, cacheWidth: 1080);
        if (provider != null) {
          unawaited(precacheImage(provider, context, onError: (_, _) {}));
        }
      }
    });
  }

  String _key(FeedEntry e) => e.liveId ?? e.auctionId ?? e.deviceId ?? '';

  void _flushWatch() {
    final dwell = _watch.take();
    if (_index < widget.entries.length && dwell > Duration.zero) {
      widget.onWatch?.call(widget.entries[_index], dwell);
    }
  }

  void _visibility() {
    final visible = widget.active && _routeVisible && _foreground;
    _watch.setVisible(visible && !_scrolling);
    if (!visible) {
      _viewTimer?.cancel();
      _preloadTimer?.cancel();
      if (_visible) _flushWatch();
    } else if (!_visible) {
      _scheduleView();
    }
    _visible = visible;
    if (visible && !_scrolling) _schedulePreload();
  }

  void _scheduleView() {
    _viewTimer?.cancel();
    if (_scrolling || _index >= widget.entries.length) return;
    final entry = widget.entries[_index];
    _viewTimer = Timer(const Duration(seconds: 1), () {
      if (mounted &&
          _visible &&
          _index < widget.entries.length &&
          _key(widget.entries[_index]) == _key(entry)) {
        _seen(_index);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      feedRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) feedRouteObserver.subscribe(this, route);
    }
    _routeVisible = route?.isCurrent ?? true;
    _visibility();
  }

  @override
  void didUpdateWidget(covariant SwipeFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldEntry = _index < oldWidget.entries.length
        ? oldWidget.entries[_index]
        : null;
    final newEntry = _index < widget.entries.length
        ? widget.entries[_index]
        : null;
    if ((oldEntry == null ? null : _key(oldEntry)) !=
        (newEntry == null ? null : _key(newEntry))) {
      final dwell = _watch.take();
      if (oldEntry != null && dwell > Duration.zero) {
        oldWidget.onWatch?.call(oldEntry, dwell);
      }
    }
    _visibility();
    if (_visible) _scheduleView();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
    _visibility();
  }

  @override
  void didPushNext() {
    setState(() => _routeVisible = false);
    _visibility();
  }

  @override
  void didPopNext() {
    setState(() => _routeVisible = true);
    _visibility();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    _watch.setVisible(false);
    _flushWatch();
    _viewTimer?.cancel();
    _preloadTimer?.cancel();
    feedRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  void _seen(int i) {
    if (i >= widget.entries.length) return;
    final e = widget.entries[i];
    if (e.isLive || !_recorded.add(_key(e))) return;
    final state = ref.read(appProvider);
    final id = e.deviceId ?? state.auctionById(e.auctionId!)?.deviceId;
    if (id != null) ref.read(appProvider.notifier).recordView(id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final entries = widget.entries;
    final embedded = widget.embedded;
    final reason = _index < entries.length
        ? widget.reasonOf?.call(entries[_index])
        : null;
    // Izlazak dok se gleda live: live se gleda dalje u malom prozoru.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop || _index >= entries.length) return;
        final e = entries[_index];
        if (e.isLive) ref.read(miniLiveProvider.notifier).show(e.liveId!);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          // Na širokom ekranu objava ima oblik mobitela.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: PageView.builder(
                    key: const ValueKey('swipe-feed'),
                    scrollBehavior: const AnyDeviceDragBehavior(),
                    controller: _pages,
                    scrollDirection: Axis.vertical,
                    itemCount:
                        entries.length +
                        (widget.endPage != null || !embedded ? 1 : 0),
                    onPageChanged: (i) {
                      final dwell = _watch.take();
                      if (_index < entries.length && dwell > Duration.zero) {
                        widget.onWatch?.call(entries[_index], dwell);
                      }
                      final from = _index;
                      setState(() => _index = i);
                      widget.onPage?.call(from, dwell, i);
                      if (_visible) _scheduleView();
                    },
                    itemBuilder: (context, i) {
                      if (i == entries.length) {
                        return widget.endPage ??
                            _EndPage(onBack: () => Navigator.pop(context));
                      }
                      final e = entries[i];
                      if (e.isLive) {
                        return LiveRoomView(
                          key: ValueKey('feed-live-${e.liveId}'),
                          showId: e.liveId!,
                          active: i == _index && _visible,
                        );
                      }
                      return RepaintBoundary(
                        key: ValueKey('post-${_key(e)}'),
                        child: _PostPage(
                          entry: e,
                          state: state,
                          onDetails: () => widget.onDetails?.call(e),
                        ),
                      );
                    },
                  ),
                ),
                // Ugrađeno: oznaka zašto je objava predložena.
                if (embedded &&
                    reason != null &&
                    _index < entries.length &&
                    !entries[_index].isLive)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        key: const ValueKey('feed-reason'),
                        margin: const EdgeInsets.only(
                          top: 10,
                          left: 14,
                          right: 58,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.onFeedback != null && _index < entries.length)
                  Positioned(
                    right: 4,
                    top: entries[_index].isLive ? 62 : 0,
                    child: SafeArea(
                      child: PopupMenuButton<FeedFeedback>(
                        key: const ValueKey('feed-more'),
                        tooltip: t('Uredi preporuke'),
                        icon: const Icon(
                          Icons.more_horiz,
                          color: Colors.white,
                          shadows: _shadow,
                        ),
                        onSelected: (action) =>
                            widget.onFeedback!(entries[_index], action),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: FeedFeedback.less,
                            child: Text(t('Manje ovakvog')),
                          ),
                          PopupMenuItem(
                            value: FeedFeedback.hide,
                            child: Text(t('Sakrij oglas')),
                          ),
                          PopupMenuItem(
                            value: FeedFeedback.seller,
                            enabled: entries[_index].isLive
                                ? state
                                          .liveShowById(entries[_index].liveId!)
                                          ?.hostId !=
                                      null
                                : entries[_index].isAuction
                                ? state
                                          .auctionById(
                                            entries[_index].auctionId!,
                                          )
                                          ?.sellerId !=
                                      null
                                : state
                                          .deviceById(entries[_index].deviceId!)
                                          ?.ownerId !=
                                      null,
                            child: Text(t('Sakrij prodavača')),
                          ),
                          PopupMenuItem(
                            value: FeedFeedback.settings,
                            child: Text(t('Uredi preporuke')),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Gornja traka: natrag, naslov, broj objave (live ima svoju).
                if (!embedded &&
                    (_index >= entries.length || !entries[_index].isLive))
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: t('Natrag'),
                            color: Colors.white,
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Text(
                              widget.title ?? t('Za tebe'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                shadows: _shadow,
                              ),
                            ),
                          ),
                          // Isti razmak kao gumb Natrag (naslov ostaje u sredini).
                          const SizedBox(width: 48),
                        ],
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

const _shadow = [Shadow(blurRadius: 8, color: Colors.black87)];

class _EndPage extends StatelessWidget {
  const _EndPage({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🎉', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 8),
        Text(
          t('Pogledao si sve objave'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: onBack, child: Text(t('Natrag'))),
      ],
    ),
  );
}

/// Predmet koji sam upravo kupio (umjesto "Oglas više nije dostupan").
class _BoughtPage extends StatelessWidget {
  const _BoughtPage({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('post-bought'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ItemThumb(device: device, size: 160),
            ),
            const SizedBox(height: 16),
            Text(
              t('Kupljeno! 🎉'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              device.name,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => DeliveriesScreen.open(context),
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(t('Prati dostavu')),
            ),
            const SizedBox(height: 8),
            Text(
              t('Povuci gore za sljedeće'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Jedna objava: slika preko cijelog ekrana, a dolje opis (lijevo) i
/// stupac akcija (desno) jedan pokraj drugoga — nikad se ne preklapaju.
class _PostPage extends ConsumerStatefulWidget {
  const _PostPage({
    required this.entry,
    required this.state,
    this.onDetails,
  });
  final VoidCallback? onDetails;
  final FeedEntry entry;
  final AppState state;

  @override
  ConsumerState<_PostPage> createState() => _PostPageState();
}

class _PostPageState extends ConsumerState<_PostPage> {
  bool _heart = false;

  Future<void> _doubleTapLike(Device d) async {
    setState(() => _heart = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _heart = false);
    });
    if (!widget.state.isFavorite(d.id)) {
      await toggleFavorite(ref, d, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final e = widget.entry;
    final auction = e.isAuction ? state.auctionById(e.auctionId!) : null;
    final d = state.deviceById(e.deviceId ?? auction?.deviceId ?? '');
    final available =
        d != null && (auction != null ? auction.isActive : d.isForSale);
    if (!available &&
        d != null &&
        auction == null &&
        state.hasPurchased(d.id)) {
      return _BoughtPage(device: d);
    }
    if (!available) {
      return Center(
        child: Text(
          auction != null
              ? t('Aukcija je završila.')
              : t('Oglas više nije dostupan.'),
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    final owner = state.userById(auction?.sellerId ?? d.ownerId);
    final me = state.currentUser;
    final isMine = owner != null && owner.id == me?.id;
    void openDetails() {
      widget.onDetails?.call();
      _showPostDetails(context, ref, d, auction);
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Media(
                key: const ValueKey('post-media'),
                device: d,
                onTap: openDetails,
                onDoubleTap: isMine || auction != null
                    ? null
                    : () => _doubleTapLike(d),
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black38,
                        Colors.transparent,
                        Colors.transparent,
                      ],
                      stops: [0, 0.22, 1],
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Center(
                  child: AnimatedScale(
                    scale: _heart ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.favorite,
                      color: Color(0xFFFF2D55),
                      size: 100,
                      shadows: _shadow,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 48,
                left: 14,
                right: 80,
                child: _CornerBadge(device: d, auction: auction, state: state),
              ),
              Positioned(
                right: 10,
                bottom: 12,
                child: _ActionRail(
                  device: d,
                  auction: auction,
                  state: state,
                  isMine: isMine,
                ),
              ),
            ],
          ),
        ),
        _Info(
          device: d,
          auction: auction,
          state: state,
          isMine: isMine,
          onDetails: openDetails,
        ),
      ],
    );
  }
}

/// Fotografija preko cijelog ekrana: zamućena pozadina + cijela slika, pa
/// i uske ili široke fotografije izgledaju dobro. Bez fotografije —
/// ilustracija kategorije.
class _Media extends StatefulWidget {
  const _Media({
    super.key,
    required this.device,
    required this.onTap,
    this.onDoubleTap,
  });
  final Device device;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_Media> createState() => _MediaState();
}

class _MediaState extends State<_Media> {
  int _photo = 0;

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final c = d.category.color;
    final illustration = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withValues(alpha: 0.95), Colors.black],
        ),
      ),
      child: Center(
        child: Icon(d.category.icon, size: 140, color: Colors.white24),
      ),
    );
    if (d.imagePaths.isEmpty) {
      return GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: illustration,
      );
    }
    final current = _photo.clamp(0, d.imagePaths.length - 1);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF090A0D)),
        ScrollConfiguration(
          behavior: const AnyDeviceDragBehavior(),
          child: PageView.builder(
            key: const ValueKey('post-gallery'),
            allowImplicitScrolling: true,
            itemCount: d.imagePaths.length,
            onPageChanged: (i) => setState(() => _photo = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: widget.onTap,
              onDoubleTap: widget.onDoubleTap,
              child: LocalPhoto(
                path: d.imagePaths[i],
                fit: BoxFit.contain,
                cacheWidth: 1080,
                fallback: illustration,
              ),
            ),
          ),
        ),
        Positioned(
          right: 10,
          top: 56,
          child: SafeArea(
            child: Column(
              children: [
                if (d.imagePaths.length > 1)
                  Container(
                    key: const ValueKey('post-photo-count'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${current + 1}/${d.imagePaths.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                IconButton(
                  key: const ValueKey('post-zoom'),
                  tooltip: t('Povećaj fotografiju'),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.all(6),
                  ),
                  icon: const Icon(
                    Icons.zoom_in,
                    size: 20,
                    color: Color(0xFFDDDEE5),
                  ),
                  onPressed: () =>
                      PhotoViewer.open(context, d.imagePaths, initial: current),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CornerBadge extends StatelessWidget {
  const _CornerBadge({
    required this.device,
    required this.auction,
    required this.state,
  });
  final Device device;
  final Auction? auction;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final a = auction;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (state.isPromotedItem(device))
          _Pill(
            color: const Color(0xFFFFC233),
            child: Text(
              t('Sponzorirano'),
              style: _pillText.copyWith(color: Colors.black87),
            ),
          ),
        if (a != null)
          _Pill(
            color: LoopColors.accent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('🔨 AUKCIJA'), style: _pillText),
                const SizedBox(width: 8),
                AuctionCountdown(
                  endsAt: a.endsAt,
                  showIcon: false,
                  style: _pillText,
                ),
              ],
            ),
          )
        else if (device.hasDiscount)
          _Pill(
            color: const Color(0xFFFF2D55),
            child: Text(
              t('−{0}% popust', ['${device.discountPercent}']),
              style: _pillText,
            ),
          ),
      ],
    );
  }
}

const _pillText = TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.w700,
  fontSize: 11,
);

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(99),
    ),
    child: child,
  );
}

String _shippingLabel(Device d) {
  final methods = DeliveryService.methodsFor(d);
  final shipped = methods.where((m) => m != DeliveryMethod.pickup).toList()
    ..sort((a, b) => a.cost.compareTo(b.cost));
  if (shipped.isEmpty) return t('Osobno preuzimanje');
  if (shipped.first == DeliveryMethod.digital) return t('Digitalna dostava');
  return t('Dostava od {0}', [formatCredits(shipped.first.cost)]);
}

/// Opis objave: trgovina (+ Prati), naziv, opis, cijena i glavni gumb.
class _Info extends ConsumerWidget {
  const _Info({
    required this.device,
    required this.auction,
    required this.state,
    required this.isMine,
    required this.onDetails,
  });
  final Device device;
  final Auction? auction;
  final AppState state;
  final bool isMine;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = device;
    final a = auction;
    final owner = state.userById(a?.sellerId ?? d.ownerId);
    final meId = state.currentUserId;
    final leading = a != null && a.highestBid?.userId == meId;
    final price = buyTotal(state.priceForMe(d));

    Widget primary;
    if (isMine) {
      primary = _MainButton(
        icon: Icons.info_outline,
        label: a != null ? t('Moja aukcija') : t('Moj oglas'),
        onTap: onDetails,
        outlined: true,
      );
    } else if (a != null) {
      primary = _MainButton(
        key: const ValueKey('post-bid'),
        icon: leading ? Icons.emoji_events_outlined : Icons.gavel,
        label: leading
            ? t('Vodiš · automatska ponuda')
            : t('Licitiraj · od {0}', [formatCredits(a.minNextBid)]),
        onTap: () => showBidSheet(context, ref, a.id),
        color: LoopColors.accent,
      );
    } else {
      primary = _MainButton(
        key: const ValueKey('post-buy'),
        icon: d.isDigital
            ? Icons.download_for_offline_outlined
            : Icons.shopping_bag_outlined,
        label: d.isDigital && state.hasPurchased(d.id)
            ? t('Preuzmi')
            : t('Kupi odmah'),
        onTap: () => confirmAndBuy(context, ref, d),
        color: LoopColors.buyNow,
      );
    }

    final rating = owner == null ? null : state.ratingOf(owner.id);
    return DecoratedBox(
      key: const ValueKey('post-info-panel'),
      decoration: const BoxDecoration(
        color: Color(0xFF131419),
        border: Border(top: BorderSide(color: Color(0xFF25262D))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (owner != null) ...[
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => PublicProfileScreen.open(context, owner.id),
                      child: UserAvatar(user: owner, size: 26),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            PublicProfileScreen.open(context, owner.id),
                        child: Text(
                          owner.shopTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB3B4BF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (rating != null && rating.count > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '★ ${rating.average.toStringAsFixed(1)}',
                        style: const TextStyle(
                          color: Color(0xFFA1A2AD),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (!isMine && !state.isFollowing(owner.id)) ...[
                      const SizedBox(width: 10),
                      _FollowPill(userId: owner.id, handle: owner.handle),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
              ],
              GestureDetector(
                key: const ValueKey('post-description'),
                behavior: HitTestBehavior.opaque,
                onTap: onDetails,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.model.isEmpty ? d.name : '${d.name} · ${d.model}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFE9E9EF),
                              fontSize: 16,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (d.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              d.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF9B9CA8),
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: a != null
                          ? Text(
                              formatCredits(a.currentPrice),
                              style: const TextStyle(
                                color: Color(0xFFE9E9EF),
                                fontSize: 22,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : PriceTag(
                              device: d,
                              price: isMine ? d.askPrice : price,
                              basePrice: d.shownBasePrice,
                              fontSize: 22,
                              color: const Color(0xFFE9E9EF),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      a != null
                          ? t('{0} ponuda', ['${a.bids.length}'])
                          : d.isDigital
                          ? t('Digitalna dostava')
                          : '${d.condition.label} · ${_shippingLabel(d)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF92939F),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: t('Zaštita kupca'),
                    onPressed: () => BuyerProtectionBadge.explain(context),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    icon: const Icon(
                      Icons.verified_user_outlined,
                      size: 15,
                      color: Color(0xFF75AD91),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('post-details-link'),
                    onPressed: onDetails,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB3B4BF),
                      padding: const EdgeInsets.only(left: 4),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(t('Detalji ›')),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              primary,
            ],
          ),
        ),
      ),
    );
  }
}

class _MainButton extends StatelessWidget {
  const _MainButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.outlined = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: outlined
          ? OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE9E9EF),
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                side: const BorderSide(color: Color(0xFF555661)),
              ),
              child: child,
            )
          : FilledButton(
              onPressed: onTap,
              style: color == null
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: const Color(0xFFF0F0F3),
                      minimumSize: const Size(0, 42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
              child: child,
            ),
    );
  }
}

class _FollowPill extends ConsumerWidget {
  const _FollowPill({required this.userId, required this.handle});
  final String userId;
  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
    color: const Color(0xFF24252D),
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      key: const ValueKey('post-follow'),
      borderRadius: BorderRadius.circular(99),
      onTap: () async {
        if (blockGuest(context)) return;
        await ref.read(appProvider.notifier).toggleFollow(userId);
        showLoopSnackBar(t('Pratiš {0}', [handle]));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          t('Prati'),
          style: const TextStyle(
            color: Color(0xFFCACBD4),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

/// Desni stupac akcija (fiksne širine).
class _ActionRail extends ConsumerWidget {
  const _ActionRail({
    required this.device,
    required this.auction,
    required this.state,
    required this.isMine,
  });
  final Device device;
  final Auction? auction;
  final AppState state;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = device;
    final a = auction;
    final liked = state.isFavorite(d.id);
    final watching = a != null && a.watchers.contains(state.currentUserId);
    void share() => shareLink(
      context,
      publicLink(item: d.id),
      text: a != null
          ? t('Aukcija: {0} — trenutno {1} na Subhastu', [
              d.name,
              formatCredits(a.currentPrice),
            ])
          : t('{0} za {1} na Subhastu', [d.name, formatCredits(d.shownPrice)]),
    );
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (a == null)
            _RailButton(
              key: const ValueKey('post-like'),
              icon: liked ? Icons.favorite : Icons.favorite_border,
              color: liked ? const Color(0xFFFF2D55) : Colors.white,
              label: '${state.likesOf(d.id)}',
              onTap: isMine
                  ? null
                  : () => toggleFavorite(ref, d, context: context),
            )
          else if (!isMine)
            _RailButton(
              key: const ValueKey('post-watch'),
              icon: watching
                  ? Icons.notifications_active
                  : Icons.notifications_none,
              color: watching ? const Color(0xFFFFC233) : Colors.white,
              label: watching ? t('Pratiš') : t('Prati'),
              onTap: () async {
                if (blockGuest(context)) return;
                final on = await ref
                    .read(appProvider.notifier)
                    .toggleWatchAuction(a.id);
                showLoopSnackBar(
                  on
                      ? t('Pratiš aukciju — javit ćemo ti 10 minuta prije kraja.')
                      : t('Više ne pratiš aukciju.'),
                );
              },
            ),
          if (a == null && !isMine && d.isListed)
            _RailButton(
              key: const ValueKey('post-offer'),
              icon: Icons.price_change_outlined,
              label: t('Ponudi'),
              onTap: () => showBargainDialog(context, ref, d),
            ),
          _RailButton(
            key: const ValueKey('post-share'),
            icon: Icons.reply,
            mirror: true,
            label: t('Podijeli'),
            onTap: share,
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.mirror = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    Widget i = Icon(icon, color: color, size: 23);
    if (mirror) i = Transform.flip(flipX: true, child: i);
    return SizedBox(
      height: 54,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            i,
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFCDCED6),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cijeli opis i detalji objave u donjem listu (feed ostaje iza njega).
Future<void> _showPostDetails(
  BuildContext context,
  WidgetRef ref,
  Device d,
  Auction? a,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 520),
  builder: (ctx) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    minChildSize: 0.35,
    maxChildSize: 0.92,
    builder: (ctx, scroll) => Consumer(
      builder: (ctx, ref, _) {
        final state = ref.watch(appProvider);
        final owner = state.userById(a?.sellerId ?? d.ownerId);
        final rating = owner == null ? null : state.ratingOf(owner.id);
        Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(label)),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
        return ListView(
          key: const ValueKey('post-details'),
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              d.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            if (d.model.isNotEmpty)
              Text(d.model, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
            Text(
              d.description.isEmpty
                  ? t('Prodavatelj nije dodao opis.')
                  : d.description,
              style: const TextStyle(fontSize: 15, height: 1.45),
            ),
            const Divider(height: 28),
            row(
              Icons.sell_outlined,
              a != null ? t('Trenutna ponuda') : t('Cijena'),
              formatCredits(a?.currentPrice ?? buyTotal(state.priceForMe(d))),
            ),
            if (a != null)
              row(
                Icons.timer_outlined,
                t('Završava'),
                formatDateTime(a.endsAt),
              ),
            row(Icons.category_outlined, t('Kategorija'), d.category.singular),
            if (!d.isDigital)
              row(Icons.verified_outlined, t('Stanje'), d.condition.label),
            if (d.isDigital && d.file != null)
              row(
                Icons.insert_drive_file_outlined,
                t('Datoteka'),
                '${d.file!.extension.toUpperCase()} · ${d.file!.sizeLabel}',
              ),
            if (d.hasStock)
              row(
                Icons.inventory_2_outlined,
                t('Na zalihi'),
                t('{0} kom', ['${d.quantity}']),
              ),
            if (owner != null)
              row(
                Icons.storefront_outlined,
                t('Trgovina'),
                rating != null && rating.count > 0
                    ? '${owner.shopTitle} · ★ ${rating.average.toStringAsFixed(1)}'
                    : owner.shopTitle,
              ),
            row(
              Icons.schedule,
              t('Objavljeno'),
              formatDate(d.listedAt ?? d.createdAt),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                a != null
                    ? AuctionDetailScreen.open(context, a.id)
                    : DeviceDetailScreen.open(context, d);
              },
              icon: const Icon(Icons.open_in_full),
              label: Text(t('Otvori cijeli oglas')),
            ),
          ],
        );
      },
    ),
  ),
);
