import 'auctions_screen.dart';
import 'categories_screen.dart';
import '../widgets/category_style.dart';
import '../models/device.dart';
import '../config/features.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/market_filter.dart' show normalizeSearch, searchMatches;
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/feed.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/user_avatar.dart';
import 'public_profile_screen.dart';
import 'swipe_feed_screen.dart';

/// Pretraga objava (oglasi i aukcije) i korisničkih računa (trgovina).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.accounts = false});

  /// Otvori odmah karticu "Računi".
  final bool accounts;

  static Future<void> open(BuildContext context, {bool accounts = false}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SearchScreen(accounts: accounts),
        ),
      );

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _c = TextEditingController();
  String _q = '';

  /// Showovi: 'live' | 'soon' | null (sve) i redoslijed po gledateljima.
  String? _showTime;
  int _showSort = 0; // 0 preporučeno, 1 gledatelji ↓, 2 gledatelji ↑

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _set(String q) => setState(() {
    _c.text = q;
    _q = q;
  });

  /// Svaki pojam mora biti početak neke riječi — "nike" ne smije naći
  /// "početnike" (violina, fotoaparat…).
  static bool _matches(String text, List<String> terms) =>
      searchMatches(text, terms);

  List<String> get _terms => normalizeSearch(
    _q.replaceAll('@', ''),
  ).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

  List<FeedEntry> _posts(AppState s) {
    final terms = _terms;
    if (terms.isEmpty) return const [];
    return [
      for (final (show, _) in s.activeLives)
        if (_matches(
          '${show.title} ${show.hostLabel} '
          '${show.lots.map((l) => l.deviceName).join(' ')}',
          terms,
        ))
          FeedEntry.live(show.id),
      for (final a in s.activeAuctions)
        if (a.sellerId != s.currentUserId &&
            !s.isBlocked(a.sellerId) &&
            _matches('${a.deviceName} ${a.sellerLabel}', terms))
          FeedEntry.auction(a.id),
      // Kupi odmah: tuđi predmeti na prodaji (naziv, model, kategorija,
      // opis i prodavač).
      for (final d in s.marketDevices)
        if (kBuyNowEnabled &&
            d.isListed &&
            !s.isBlocked(d.ownerId!) &&
            _matches(
              '${d.name} ${d.model} ${d.category.label} ${d.description} '
              '${s.userById(d.ownerId)?.handle ?? ''}',
              terms,
            ))
          FeedEntry.item(d.id),
    ];
  }

  List<AppUser> _accounts(AppState s) {
    final terms = _terms;
    final list =
        s.users
            .where(
              (u) =>
                  !u.isGuest &&
                  !u.pendingDeletion &&
                  u.username.isNotEmpty &&
                  !s.isBlocked(u.id) &&
                  (terms.isEmpty ||
                      _matches(
                        '${u.username} ${u.name} ${u.shopName} ${u.city ?? ''} ${u.bio}',
                        terms,
                      )),
            )
            .toList()
          ..sort((a, b) => s.followersOf(b.id).compareTo(s.followersOf(a.id)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final posts = _posts(s);
    final accounts = _accounts(s);
    final shows = [
      for (final e in posts)
        if (e.isLive) e,
    ];
    final terms = _q.trim().toLowerCase();
    final categories = [
      for (final c in DeviceCategory.values)
        if (terms.isNotEmpty && c.label.toLowerCase().contains(terms)) c,
    ];
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
        gridDelegate: const BrowseGridDelegate(),
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
    return DefaultTabController(
      length: 5,
      initialIndex: widget.accounts ? 3 : 0,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: TextField(
            key: const ValueKey('global-search'),
            controller: _c,
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
          ),
          bottom: TabBar(
            indicatorColor: LoopColors.textPrimary,
            labelColor: LoopColors.textPrimary,
            unselectedLabelColor: LoopColors.textSecondary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
            tabs: [
              Tab(key: const ValueKey('search-tab-top'), text: t('Top')),
              Tab(text: t('Objave ({0})', ['${posts.length}'])),
              Tab(text: t('Showovi ({0})', ['${shows.length}'])),
              Tab(text: t('Računi ({0})', ['${accounts.length}'])),
              Tab(text: t('Kategorije ({0})', ['${categories.length}'])),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Top: kategorije, live showovi i objave (kao Whatnot).
            _q.trim().isEmpty
                ? _History(onPick: _set)
                : topLives.isEmpty &&
                      topPosts.isEmpty &&
                      categories.isEmpty &&
                      accounts.isEmpty
                ? _EmptyOrLoading(
                    child: EmptyState(
                      icon: Icons.search_off,
                      title: t('Nema rezultata za "{0}"', [_q.trim()]),
                    ),
                  )
                : Builder(
                    builder: (ctx) {
                      final tabs = DefaultTabController.of(ctx);
                      return CustomScrollView(
                        key: const ValueKey('search-top'),
                        slivers: [
                          if (categories.isNotEmpty) ...[
                            section(t('Kategorije'), () => tabs.animateTo(4)),
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: 200,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  itemCount: categories.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 10),
                                  itemBuilder: (_, i) => SizedBox(
                                    width: 150,
                                    child: CategoryStatTile(
                                      stat:
                                          stats[categories[i]] ??
                                          CategoryStat(categories[i]),
                                      onTap: () => CategoryItemsScreen.open(
                                        context,
                                        categories[i],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (topLives.isNotEmpty) ...[
                            section(t('Live showovi'), () => tabs.animateTo(2)),
                            cards(
                              'search-top-lives',
                              topLives.take(4).toList(),
                            ),
                          ],
                          if (accounts.isNotEmpty) ...[
                            section(t('Korisnici'), () => tabs.animateTo(3)),
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: 210,
                                child: ListView.separated(
                                  key: const ValueKey('search-top-users'),
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  itemCount: accounts.take(10).length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 10),
                                  itemBuilder: (_, i) {
                                    final u = accounts[i];
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () => PublicProfileScreen.open(
                                        context,
                                        u.id,
                                      ),
                                      child: Container(
                                        width: 150,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          border: Border.all(
                                            color: LoopColors.textSecondary
                                                .withValues(alpha: 0.5),
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            UserAvatar(user: u, size: 64),
                                            const SizedBox(height: 8),
                                            Text(
                                              u.username.isNotEmpty
                                                  ? u.username
                                                  : u.handle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            Text(
                                              t('{0} pratitelja', [
                                                '${s.followersOf(u.id)}',
                                              ]),
                                              style: TextStyle(
                                                color: LoopColors.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const Spacer(),
                                            if (u.id != s.currentUserId)
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
                            section(t('Objave'), () => tabs.animateTo(1)),
                            cards(
                              'search-top-posts',
                              topPosts.take(6).toList(),
                            ),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: 32)),
                        ],
                      );
                    },
                  ),
            // Objave
            _q.trim().isEmpty
                ? _History(onPick: _set)
                : posts.isEmpty
                ? _EmptyOrLoading(
                    child: EmptyState(
                      icon: Icons.search_off,
                      title: t('Nema objava za "{0}"', [_q.trim()]),
                    ),
                  )
                : postGrid(posts, const ValueKey('search-posts')),
            // Showovi (liveovi)
            _q.trim().isEmpty
                ? _History(onPick: _set)
                : shows.isEmpty
                ? EmptyState(
                    icon: Icons.videocam_off_outlined,
                    title: t('Nema showova za "{0}"', [_q.trim()]),
                  )
                : Builder(
                    builder: (ctx) {
                      final list = [
                        for (final i in topLives)
                          if (_showTime == null ||
                              (_showTime == 'live' &&
                                  (i.live?.isLive ?? false)) ||
                              (_showTime == 'soon' &&
                                  (i.live?.isScheduled ?? false)))
                            i,
                      ];
                      if (_showSort != 0) {
                        list.sort((a, b) {
                          final d = (a.live?.viewers ?? 0).compareTo(
                            b.live?.viewers ?? 0,
                          );
                          return _showSort == 1 ? -d : d;
                        });
                      }
                      Widget chip(
                        String key,
                        String label,
                        bool on,
                        VoidCallback tap,
                      ) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: ValueKey(key),
                          label: Text(label),
                          selected: on,
                          onSelected: (_) => tap(),
                        ),
                      );
                      return CustomScrollView(
                        key: const ValueKey('search-shows'),
                        slivers: [
                          SliverToBoxAdapter(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                              child: Row(
                                children: [
                                  chip(
                                    'shows-live',
                                    t('Uživo'),
                                    _showTime == 'live',
                                    () => setState(
                                      () => _showTime = _showTime == 'live'
                                          ? null
                                          : 'live',
                                    ),
                                  ),
                                  chip(
                                    'shows-soon',
                                    t('Uskoro'),
                                    _showTime == 'soon',
                                    () => setState(
                                      () => _showTime = _showTime == 'soon'
                                          ? null
                                          : 'soon',
                                    ),
                                  ),
                                  chip(
                                    'shows-sort',
                                    _showSort == 2
                                        ? t('Gledatelji ↑')
                                        : t('Gledatelji ↓'),
                                    _showSort != 0,
                                    () => setState(
                                      () => _showSort = (_showSort + 1) % 3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          cards('search-shows-grid', list),
                          const SliverToBoxAdapter(child: SizedBox(height: 32)),
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
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: accounts.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
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
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          [
                            if (u.shopName.isNotEmpty) u.handle,
                            t('{0} pratitelja', ['${s.followersOf(u.id)}']),
                            t('{0} oglasa', ['$listings']),
                            if ((u.city ?? '').isNotEmpty) u.city!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: u.id == s.currentUserId
                            ? null
                            : FollowButton(userId: u.id, compact: true),
                        onTap: () {
                          if (_q.trim().isNotEmpty) {
                            ref.read(appProvider.notifier).addSearch(_q);
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
                    title: t('Nema kategorija za "{0}"', [_q.trim()]),
                  )
                : ListView(
                    key: const ValueKey('search-categories'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final c in categories)
                        ListTile(
                          key: ValueKey('search-category-${c.name}'),
                          leading: CategoryArt(category: c, size: 44),
                          title: Text(
                            c.label,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => CategoryItemsScreen.open(context, c),
                        ),
                    ],
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
