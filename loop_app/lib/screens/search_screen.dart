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
    return DefaultTabController(
      length: 2,
      initialIndex: widget.accounts ? 1 : 0,
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
            tabs: [
              Tab(text: t('Objave ({0})', ['${posts.length}'])),
              Tab(text: t('Računi ({0})', ['${accounts.length}'])),
            ],
          ),
        ),
        body: TabBarView(
          children: [
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
                : LayoutBuilder(
                    builder: (context, c) {
                      final cols = c.maxWidth >= 900
                          ? 5
                          : c.maxWidth >= 600
                          ? 4
                          : 3;
                      return GridView.builder(
                        key: const ValueKey('search-posts'),
                        padding: const EdgeInsets.all(8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                          childAspectRatio: 3 / 4,
                        ),
                        itemCount: posts.length,
                        itemBuilder: (context, i) => PostTile(
                          entry: posts[i],
                          state: s,
                          onTap: () {
                            ref.read(appProvider.notifier).addSearch(_q);
                            SwipeFeedScreen.open(context, posts, i);
                          },
                        ),
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
