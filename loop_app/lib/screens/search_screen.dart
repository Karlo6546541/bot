import '../config/design_variant.dart';
import '../widgets/reference_order_row.dart';
import 'dart:ui';
import '../widgets/vision_glass.dart';
import 'show_filters.dart';
import 'auctions_screen.dart';
import 'auction_detail_screen.dart';
import 'categories_screen.dart';
import '../widgets/category_style.dart';
import '../models/device.dart';
import '../config/features.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import 'live_screens.dart' show LiveRoomScreen;
import '../services/market_filter.dart' show normalizeSearch;
import '../models/app_user.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/smart_search.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/feed.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/user_avatar.dart';
import 'public_profile_screen.dart';
import 'swipe_feed_screen.dart';
import '../widgets/pill_tabs.dart';

/// Pretraga objava (oglasi i aukcije) i korisničkih računa (trgovina).
/// Stanje pretrage preživljava ponovnu izgradnju rute (npr. povratak u
/// pregledniku): upit i kartica rezultata. Čisti se kad korisnik izričito
/// zatvori pretragu ili otvori novu.
class _SearchSession {
  static String query = '';
  static String tab = 'top';
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    this.accounts = false,
    this.initialQuery = '',
  });
  final String initialQuery;

  /// Otvori odmah karticu "Računi".
  final bool accounts;

  static Future<void> open(
    BuildContext context, {
    bool accounts = false,
    String initialQuery = '',
  }) {
    _SearchSession.query = initialQuery;
    _SearchSession.tab = 'top';
    return _open(context, accounts: accounts, initialQuery: initialQuery);
  }

  static Future<void> _open(
    BuildContext context, {
    bool accounts = false,
    String initialQuery = '',
  }) => kSimpleDesign
      ? Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                SearchScreen(accounts: accounts, initialQuery: initialQuery),
          ),
        )
      : Navigator.of(context).push(
          PageRouteBuilder<void>(
            opaque: false,
            barrierDismissible: false,
            pageBuilder: (_, _, _) => BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: SearchScreen(
                accounts: accounts,
                initialQuery: initialQuery,
              ),
            ),
          ),
        );

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  String _q = '';
  @override
  void initState() {
    super.initState();
    _q = widget.initialQuery.isNotEmpty
        ? widget.initialQuery
        : _SearchSession.query;
    _c.text = _q;
    _igTab = _SearchSession.tab;
  }

  /// Čip vrste (Aukcije / Kupi odmah / Uživo); `null` = sve.
  SearchKind? _kind;

  /// Odabrani filteri na kartici Showovi.
  ShowFilters _filters = const ShowFilters();

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(String q) => setState(() {
    _SearchSession.query = q;
    _c.text = q;
    _q = q;
  });

  SmartQuery get _sq => SmartQuery.parse(_q);

  /// Vrsta koja vrijedi: čip ima prednost pred riječju u upitu.
  SearchKind? get _effectiveKind => _kind ?? _sq.kind;

  List<String> get _terms => _sq.terms;

  List<FeedEntry> _posts(AppState s) {
    final sq = _sq;
    final kind = _effectiveKind;
    if (sq.terms.isEmpty && kind == null && !sq.hasPrice) return const [];
    final now = DateTime.now();
    bool text(String t) => sq.terms.isEmpty || sq.matches(t);
    return [
      // Showovi nemaju cijenu: uz filter cijene ih nema.
      if (!sq.hasPrice && (kind == null || kind == SearchKind.live))
        for (final (show, _) in s.activeLives)
          if (text(
            '${show.title} ${show.hostLabel} '
            '${show.lots.map((l) => l.deviceName).join(' ')}',
          ))
            FeedEntry.live(show.id),
      if (kind == null || kind == SearchKind.auction)
        for (final a in s.activeAuctions)
          if (a.sellerId != s.currentUserId &&
              !s.isBlocked(a.sellerId) &&
              sq.priceOk(a.currentPrice) &&
              text('${a.deviceName} ${a.sellerLabel}'))
            FeedEntry.auction(a.id),
      // Kupi odmah: tuđi predmeti na prodaji (naziv, model, kategorija,
      // opis i prodavač).
      if (kBuyNowEnabled && (kind == null || kind == SearchKind.buyNow))
        for (final d in s.marketDevices)
          if (d.isListed &&
              !s.isBlocked(d.ownerId!) &&
              sq.priceOk(d.priceAt(now)) &&
              text(
                '${d.name} ${d.model} ${d.category.label} '
                '${d.category.singular} ${d.description} '
                '${s.userById(d.ownerId)?.handle ?? ''}',
              ))
            FeedEntry.item(d.id),
    ];
  }

  /// "Misliš li na…": ispravak upita kad nema rezultata.
  String? _didYouMean(AppState s) {
    final terms = _sq.terms;
    if (terms.isEmpty) return null;
    final vocab = <String>[
      for (final c in DeviceCategory.values) ...[c.label, c.singular],
      for (final d in s.marketDevices)
        if (d.isListed) '${d.name} ${d.model}',
      for (final a in s.activeAuctions) a.deviceName,
      for (final (show, _) in s.activeLives) show.title,
    ];
    return suggestQuery(terms, vocab);
  }

  List<AppUser> _accounts(AppState s) {
    final terms = _terms;
    final sq = _sq;
    final list =
        s.users
            .where(
              (u) =>
                  !u.isGuest &&
                  !u.pendingDeletion &&
                  u.username.isNotEmpty &&
                  !s.isBlocked(u.id) &&
                  (terms.isEmpty ||
                      sq.matches(
                        '${u.username} ${u.name} ${u.shopName} ${u.city ?? ''} ${u.bio}',
                      )),
            )
            .toList()
          ..sort((a, b) => s.followersOf(b.id).compareTo(s.followersOf(a.id)));
    return list;
  }

  /// Live-first rezultati: Uživo, Uskoro pa prodavači (s razlogom podudaranja).
  /// Proizvodi samo pomažu relevantnosti — nema kataloga oglasa.
  List<Widget> _liveFirstResults(
    AppState state,
    List<AppUser> accounts,
    List<BrowseItem> items,
    Widget Function(String) heading,
  ) {
    final q = normalizeSearch(_q);
    final liveRows = <Widget>[];
    final soonRows = <Widget>[];
    final auctionRows = <Widget>[];
    final reasons = <String, String>{};
    final hostsLive = <String>{};
    final hostsSoon = <String>{};
    void reason(String id, String text) => reasons.putIfAbsent(id, () => text);
    // Proizvod pronađen u shopu ili aukciji: prvo se prikazuju showovi
    // tog prodavača (uživo / uskoro), tek onda prodavač.
    final productOwners = <String, String>{};
    for (final item in items) {
      if (item.show != null) continue;
      final owner = item.device?.ownerId ?? item.auction?.sellerId;
      final name = item.device?.name ?? item.auction?.deviceName ?? '';
      if (owner != null) productOwners.putIfAbsent(owner, () => name);
    }
    final shown = {
      for (final i in items)
        if (i.show != null) i.show!.id,
    };
    final byProduct = <BrowseItem>[
      if (productOwners.isNotEmpty)
        for (final b in browseItems(state))
          if (b.show != null &&
              !shown.contains(b.show!.id) &&
              productOwners.containsKey(b.show!.hostId))
            b,
    ];
    for (final item in [...items, ...byProduct]) {
      final show = item.show;
      if (show == null) {
        final auction = item.auction;
        if (!kLiveEnabled && auction != null) {
          // Aplikacija samo za aukcije: aukcija je izravan rezultat.
          auctionRows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ReferenceOrderRow(
                key: ValueKey('search-auction-${auction.id}'),
                title: auction.deviceName,
                subtitle:
                    '${formatCredits(auction.currentPrice)} · ${auction.sellerLabel}',
                artwork: BrowseCardMedia(device: item.device),
                onTap: () {
                  ref.read(appProvider.notifier).addSearch(_q);
                  AuctionDetailScreen.open(context, auction.id);
                },
              ),
            ),
          );
        }
        // Predmet u shopu ili aukcija: vodi do prodavača, ne do oglasa.
        final owner = item.device?.ownerId ?? auction?.sellerId;
        final name = item.device?.name ?? auction?.deviceName ?? '';
        if (owner != null && kLiveEnabled) {
          reason(owner, t('Ima u shopu: {0}', [name]));
        }
        continue;
      }
      final live = item.live;
      if (live == null) continue;
      String? lotMatch;
      for (final l in show.lots) {
        if (normalizeSearch(l.deviceName).contains(q)) lotMatch = l.deviceName;
      }
      final why = normalizeSearch(show.title).contains(q)
          ? t('Tema prijenosa: {0}', [show.title])
          : lotMatch != null
          ? t('U prijenosu: {0}', [lotMatch])
          : productOwners[show.hostId] != null
          ? t('Prodaje proizvod: {0}', [productOwners[show.hostId]!])
          : t('Prodavač: {0}', [show.hostLabel]);
      final isLive = live.isLive;
      (isLive ? hostsLive : hostsSoon).add(show.hostId);
      (isLive ? liveRows : soonRows).add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ReferenceOrderRow(
            key: ValueKey('search-live-${show.id}'),
            title: show.title,
            subtitle: isLive
                ? '${t('Uživo')} · $why'
                : '${t('Uskoro')} · ${formatDateTime(show.startsAt)} · $why',
            artwork: BrowseCardMedia(
              device: item.device,
              cover: show.coverPath,
            ),
            onTap: () {
              ref.read(appProvider.notifier).addSearch(_q);
              LiveRoomScreen.open(context, show.id);
            },
          ),
        ),
      );
    }
    final sellerIds = <String>{
      ...hostsLive,
      ...hostsSoon,
      for (final u in accounts) u.id,
      ...reasons.keys,
    };
    String status(String id) => hostsLive.contains(id)
        ? t('Uživo')
        : hostsSoon.contains(id)
        ? t('Uskoro')
        : t('Shop');
    final sellers = [
      for (final id in sellerIds)
        if (state.userById(id) case final u? when !u.isGuest) u,
    ];
    final top = _igTab == 'top';
    final out = <Widget>[
      if (auctionRows.isNotEmpty && (top || _igTab == 'auctions')) ...[
        if (top) heading(t('Aukcije')),
        ...auctionRows,
      ],
      if (liveRows.isNotEmpty && (top || _igTab == 'live')) ...[
        if (top) heading(t('Uživo')),
        ...liveRows,
      ],
      if (soonRows.isNotEmpty && (top || _igTab == 'soon')) ...[
        if (top) heading(t('Uskoro')),
        ...soonRows,
      ],
      if (sellers.isNotEmpty && (top || _igTab == 'accounts')) ...[
        if (top) heading(t('Prodavači')),
        for (final user in sellers.take(10))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ReferenceOrderRow(
              key: ValueKey('reference-shop-${user.id}'),
              title: user.shopTitle,
              subtitle: [
                status(user.id),
                reasons[user.id] ?? t('Shop prodavača'),
                if (user.city != null) user.city!,
              ].join(' · '),
              artwork: UserAvatar(user: user, size: 52),
              onTap: () => PublicProfileScreen.open(context, user.id),
            ),
          ),
      ],
    ];
    return out.isEmpty
        ? [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                t('Nema rezultata'),
                textAlign: TextAlign.center,
                style: TextStyle(color: LoopColors.textSecondary),
              ),
            ),
          ]
        : out;
  }

  /// Kartica rezultata: 'top' | 'accounts' | 'live' | 'soon'.
  String _igTab = 'top';

  /// Pretraga u Instagram stilu: puni zaslon, polje s povratkom, nedavna
  /// pretraživanja i tekstualni tabovi rezultata.
  Widget _referenceBody(AppState state) {
    final posts = _posts(state);
    final accounts = _q.trim().isEmpty ? <AppUser>[] : _accounts(state);
    final entries = {
      for (final entry in posts)
        entry.liveId ?? entry.auctionId ?? entry.deviceId,
    };
    final items = browseItems(state)
        .where(
          (item) => entries.contains(
            item.show?.id ?? item.auction?.id ?? item.device?.id,
          ),
        )
        .toList();
    final hasQuery = _q.trim().isNotEmpty;
    Widget tab(String id, String label) => Expanded(
      child: Semantics(
        button: true,
        selected: _igTab == id,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('search-tab-$id'),
          onTap: () => setState(() {
            _igTab = id;
            _SearchSession.tab = id;
          }),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 2,
                  color: _igTab == id
                      ? LoopColors.textPrimary
                      : LoopColors.textPrimary.withValues(alpha: .08),
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: _igTab == id ? FontWeight.w700 : FontWeight.w500,
                color: _igTab == id
                    ? LoopColors.textPrimary
                    : LoopColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    );
    final history = state.searchHistory.take(8).toList();
    final suggested = [
      for (final u in state.users)
        if (!u.isGuest &&
            u.shopName.trim().isNotEmpty &&
            !state.isBlocked(u.id) &&
            u.id != state.currentUserId)
          u,
    ].take(5).toList();
    return Scaffold(
      backgroundColor: LoopColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('search-back'),
                    tooltip: t('Natrag'),
                    onPressed: () {
                      _SearchSession.query = '';
                      _SearchSession.tab = 'top';
                      Navigator.maybePop(context);
                    },
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        key: const ValueKey('reference-search-input'),
                        controller: _c,
                        focusNode: _focus,
                        autofocus: true,
                        onChanged: (value) => setState(() {
                          _q = value;
                          _SearchSession.query = value;
                        }),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty) {
                            ref.read(appProvider.notifier).addSearch(value);
                          }
                        },
                        style: const TextStyle(fontSize: 16, height: 1.2),
                        decoration: InputDecoration(
                          hintText: t('Traži'),
                          filled: true,
                          fillColor: LoopColors.textPrimary.withValues(
                            alpha: .07,
                          ),
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: _q.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: t('Očisti'),
                                  icon: const Icon(Icons.cancel, size: 18),
                                  onPressed: () => _set(''),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasQuery)
              Row(
                children: [
                  tab('top', t('Top')),
                  tab('accounts', t('Računi')),
                  if (kLiveEnabled) ...[
                    tab('live', t('Uživo')),
                    tab('soon', t('Uskoro')),
                  ] else
                    tab('auctions', t('Aukcije')),
                ],
              ),
            Expanded(
              child: ListView(
                key: const ValueKey('reference-search-results'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                children: [
                  if (!hasQuery) ...[
                    if (history.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(child: heading(t('Nedavno'))),
                          TextButton(
                            key: const ValueKey('search-clear-history'),
                            onPressed: () => ref
                                .read(appProvider.notifier)
                                .clearSearchHistory(),
                            child: Text(t('Očisti sve')),
                          ),
                        ],
                      ),
                      for (final term in history)
                        InkWell(
                          key: ValueKey('search-history-$term'),
                          onTap: () => _set(term),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Icon(Icons.history),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(term)),
                                IconButton(
                                  tooltip: t('Ukloni'),
                                  onPressed: () => ref
                                      .read(appProvider.notifier)
                                      .removeSearch(term),
                                  icon: const Icon(Icons.close, size: 20),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    if (suggested.isNotEmpty) ...[
                      heading(t('Predloženi prodavači')),
                      for (final user in suggested)
                        ReferenceOrderRow(
                          key: ValueKey('reference-shop-${user.id}'),
                          title: user.shopTitle,
                          subtitle: user.handle,
                          artwork: UserAvatar(user: user, size: 52),
                          onTap: () =>
                              PublicProfileScreen.open(context, user.id),
                        ),
                    ],
                  ] else ...[
                    ..._liveFirstResults(state, accounts, items, heading),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    if (kSimpleDesign) return _referenceBody(s);
    final posts = _posts(s);
    final accounts = _accounts(s);
    final shows = [
      for (final e in posts)
        if (e.isLive) e,
    ];
    final sq = _sq;
    final categories = [
      for (final c in DeviceCategory.values)
        if (sq.terms.isNotEmpty && sq.matches('${c.label} ${c.singular}')) c,
    ];
    final empty = sq.isEmpty && _kind == null;
    final mean = (!empty && posts.isEmpty && categories.isEmpty)
        ? _didYouMean(s)
        : null;
    Widget noResults(String title, IconData icon) => _EmptyOrLoading(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          EmptyState(icon: icon, title: title),
          if (mean != null)
            TextButton(
              key: const ValueKey('search-did-you-mean'),
              onPressed: () => _set(mean),
              child: Text(t('Misliš li na "{0}"?', [mean])),
            ),
        ],
      ),
    );
    Widget postGrid(List<FeedEntry> list, Key key) => LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900
            ? 5
            : c.maxWidth >= 600
            ? 4
            : 3;
        return GridView.builder(
          key: key,
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 3 / 4,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) => PostTile(
            entry: list[i],
            state: s,
            onTap: () {
              ref.read(appProvider.notifier).addSearch(_q);
              SwipeFeedScreen.open(context, list, i);
            },
          ),
        );
      },
    );
    // Kartice za odjeljak "Top" (kao Whatnot): iste kartice kao na početnoj.
    final liveIds = {for (final e in shows) e.liveId};
    final postIds = {
      for (final e in posts)
        if (!e.isLive) e.auctionId ?? e.deviceId,
    };
    final browse = browseItems(s);
    final topLives = [
      for (final i in browse)
        if (i.show != null && liveIds.contains(i.show!.id)) i,
    ];
    final topPosts = [
      for (final i in browse)
        if (i.show == null && postIds.contains(i.auction?.id ?? i.device?.id))
          i,
    ];
    final stats = {for (final c in categoryStats(s)) c.category: c};
    Widget section(String title, VoidCallback onAll) => SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Builder(
              builder: (ctx) => TextButton(
                onPressed: () {
                  onAll();
                },
                child: Text('${t('Prikaži sve')} ›'),
              ),
            ),
          ],
        ),
      ),
    );
    Widget cards(String key, List<BrowseItem> list) => SliverPadding(
      key: ValueKey(key),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: BrowseGridDelegate(
          textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
        ),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => AuctionBrowseCard(
            item: list[i],
            viewerId: s.currentUserId ?? '',
            onTap: () {
              ref.read(appProvider.notifier).addSearch(_q);
              SwipeFeedScreen.open(ctx, [for (final x in list) x.entry], i);
            },
          ),
          childCount: list.length,
        ),
      ),
    );
    final input = TextField(
      key: const ValueKey('global-search'),
      controller: _c,
      focusNode: _focus,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: (v) => setState(() => _q = v),
      onSubmitted: (v) => ref.read(appProvider.notifier).addSearch(v),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: LoopColors.surfaceHover,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(99)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(99)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(99)),
          borderSide: BorderSide(color: LoopColors.textSecondary),
        ),
        hintText: t('Traži liveove, aukcije, predmete i račune…'),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _q.isEmpty
            ? null
            : IconButton(
                tooltip: t('Očisti'),
                icon: const Icon(Icons.close),
                onPressed: () => _set(''),
              ),
      ),
    );
    return DefaultTabController(
      length: 5,
      initialIndex: widget.accounts ? 3 : 0,
      child: Scaffold(
        backgroundColor: LoopColors.background.withValues(alpha: .86),
        appBar: AppBar(
          titleSpacing: 0,
          title: empty ? Text(t('Pretraži')) : input,
          bottom: empty
              ? null
              : PillTabBar(
                  // Bez rezanja naziva ("Objav", "Raču"): kapsula se pomiče.
                  scrollable: true,
                  tabs: [
                    Tab(key: const ValueKey('search-tab-top'), text: t('Top')),
                    Tab(text: t('Objave ({0})', ['${posts.length}'])),
                    Tab(text: t('Showovi ({0})', ['${shows.length}'])),
                    Tab(text: t('Računi ({0})', ['${accounts.length}'])),
                    Tab(text: t('Kategorije ({0})', ['${categories.length}'])),
                  ],
                ),
        ),
        body: empty
            ? Align(
                alignment: const Alignment(0, .1),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: VisionGlass(
                      radius: 99,
                      padding: const EdgeInsets.all(8),
                      child: input,
                    ),
                  ),
                ),
              )
            : Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: ListView(
                      key: const ValueKey('search-kinds'),
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      children: [
                        for (final (k, label) in <(SearchKind?, String)>[
                          (null, t('Sve')),
                          (SearchKind.auction, t('Aukcije')),
                          (SearchKind.buyNow, t('Kupi odmah')),
                          (SearchKind.live, t('Uživo')),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: ValueKey('search-kind-${k?.name ?? 'all'}'),
                              label: Text(label),
                              selected: _effectiveKind == k,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => _kind = k),
                            ),
                          ),
                        if (sq.hasPrice)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              key: const ValueKey('search-price-chip'),
                              avatar: const Icon(Icons.euro, size: 16),
                              label: Text(
                                [
                                  if (sq.minPrice != null)
                                    t('od {0}', [formatCredits(sq.minPrice!)]),
                                  if (sq.maxPrice != null)
                                    t('do {0}', [formatCredits(sq.maxPrice!)]),
                                ].join(' '),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Top: kategorije, live showovi i objave (kao Whatnot).
                        empty
                            ? _History(onPick: _set)
                            : topLives.isEmpty &&
                                  topPosts.isEmpty &&
                                  categories.isEmpty &&
                                  accounts.isEmpty
                            ? noResults(
                                t('Nema rezultata za "{0}"', [_q.trim()]),
                                Icons.search_off,
                              )
                            : Builder(
                                builder: (ctx) {
                                  final tabs = DefaultTabController.of(ctx);
                                  return CustomScrollView(
                                    key: const ValueKey('search-top'),
                                    slivers: [
                                      if (categories.isNotEmpty) ...[
                                        section(
                                          t('Kategorije'),
                                          () => tabs.animateTo(4),
                                        ),
                                        SliverPadding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          sliver: SliverList.list(
                                            children: [
                                              for (final c in categories.take(
                                                3,
                                              ))
                                                CategoryRow(
                                                  stat:
                                                      stats[c] ??
                                                      CategoryStat(c),
                                                  onTap: () =>
                                                      CategoryItemsScreen.open(
                                                        context,
                                                        c,
                                                      ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      if (topLives.isNotEmpty) ...[
                                        section(
                                          t('Live showovi'),
                                          () => tabs.animateTo(2),
                                        ),
                                        cards(
                                          'search-top-lives',
                                          topLives.take(4).toList(),
                                        ),
                                      ],
                                      if (accounts.isNotEmpty) ...[
                                        section(
                                          t('Korisnici'),
                                          () => tabs.animateTo(3),
                                        ),
                                        SliverToBoxAdapter(
                                          child: SizedBox(
                                            height: 210,
                                            child: ListView.separated(
                                              key: const ValueKey(
                                                'search-top-users',
                                              ),
                                              scrollDirection: Axis.horizontal,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                  ),
                                              itemCount: accounts
                                                  .take(10)
                                                  .length,
                                              separatorBuilder: (_, _) =>
                                                  const SizedBox(width: 10),
                                              itemBuilder: (_, i) {
                                                final u = accounts[i];
                                                return InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  onTap: () =>
                                                      PublicProfileScreen.open(
                                                        context,
                                                        u.id,
                                                      ),
                                                  child: Container(
                                                    width: 150,
                                                    padding:
                                                        const EdgeInsets.all(
                                                          12,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            18,
                                                          ),
                                                      border: Border.all(
                                                        color: LoopColors
                                                            .textSecondary
                                                            .withValues(
                                                              alpha: 0.5,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Column(
                                                      children: [
                                                        UserAvatar(
                                                          user: u,
                                                          size: 64,
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Text(
                                                          u.username.isNotEmpty
                                                              ? u.username
                                                              : u.handle,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                              ),
                                                        ),
                                                        Text(
                                                          t('{0} pratitelja', [
                                                            '${s.followersOf(u.id)}',
                                                          ]),
                                                          style: TextStyle(
                                                            color: LoopColors
                                                                .textSecondary,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        if (u.id !=
                                                            s.currentUserId)
                                                          FollowButton(
                                                            userId: u.id,
                                                            compact: true,
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (topPosts.isNotEmpty) ...[
                                        section(
                                          t('Objave'),
                                          () => tabs.animateTo(1),
                                        ),
                                        cards(
                                          'search-top-posts',
                                          topPosts.take(6).toList(),
                                        ),
                                      ],
                                      const SliverToBoxAdapter(
                                        child: SizedBox(height: 32),
                                      ),
                                    ],
                                  );
                                },
                              ),
                        // Objave
                        empty
                            ? _History(onPick: _set)
                            : posts.isEmpty
                            ? noResults(
                                t('Nema objava za "{0}"', [_q.trim()]),
                                Icons.search_off,
                              )
                            : postGrid(posts, const ValueKey('search-posts')),
                        // Showovi (liveovi)
                        empty
                            ? _History(onPick: _set)
                            : shows.isEmpty
                            ? EmptyState(
                                icon: Icons.videocam_off_outlined,
                                title: t('Nema showova za "{0}"', [_q.trim()]),
                              )
                            : Builder(
                                builder: (ctx) {
                                  final list = _filters.apply(topLives, s);
                                  return CustomScrollView(
                                    key: const ValueKey('search-shows'),
                                    slivers: [
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            12,
                                            16,
                                            12,
                                          ),
                                          child: Row(
                                            children: [
                                              ActionChip(
                                                key: const ValueKey(
                                                  'shows-filter',
                                                ),
                                                avatar: const Icon(
                                                  Icons.tune,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  _filters.activeCount == 0
                                                      ? t('Filter')
                                                      : '${t('Filter')} (${_filters.activeCount})',
                                                ),
                                                onPressed: () async {
                                                  final r =
                                                      await showShowFilterSheet(
                                                        ctx,
                                                        initial: _filters,
                                                        items: topLives,
                                                        state: s,
                                                      );
                                                  if (r != null) {
                                                    setState(
                                                      () => _filters = r,
                                                    );
                                                  }
                                                },
                                              ),
                                              if (!_filters.isDefault) ...[
                                                const SizedBox(width: 8),
                                                TextButton(
                                                  key: const ValueKey(
                                                    'shows-filter-clear',
                                                  ),
                                                  onPressed: () => setState(
                                                    () => _filters =
                                                        const ShowFilters(),
                                                  ),
                                                  child: Text(t('Očisti')),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                      cards('search-shows-grid', list),
                                      const SliverToBoxAdapter(
                                        child: SizedBox(height: 32),
                                      ),
                                    ],
                                  );
                                },
                              ),
                        // Računi
                        accounts.isEmpty
                            ? _EmptyOrLoading(
                                child: EmptyState(
                                  icon: Icons.person_search_outlined,
                                  title: t('Nema računa za "{0}"', [_q.trim()]),
                                ),
                              )
                            : ListView.separated(
                                key: const ValueKey('search-accounts'),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                itemCount: accounts.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final u = accounts[i];
                                  final listings = s.listingsOf(u.id).length;
                                  return ListTile(
                                    key: ValueKey('account-${u.id}'),
                                    leading: UserAvatar(user: u, size: 44),
                                    title: Text(
                                      u.shopTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      [
                                        if (u.shopName.isNotEmpty) u.handle,
                                        t('{0} pratitelja', [
                                          '${s.followersOf(u.id)}',
                                        ]),
                                        t('{0} oglasa', ['$listings']),
                                        if ((u.city ?? '').isNotEmpty) u.city!,
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: u.id == s.currentUserId
                                        ? null
                                        : FollowButton(
                                            userId: u.id,
                                            compact: true,
                                          ),
                                    onTap: () {
                                      if (_q.trim().isNotEmpty) {
                                        ref
                                            .read(appProvider.notifier)
                                            .addSearch(_q);
                                      }
                                      PublicProfileScreen.open(context, u.id);
                                    },
                                  );
                                },
                              ),
                        // Kategorije
                        categories.isEmpty
                            ? EmptyState(
                                icon: Icons.grid_view_outlined,
                                title: t('Nema kategorija za "{0}"', [
                                  _q.trim(),
                                ]),
                              )
                            : ListView(
                                key: const ValueKey('search-categories'),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                children: [
                                  for (final c in categories)
                                    ListTile(
                                      key: ValueKey(
                                        'search-category-${c.name}',
                                      ),
                                      leading: CategoryArt(
                                        category: c,
                                        size: 44,
                                      ),
                                      title: Text(
                                        c.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () =>
                                          CategoryItemsScreen.open(context, c),
                                    ),
                                ],
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

/// Dok se online podaci još učitavaju, "0 rezultata" bi lagalo —
/// prikaži "Učitavam…".
class _EmptyOrLoading extends ConsumerWidget {
  const _EmptyOrLoading({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    if (sync == null) return child;
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: sync.statusListenable,
      builder: (context, status, _) =>
          status == SyncStatus.connecting || status == SyncStatus.offline
          ? Center(
              key: const ValueKey('search-loading'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(t('Učitavam…')),
                ],
              ),
            )
          : child,
    );
  }
}

/// Nedavne pretrage (dok je polje prazno).
class _History extends ConsumerWidget {
  const _History({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(appProvider.select((s) => s.searchHistory));
    if (history.isEmpty) {
      return EmptyState(
        icon: Icons.search,
        title: t('Pretraži objave i račune'),
        message: t(
          'Upiši naziv predmeta, kategoriju, trgovinu ili @korisnika.',
        ),
      );
    }
    final c = ref.read(appProvider.notifier);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t('Nedavno traženo'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: c.clearSearchHistory,
                child: Text(t('Očisti povijest')),
              ),
            ],
          ),
        ),
        for (final q in history)
          ListTile(
            leading: Icon(Icons.history, color: LoopColors.textSecondary),
            title: Text(q),
            trailing: IconButton(
              tooltip: t('Ukloni'),
              icon: const Icon(Icons.close),
              onPressed: () => c.removeSearch(q),
            ),
            onTap: () => onPick(q),
          ),
      ],
    );
  }
}
