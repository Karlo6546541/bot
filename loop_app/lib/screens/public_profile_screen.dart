import '../config/features.dart';
import '../config/design_variant.dart';
import '../models/auction.dart';
import 'account_screens.dart' show EditProfileScreen;
import 'seller_hub.dart';
import '../services/demo_accounts.dart';
import '../widgets/reference_sheet.dart';
import '../services/app_location/app_location.dart';

import 'package:flutter/material.dart';

import '../widgets/country_widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/trust_widgets.dart';
import '../widgets/live_shop_widgets.dart';
import '../widgets/vision_glass.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/device.dart';
import '../models/review.dart';
import '../services/market_filter.dart' show normalizeSearch;
import '../widgets/shop_widgets.dart';
import 'shop_screens.dart';
import '../widgets/community_widgets.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/user_avatar.dart';
import '../providers/app_state.dart';
import '../widgets/category_style.dart';
import 'add_device_screen.dart';
import 'auctions_screen.dart';
import 'device_detail_screen.dart';
import 'live_screens.dart';
import 'messages_screen.dart';
import '../widgets/trade_actions.dart';

/// Javni profil korisnika kao mini webshop: naziv trgovine, pratitelji,
/// prodaje, pretraga i sortiranje oglasa, aukcije i ocjene.
class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  static Future<void> open(BuildContext context, String userId) {
    final user = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(appProvider).userById(userId);
    final settings = AppPlace.of('shop', user?.username ?? '').settings;
    if (kSimpleDesign) {
      return openScreen<void>(
        context,
        title: user?.shopTitle ?? 'Shop',
        settings: settings,
        scaffoldContent: true,
        builder: (_) => PublicProfileScreen(userId: userId),
      );
    }
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => PublicProfileScreen(userId: userId),
      ),
    );
  }

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

/// Redoslijed oglasa u trgovini.
enum _ShopSort {
  newest('Najnovije'),
  priceAsc('Cijena: niža prvo'),
  priceDesc('Cijena: viša prvo'),
  discount('Najveći popust');

  const _ShopSort(this._label);
  final String _label;
  String get label => t(_label);
}

/// Dio trgovine koji se prikazuje.
enum _ShopTab { items, lives, auctions, reviews }

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  String _query = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  _ShopSort _sort = _ShopSort.newest;
  _ShopTab _tab = kBuyNowEnabled ? _ShopTab.items : _ShopTab.auctions;

  /// Kategorija iz filtra trgovine (`null` = sve).
  DeviceCategory? _category;

  String get userId => widget.userId;

  List<Device> _shopItems(List<Device> all) {
    final q = normalizeSearch(_query);
    final list = all
        .where(
          (d) =>
              (_category == null || d.category == _category) &&
              (q.isEmpty ||
                  normalizeSearch(
                    '${d.name} ${d.model} ${d.description} ${d.category.label}',
                  ).contains(q)),
        )
        .toList();
    int discount(Device d) => d.hasDiscount ? d.discountPercent : 0;
    list.sort(
      (a, b) => switch (_sort) {
        _ShopSort.newest => (b.listedAt ?? b.createdAt).compareTo(
          a.listedAt ?? a.createdAt,
        ),
        _ShopSort.priceAsc => a.askPrice.compareTo(b.askPrice),
        _ShopSort.priceDesc => b.askPrice.compareTo(a.askPrice),
        _ShopSort.discount => discount(b).compareTo(discount(a)),
      },
    );
    return list;
  }

  bool _bioOpen = false;
  bool _searchOpen = false;

  /// Kompaktan profil: zaglavlje bez kartice, jedan red statistike, jasne
  /// radnje, kartica prijenosa i mreža proizvoda u dva stupca.
  Widget _simpleProfile(
    AppState state,
    AppUser user,
    List<Device> allListings,
    List<Auction> auctions,
    List<Review> reviews,
  ) {
    final viewer = state.currentUserId ?? '';
    final isMe = viewer == user.id;
    final blocked = state.isBlocked(user.id);
    final signedIn = state.currentUser != null && !state.currentUser!.isGuest;
    final demo = isDemoAccount(user.id);
    final rating = state.ratingOf(user.id);
    final lives = state.activeLives.where((e) => e.$1.hostId == user.id);
    final liveNow = lives.where((e) => e.$2.isLive).firstOrNull;
    final upcoming = lives.where((e) => e.$2.isScheduled).firstOrNull;
    final hasShop = allListings.isNotEmpty || isMe;
    final tabs = <_ShopTab>[
      if (hasShop && kBuyNowEnabled) _ShopTab.items,
      if (kLiveEnabled) _ShopTab.lives,
      _ShopTab.reviews,
      if (auctions.isNotEmpty || !kBuyNowEnabled) _ShopTab.auctions,
    ];
    final tab = tabs.contains(_tab) ? _tab : tabs.first;
    final listings = _shopItems(allListings);
    final secondary = TextStyle(color: LoopColors.textSecondary, fontSize: 13);
    final showHandle =
        user.username.isNotEmpty &&
        user.shopTitle.toLowerCase() != '@${user.username}'.toLowerCase();
    final meta = [
      if (user.seller != null)
        user.isTrader ? t('Trgovac') : t('Privatni prodavač'),
      if ((user.city ?? '').isNotEmpty) user.city!,
    ].join(' · ');
    Widget tabButton(_ShopTab id, String label) => Expanded(
      child: Semantics(
        button: true,
        selected: tab == id,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('shop-tab-${id.name}'),
          onTap: () => setState(() => _tab = id),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 2,
                  color: tab == id
                      ? LoopColors.textPrimary
                      : LoopColors.textPrimary.withValues(alpha: .08),
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: tab == id ? FontWeight.w700 : FontWeight.w500,
                color: tab == id
                    ? LoopColors.textPrimary
                    : LoopColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
    Widget box(Widget child) => SliverToBoxAdapter(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
        ),
      ),
    );
    final bioLong =
        user.bio.length > 90 || '\n'.allMatches(user.bio).isNotEmpty;
    final ratingText = rating.count == 0
        ? t('Nema recenzija')
        : '★ ${rating.average.toStringAsFixed(1)} (${rating.count})';
    final stats = [
      ratingText,
      if (!demo) t('{0} prodaja', ['${state.salesCountOf(user.id)}']),
      t('{0} pratitelja', ['${state.followersOf(user.id)}']),
    ].join('  ·  ');
    final categories = AppState.countByCategory(allListings);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          user.shopTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('profile-menu'),
            tooltip: t('Više'),
            onSelected: (v) async {
              switch (v) {
                case 'about':
                  await showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: SellerTrustCard(user: user),
                      ),
                    ),
                  );
                case 'share':
                  await shareLink(
                    context,
                    publicLink(shop: user.username),
                    text: t('Trgovina {0} na Subhastu', [user.shopTitle]),
                  );
                case 'report':
                  await showReportSheet(
                    context,
                    ref,
                    targetType: 'user',
                    targetId: user.id,
                    targetLabel: user.handle,
                  );
                case 'block':
                  final now = await ref
                      .read(appProvider.notifier)
                      .toggleBlock(user.id);
                  showLoopSnackBar(
                    now
                        ? t('{0} je blokiran — ne vidiš njegove oglase.', [
                            user.handle,
                          ])
                        : t('{0} je odblokiran.', [user.handle]),
                  );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'about', child: Text(t('O prodavatelju'))),
              if (user.username.isNotEmpty)
                PopupMenuItem(
                  value: 'share',
                  child: Text(t('Podijeli profil')),
                ),
              if (!isMe && signedIn) ...[
                PopupMenuItem(
                  value: 'report',
                  child: Text(t('Prijavi korisnika')),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Text(blocked ? t('Odblokiraj') : t('Blokiraj')),
                ),
              ],
            ],
          ),
        ],
      ),
      body: CustomScrollView(
        key: const ValueKey('profile-scroll'),
        slivers: [
          box(
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  UserAvatar(user: user, size: 64),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.shopTitle,
                          key: const ValueKey('profile-name'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (showHandle)
                          Text(
                            user.handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: secondary,
                          ),
                        if (meta.isNotEmpty)
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: secondary,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (user.bio.isNotEmpty)
            box(
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: InkWell(
                  key: const ValueKey('profile-bio'),
                  onTap: bioLong
                      ? () => setState(() => _bioOpen = !_bioOpen)
                      : null,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: user.bio),
                        if (bioLong)
                          TextSpan(
                            text: _bioOpen
                                ? '  ${t('Manje')}'
                                : '  ${t('Više')}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                    maxLines: _bioOpen ? null : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                ),
              ),
            ),
          box(
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    stats,
                    key: const ValueKey('profile-stats'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (demo) Text(t('Demo račun'), style: secondary),
                ],
              ),
            ),
          ),
          box(
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: isMe
                  ? Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: FilledButton(
                            key: const ValueKey('profile-edit'),
                            onPressed: () => EditProfileScreen.open(context),
                            child: Text(t('Uredi profil')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            key: const ValueKey('profile-sell'),
                            onPressed: () => SellerHubScreen.open(context),
                            child: Text(t('Prodaj')),
                          ),
                        ),
                      ],
                    )
                  : blocked
                  ? const SizedBox.shrink()
                  : Row(
                      children: [
                        Expanded(flex: 3, child: FollowButton(userId: user.id)),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            key: const ValueKey('profile-message'),
                            onPressed: () => ChatScreen.open(context, user.id),
                            child: Text(t('Poruka')),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (liveNow != null)
            box(
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  key: ValueKey('profile-live-${liveNow.$1.id}'),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: LoopColors.textPrimary.withValues(alpha: .05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: BrowseCardMedia(
                            device: state.deviceById(
                              liveNow.$2.lots.firstOrNull?.lot.deviceId ?? '',
                            ),
                            cover: liveNow.$1.coverPath,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '● ${t('UŽIVO')}',
                              style: TextStyle(
                                color: LoopColors.live,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              liveNow.$1.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: FilledButton(
                          key: const ValueKey('profile-watch-live'),
                          style: FilledButton.styleFrom(
                            backgroundColor: LoopColors.live,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: () =>
                              LiveRoomScreen.open(context, liveNow.$1.id),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(t('Gledaj uživo')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (upcoming != null)
            box(
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  key: ValueKey('profile-live-${upcoming.$1.id}'),
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            LiveRoomScreen.open(context, upcoming.$1.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${t('Uskoro')} · ${formatDateTime(upcoming.$1.startsAt)}',
                                style: secondary,
                              ),
                              Text(
                                upcoming.$1.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!isMe)
                      OutlinedButton(
                        key: const ValueKey('profile-remind'),
                        onPressed: () => remindMe(context, ref, upcoming.$1.id),
                        child: Text(t('Podsjeti me')),
                      ),
                  ],
                ),
              ),
            ),
          if (!isMe && allListings.isNotEmpty)
            box(
              InkWell(
                key: const ValueKey('shop-terms'),
                onTap: () => BuyerProtectionBadge.explain(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t('Dostava i zaštita kupca'),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          box(
            Row(
              key: const ValueKey('shop-tabs'),
              children: [
                for (final id in tabs)
                  tabButton(id, switch (id) {
                    _ShopTab.items => t('Shop ({0})', [
                      '${allListings.length}',
                    ]),
                    _ShopTab.lives => t('Lajvovi'),
                    _ShopTab.reviews =>
                      reviews.isEmpty
                          ? t('Ocjene')
                          : t('Ocjene ({0})', ['${reviews.length}']),
                    _ShopTab.auctions => t('Aukcije ({0})', [
                      '${auctions.length}',
                    ]),
                  }),
              ],
            ),
          ),
          if (tab == _ShopTab.items) ...[
            if (allListings.isNotEmpty)
              box(
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      if (_searchOpen)
                        Expanded(
                          child: TextField(
                            key: const ValueKey('shop-search'),
                            controller: _search,
                            autofocus: true,
                            onChanged: (v) => setState(() => _query = v),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: t('Pretraži shop'),
                              prefixIcon: const Icon(Icons.search, size: 20),
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      IconButton(
                        key: const ValueKey('shop-search-toggle'),
                        tooltip: t('Pretraži shop'),
                        onPressed: () => setState(() {
                          _searchOpen = !_searchOpen;
                          if (!_searchOpen) {
                            _query = '';
                            _search.clear();
                          }
                        }),
                        icon: Icon(_searchOpen ? Icons.close : Icons.search),
                      ),
                      IconButton(
                        key: const ValueKey('shop-filters'),
                        tooltip: t('Filteri'),
                        onPressed: () => _shopFilters(categories),
                        icon: Badge(
                          isLabelVisible: _category != null,
                          smallSize: 8,
                          child: const Icon(Icons.tune),
                        ),
                      ),
                      if (isMe)
                        IconButton(
                          key: const ValueKey('shop-add'),
                          tooltip: t('Dodaj predmet u trgovinu'),
                          onPressed: () => AddDeviceScreen.open(context),
                          icon: const Icon(Icons.add),
                        ),
                    ],
                  ),
                ),
              ),
            if (listings.isEmpty)
              box(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    allListings.isEmpty
                        ? (isMe
                              ? t('Dodaj prvi predmet u svoj shop.')
                              : t('Shop još nema proizvoda.'))
                        : t('Nema predmeta za odabrani filtar.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ),
              )
            else
              SliverLayoutBuilder(
                builder: (context, c) {
                  final width = c.crossAxisExtent.clamp(0.0, 720.0);
                  final cols = width >= 560 ? 3 : 2;
                  final pad = (c.crossAxisExtent - width) / 2 + 16;
                  final cell = (width - 32 - (cols - 1) * 12) / cols;
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                    sliver: SliverGrid(
                      key: const ValueKey('shop-grid'),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 12,
                        mainAxisExtent: cell * 5 / 4 + 58 * scale.clamp(1, 2),
                      ),
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final d = listings[i];
                        return _ShopGridCard(
                          key: ValueKey('shop-item-${d.id}'),
                          device: d,
                          price: state.priceForMe(d),
                          onTap: () => DeviceDetailScreen.open(context, d),
                        );
                      }, childCount: listings.length),
                    ),
                  );
                },
              ),
          ],
          if (tab == _ShopTab.lives) ...[
            if (lives.isEmpty)
              box(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    t('Trenutno nema aktivnih ni najavljenih prijenosa.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ),
              )
            else
              for (final (show, live) in lives)
                box(
                  Row(
                    key: ValueKey('profile-live-row-${show.id}'),
                    children: [
                      Expanded(
                        child: LiveShopRow(
                          show: show,
                          subtitle: live.isLive
                              ? t('Uživo sada')
                              : '${t('Uskoro')} · ${formatDateTime(show.startsAt)}',
                          onTap: () => LiveRoomScreen.open(context, show.id),
                        ),
                      ),
                      if (!live.isLive && !isMe)
                        OutlinedButton(
                          onPressed: () => remindMe(context, ref, show.id),
                          child: Text(t('Podsjeti me')),
                        ),
                    ],
                  ),
                ),
          ],
          if (tab == _ShopTab.auctions)
            for (final a in auctions)
              box(
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: IntrinsicHeight(
                    child: AuctionCard(auction: a, viewerId: viewer),
                  ),
                ),
              ),
          if (tab == _ShopTab.reviews) ...[
            box(
              _ShopRatingCard(
                sellerId: user.id,
                sellerLabel: user.shopTitle,
                canRate: !isMe && signedIn,
              ),
            ),
            if (reviews.isEmpty)
              box(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    t('Nema recenzija'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ),
              )
            else
              box(
                Column(
                  children: [
                    for (final (i, r) in reviews.take(30).indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ReviewTile(review: r),
                    ],
                  ],
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  /// Jedan gumb za filtre shopa: sortiranje i (samo kad ima smisla)
  /// kategorije.
  Future<void> _shopFilters(Map<DeviceCategory, int> categories) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('Sortiraj'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final v in _ShopSort.values)
                        ChoiceChip(
                          label: Text(v.label),
                          selected: _sort == v,
                          onSelected: (_) {
                            setState(() => _sort = v);
                            setSheet(() {});
                          },
                        ),
                    ],
                  ),
                  if (categories.length >= 2) ...[
                    const SizedBox(height: 16),
                    Text(
                      t('Kategorija'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(t('Sve')),
                          selected: _category == null,
                          onSelected: (_) {
                            setState(() => _category = null);
                            setSheet(() {});
                          },
                        ),
                        for (final e in categories.entries)
                          ChoiceChip(
                            key: ValueKey('shop-cat-${e.key.name}'),
                            label: Text('${e.key.label} (${e.value})'),
                            selected: _category == e.key,
                            onSelected: (_) {
                              setState(
                                () => _category = _category == e.key
                                    ? null
                                    : e.key,
                              );
                              setSheet(() {});
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(t('Gotovo')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    AppUser? user;
    for (final u in state.users) {
      if (u.id == userId) user = u;
    }
    if (user == null || user.pendingDeletion) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.person_off_outlined,
          title: t('Korisnik ne postoji.'),
        ),
      );
    }
    final viewer = state.currentUserId ?? '';
    final isMe = viewer == user.id;
    final allListings = liveShopProducts(state, user.id);
    final listings = _shopItems(allListings);
    final auctions = state.activeAuctions
        .where((a) => a.sellerId == user!.id)
        .toList();
    Widget box(Widget child) => SliverToBoxAdapter(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
        ),
      ),
    );
    final reviews = state.reviewsOf(user.id);
    final blocked = state.isBlocked(user.id);
    final other = user;
    if (kSimpleDesign) {
      return _simpleProfile(state, user, allListings, auctions, reviews);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(user.shopTitle, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: t('O prodavatelju'),
            icon: const Icon(Icons.info_outline),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (_) => SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SellerTrustCard(user: other),
                ),
              ),
            ),
          ),
          if (user.username.isNotEmpty)
            ShareButton(
              url: publicLink(shop: user.username),
              text: t('Trgovina {0} na Subhastu', [user.shopTitle]),
              tooltip: t('Podijeli trgovinu'),
            ),
          if (!isMe && state.currentUser != null && !state.currentUser!.isGuest)
            PopupMenuButton<String>(
              key: const ValueKey('profile-menu'),
              onSelected: (v) async {
                if (v == 'report') {
                  await showReportSheet(
                    context,
                    ref,
                    targetType: 'user',
                    targetId: other.id,
                    targetLabel: other.handle,
                  );
                } else if (v == 'block') {
                  final now = await ref
                      .read(appProvider.notifier)
                      .toggleBlock(other.id);
                  showLoopSnackBar(
                    now
                        ? t('{0} je blokiran — ne vidiš njegove oglase.', [
                            other.handle,
                          ])
                        : t('{0} je odblokiran.', [other.handle]),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(t('Prijavi korisnika')),
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: ListTile(
                    leading: const Icon(Icons.block),
                    title: Text(blocked ? t('Odblokiraj') : t('Blokiraj')),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          box(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileHeader(
                    user: user,
                    rating: state.ratingOf(user.id),
                    editable: isMe,
                    shopfront: true,
                    compact: kSimpleDesign,
                  ),
                  const SizedBox(height: 10),
                  _ShopStats(
                    userId: user.id,
                    followers: state.followersOf(user.id),
                    following: state.followingListOf(user.id).length,
                    sales: state.salesCountOf(user.id),
                    listings: allListings.length,
                    promoted: user.isPromoted,
                  ),
                  const SizedBox(height: 10),
                  if (!isMe && !blocked) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: FollowButton(userId: other.id),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            key: const ValueKey('profile-message'),
                            onPressed: () => ChatScreen.open(context, other.id),
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: Text(t('Poruka')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Status prijenosa: uživo se ističe, najavljeno je označeno Uskoro.
          for (final (show, live)
              in ref
                  .watch(appProvider)
                  .activeLives
                  .where((e) => e.$1.hostId == widget.userId))
            box(
              live.isLive
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: FilledButton.icon(
                        key: ValueKey('profile-live-${show.id}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: LoopColors.live,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: () => LiveRoomScreen.open(context, show.id),
                        icon: const Icon(Icons.sensors),
                        label: Text(
                          t('Uživo: {0} · Uđi u live', [show.title]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                  : LiveShopRow(
                      key: ValueKey('profile-live-${show.id}'),
                      show: show,
                      subtitle: t('Uskoro · {0}', [
                        formatDateTime(show.startsAt),
                      ]),
                      onTap: () => LiveRoomScreen.open(context, show.id),
                    ),
            ),
          // Odabir dijela trgovine.
          box(
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 10),
              child: Row(
                key: const ValueKey('shop-tabs'),
                children: [
                  for (final (tab, label, tip) in [
                    if (kBuyNowEnabled)
                      (
                        _ShopTab.items,
                        t('Shop ({0})', ['${allListings.length}']),
                        null,
                      ),
                    (
                      _ShopTab.auctions,
                      t('Aukcije ({0})', [auctions.length]),
                      null,
                    ),
                    (
                      _ShopTab.reviews,
                      t('Ocjene ({0})', ['${reviews.length}']),
                      t('Ocjene'),
                    ),
                  ])
                    Expanded(
                      child: Tooltip(
                        message: tip ?? '',
                        excludeFromSemantics: tip == null,
                        child: InkWell(
                          key: ValueKey('shop-tab-${tab.name}'),
                          onTap: () => setState(() => _tab = tab),
                          child: Container(
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: _tab == tab
                                      ? LoopColors.textPrimary
                                      : LoopColors.surfaceHover,
                                  width: _tab == tab ? 2 : 1,
                                ),
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: _tab == tab
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: _tab == tab
                                    ? LoopColors.textPrimary
                                    : LoopColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_tab == _ShopTab.items) ...[
            if (allListings.isNotEmpty && !isMe)
              box(
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton.icon(
                    key: const ValueKey('shop-terms'),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(48, 44),
                    ),
                    onPressed: () => BuyerProtectionBadge.explain(context),
                    icon: const Icon(Icons.verified_user_outlined, size: 18),
                    label: Text(
                      t('Dostava i zaštita kupca — uvjeti prije kupnje'),
                    ),
                  ),
                ),
              ),
            if (allListings.isNotEmpty) ...[
              box(
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('shop-search'),
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: t('Pretraži trgovinu…'),
                          prefixIcon: const Icon(Icons.search),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<_ShopSort>(
                      tooltip: t('Sortiraj'),
                      initialValue: _sort,
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (_) => [
                        for (final v in _ShopSort.values)
                          PopupMenuItem(value: v, child: Text(v.label)),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.sort),
                      ),
                    ),
                  ],
                ),
              ),
              // Kategorije trgovine: nastaju same iz objavljenih predmeta.
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: SizedBox(
                      height: 52,
                      child: ListView(
                        key: const ValueKey('shop-categories'),
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                t('Sve ({0})', ['${allListings.length}']),
                              ),
                              selected: _category == null,
                              onSelected: (_) =>
                                  setState(() => _category = null),
                            ),
                          ),
                          for (final e
                              in (AppState.countByCategory(
                                  allListings,
                                ).entries.toList()
                                ..sort((a, b) => b.value.compareTo(a.value))))
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                key: ValueKey('shop-cat-${e.key.name}'),
                                avatar: Icon(e.key.icon, size: 16),
                                label: Text('${e.key.label} (${e.value})'),
                                selected: _category == e.key,
                                onSelected: (_) => setState(
                                  () => _category = _category == e.key
                                      ? null
                                      : e.key,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              box(const SizedBox(height: 8)),
            ],
            if (isMe)
              box(
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton.icon(
                    key: const ValueKey('shop-add'),
                    onPressed: () => AddDeviceScreen.open(context),
                    icon: const Icon(Icons.add),
                    label: Text(t('Dodaj predmet u trgovinu')),
                  ),
                ),
              ),
            if (listings.isEmpty)
              box(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    allListings.isEmpty
                        ? t('Trgovina još nema oglasa.')
                        : t('Nema predmeta za odabrani filtar.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: listings.length,
                  itemBuilder: (context, index) {
                    final d = listings[index];
                    return ShopProductRow(
                      key: ValueKey('shop-item-${d.id}'),
                      device: d,
                      price: state.priceForMe(d),
                      onTap: () => DeviceDetailScreen.open(context, d),
                    );
                  },
                ),
              ),
          ],
          if (_tab == _ShopTab.auctions) ...[
            // Live koji traje (ili je zakazan) je prvi.
            for (final (show, live)
                in ref
                    .watch(appProvider)
                    .activeLives
                    .where((e) => e.$1.hostId == widget.userId))
              box(
                LiveShopRow(
                  key: ValueKey('profile-live-${show.id}'),
                  show: show,
                  subtitle: live.isLive
                      ? t('Uživo sada')
                      : formatDateTime(show.startsAt),
                  onTap: () => LiveRoomScreen.open(context, show.id),
                ),
              ),
            if (auctions.isEmpty)
              box(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    t('Nema aukcija'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ),
              )
            else
              for (final a in auctions)
                box(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    // Kartica je rađena za mrežu (popunjava visinu reda).
                    child: IntrinsicHeight(
                      child: AuctionCard(auction: a, viewerId: viewer),
                    ),
                  ),
                ),
          ],
          if (_tab == _ShopTab.reviews) ...[
            box(
              _ShopRatingCard(
                sellerId: user.id,
                sellerLabel: user.shopTitle,
                canRate:
                    !isMe &&
                    state.currentUser != null &&
                    !state.currentUser!.isGuest,
              ),
            ),
            box(const SizedBox(height: 10)),
            if (reviews.isEmpty)
              box(
                Text(
                  t('Još nema ocjena'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: LoopColors.textSecondary),
                ),
              )
            else
              box(
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (final (i, r) in reviews.take(30).indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ReviewTile(review: r),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// Zaglavlje profila / trgovine: naslovna slika, profilna slika, ime,
/// ocjena i opis. Na vlastitom profilu ([editable]) obje se slike mijenjaju
/// dodirom na ikonu kamere.
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({
    super.key,
    required this.user,
    this.trailing,
    this.rating,
    this.editable = false,
    this.compact = false,
    this.shopfront = false,
  });

  final AppUser user;
  final Widget? trailing;

  /// Prosjek ocjena (prikazuje se na javnom profilu).
  final Rating? rating;

  /// Vlastiti profil: gumbi za promjenu naslovne i profilne slike.
  final bool editable;
  final bool compact;
  final bool shopfront;

  Future<void> _photoMenu(
    BuildContext context,
    WidgetRef ref, {
    required bool cover,
  }) async {
    final c = ref.read(appProvider.notifier);
    final has = cover ? user.coverPath != null : user.avatarPath != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: LoopColors.background,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t('Odaberi iz galerije')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t('Uslikaj')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (has)
              ListTile(
                leading: Icon(Icons.delete_outline, color: LoopColors.error),
                title: Text(t('Ukloni sliku')),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    try {
      if (choice == 'remove') {
        await (cover ? c.removeCover() : c.removeAvatar());
        showLoopSnackBar(t('Slika je uklonjena'));
        return;
      }
      final camera = choice == 'camera';
      final ok = await (cover
          ? c.pickCover(camera: camera)
          : c.pickAvatar(camera: camera));
      if (ok) {
        showLoopSnackBar(
          cover
              ? t('Naslovna slika je promijenjena')
              : t('Profilna slika je promijenjena'),
        );
      }
    } catch (e) {
      showLoopSnackBar(t('Slika nije spremljena: {0}', [e]), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(appProvider);
    // Prodavatelj: ima podatke prodavatelja, oglase ili prodaje.
    final sells =
        user.seller != null ||
        user.trader != null ||
        st.listingsOf(user.id).isNotEmpty ||
        st.salesCountOf(user.id) > 0;
    Widget chip(String key, String text, Color color) => Container(
      key: ValueKey(key),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
    final Widget? sellerKind = !sells
        ? null
        : user.isTrader
        ? chip('seller-kind-business', t('Trgovac'), LoopColors.sky)
        : chip('seller-kind-private', t('Fizička osoba'), LoopColors.peach);
    if (shopfront) {
      return VisionGlass(
        blur: false,
        radius: 28,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(user: user, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.shopTitle,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.7,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.handle,
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          ?sellerKind,
                          CountryBadge(
                            key: const ValueKey('profile-country'),
                            code: user.country,
                            withName: true,
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (rating != null && rating!.count > 0)
                            RatingBadge(rating: rating!),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (user.bio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  user.bio,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    final secondary = TextStyle(color: LoopColors.textSecondary, fontSize: 13);
    final cover = user.coverPath;
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LoopColors.accent.withValues(alpha: 0.85),
            LoopColors.accent,
          ],
        ),
      ),
    );
    // Naslovna: prozirna tamna pilula s ikonom i natpisom.
    Widget coverButton(VoidCallback onTap) => Material(
      color: Colors.black.withValues(alpha: 0.38),
      shape: const StadiumBorder(),
      child: InkWell(
        key: const ValueKey('edit-cover'),
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.photo_camera_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 5),
              Text(
                t('Naslovna'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Profilna: mali okrugli gumb u boji s bijelim rubom.
    Widget avatarButton(VoidCallback onTap) => Tooltip(
      message: t('Promijeni profilnu sliku'),
      child: Material(
        color: LoopColors.accent,
        shape: CircleBorder(
          side: BorderSide(color: LoopColors.surface, width: 2.5),
        ),
        elevation: 0,
        child: InkWell(
          key: const ValueKey('edit-avatar'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(
              Icons.photo_camera_rounded,
              color: Colors.white,
              size: 15,
            ),
          ),
        ),
      ),
    );
    return Card(
      color: Colors.transparent,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: cover == null ? 96 : (compact ? 132 : 168),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Naslovna slika ima svoj prostor; profilna slika samo
                // prelazi preko donjeg ruba.
                Positioned.fill(
                  bottom: 44,
                  child: cover == null
                      ? ColoredBox(color: LoopColors.surfaceHover)
                      : LocalPhoto(
                          path: cover,
                          cacheWidth: 1200,
                          fallback: gradient,
                        ),
                ),
                if (editable)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Tooltip(
                      message: t('Promijeni naslovnu sliku'),
                      child: coverButton(
                        () => _photoMenu(context, ref, cover: true),
                      ),
                    ),
                  ),
                Positioned(
                  left: 18,
                  bottom: 0,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: LoopColors.surface,
                            width: 4,
                          ),
                        ),
                        // Bez priča (uklonjene radi jednostavnosti).
                        child: UserAvatar(user: user, size: compact ? 60 : 76),
                      ),
                      if (editable)
                        Positioned(
                          right: -2,
                          bottom: 2,
                          child: avatarButton(
                            () => _photoMenu(context, ref, cover: false),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null)
                  Positioned(right: 16, bottom: 4, child: trailing!),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user.shopName.isNotEmpty)
                  Text(
                    user.shopName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                if (user.name.isNotEmpty)
                  Text(
                    user.name,
                    style: TextStyle(
                      fontSize: user.shopName.isEmpty ? 20 : 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                // Uz ime: vrsta prodavatelja (trgovac ili fizička osoba).
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    UserHandle(
                      user: user,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: user.name.isEmpty && user.shopName.isEmpty
                            ? LoopColors.textPrimary
                            : LoopColors.textSecondary,
                        fontSize: user.name.isEmpty && user.shopName.isEmpty
                            ? 20
                            : 14,
                      ),
                    ),
                    ?sellerKind,
                    CountryBadge(
                      key: const ValueKey('profile-country'),
                      code: user.country,
                      withName: true,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (user.traderInfo case final info?) ...[
                  const SizedBox(height: 6),
                  Container(
                    key: const ValueKey('profile-business'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: LoopColors.sky,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      t('Trgovac · {0}', [info.name]),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                if (rating != null) ...[
                  const SizedBox(height: 4),
                  RatingBadge(rating: rating!),
                ],
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    if ((user.city ?? '').isNotEmpty)
                      Text('${user.city}', style: secondary),
                    Text(
                      t('Član od {0}', [formatDate(user.createdAt)]),
                      style: secondary,
                    ),
                  ],
                ),
                if (user.bio.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(user.bio, style: const TextStyle(height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pratitelji, pratim, prodaje i oglasi (dodir otvara popis).
class _ShopStats extends StatelessWidget {
  const _ShopStats({
    required this.userId,
    required this.followers,
    required this.following,
    required this.sales,
    required this.listings,
    required this.promoted,
  });
  final String userId;
  final int followers;
  final int following;
  final int sales;
  final int listings;
  final bool promoted;

  @override
  Widget build(BuildContext context) {
    // Kao Whatnot: brojevi i nazivi u retku, bez kartice.
    Widget stat(
      String value,
      String label,
      VoidCallback? onTap,
      Key key,
    ) => InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 10,
        children: [
          stat(
            '$followers',
            t('pratitelja'),
            () => FollowListScreen.open(context, userId),
            const ValueKey('stat-followers'),
          ),
          stat(
            '$following',
            t('prati'),
            () => FollowListScreen.open(context, userId, following: true),
            const ValueKey('stat-following'),
          ),
          stat(
            '$sales',
            t('prodaja'),
            () => SalesListScreen.open(context, userId),
            const ValueKey('stat-sales'),
          ),
          stat('$listings', t('oglasa'), null, const ValueKey('stat-listings')),
        ],
      ),
    );
  }
}

/// Ocjena trgovine (prosjek zvjezdica) i gumb "Ocijeni trgovinu".
class _ShopRatingCard extends ConsumerWidget {
  const _ShopRatingCard({
    required this.sellerId,
    required this.sellerLabel,
    required this.canRate,
  });
  final String sellerId;
  final String sellerLabel;
  final bool canRate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final rating = state.ratingOf(sellerId);
    final mine = state.myShopReviewOf(sellerId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 140),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('Ocjena trgovine'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  RatingBadge(rating: rating),
                ],
              ),
            ),
            if (canRate)
              FilledButton.tonalIcon(
                key: const ValueKey('rate-shop'),
                onPressed: () => showShopRatingDialog(
                  context,
                  ref,
                  sellerId: sellerId,
                  sellerLabel: sellerLabel,
                ),
                icon: const Icon(Icons.star_outline),
                label: Text(
                  mine == null
                      ? t('Ocijeni')
                      : t('Tvoja ocjena: {0}★', ['${mine.stars}']),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Kartica proizvoda u mreži shopa: fotografija, kratak naziv i cijena.
class _ShopGridCard extends StatelessWidget {
  const _ShopGridCard({
    super.key,
    required this.device,
    required this.price,
    required this.onTap,
  });
  final Device device;
  final double price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${device.name}, ${formatCredits(price)}',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(child: BrowseCardMedia(device: device)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            device.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          Row(
            children: [
              Text(
                formatCredits(price),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (device.hasDiscount) ...[
                const SizedBox(width: 6),
                Text(
                  '−${device.discountPercent}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: LoopColors.error,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}
