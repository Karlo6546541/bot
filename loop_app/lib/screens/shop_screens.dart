import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/price_offer.dart';
import '../providers/app_providers.dart';
import '../services/community_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../services/market_filter.dart' show normalizeSearch;
import '../widgets/empty_state.dart';
import '../widgets/feed.dart' show ShopCard;
import '../widgets/shop_widgets.dart';
import '../widgets/trade_actions.dart';
import '../widgets/user_avatar.dart';
import 'device_detail_screen.dart';
import 'public_profile_screen.dart';

/// Sve moje ponude cijena: najprije one koje čekaju moj odgovor.
class BargainsScreen extends ConsumerWidget {
  const BargainsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const BargainsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final toAnswer = state.bargainsToAnswer;
    final rest = state.myBargains
        .where((o) => !toAnswer.contains(o))
        .take(50)
        .toList();
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
    Widget tile(PriceOffer o) => Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: () {
          final d = state.deviceById(o.deviceId);
          if (d != null) DeviceDetailScreen.open(context, d);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: BargainTile(offer: o, showItem: true),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t('Ponude cijena'))),
      body: state.myBargains.isEmpty
          ? EmptyState(
              icon: Icons.price_change_outlined,
              title: t('Još nema ponuda'),
              message: t(
                'Na tuđem oglasu dodirni "Ponudi cijenu". Ponude za tvoje oglase pojavit će se ovdje.',
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    if (toAnswer.isNotEmpty) ...[
                      section(t('Čeka tvoj odgovor ({0})', [toAnswer.length])),
                      for (final o in toAnswer) tile(o),
                    ],
                    if (rest.isNotEmpty) ...[
                      section(t('Ostale ponude')),
                      for (final o in rest) tile(o),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

/// Ljestvica prodavatelja po broju prodaja (tjedan, mjesec, ukupno).
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const LeaderboardScreen()));

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  int? _days = 30;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final board = state.leaderboard(days: _days);
    final periods = <(int?, String)>[
      (7, t('Tjedan')),
      (30, t('Mjesec')),
      (null, t('Ukupno')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(t('Top prodavatelji'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final (days, label) in periods)
                    ChoiceChip(
                      label: Text(label),
                      selected: _days == days,
                      onSelected: (_) => setState(() => _days = days),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (board.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: t('Još nema prodaja u ovom razdoblju'),
                    message: t(
                      'Objavi oglas — prva prodaja te stavlja na ljestvicu.',
                    ),
                  ),
                )
              else
                for (final (i, s) in board.indexed)
                  Card(
                    child: ListTile(
                      key: ValueKey('rank-${s.user.id}'),
                      onTap: () => PublicProfileScreen.open(context, s.user.id),
                      leading: SizedBox(
                        width: 72,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: Text(
                                i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}.',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            UserAvatar(user: s.user, size: 36),
                          ],
                        ),
                      ),
                      title: Text(
                        s.user.shopTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        t('{0} prodaja · {1}', [
                          '${s.sales}',
                          formatCredits(s.revenue),
                        ]),
                      ),
                      trailing: s.user.isPromoted
                          ? const PromotedBadge(small: true)
                          : null,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plaćeno isticanje računa (tjedno).
Future<void> showPromoteSheet(BuildContext context, WidgetRef ref) async {
  if (blockGuest(context)) return;
  final weeks = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    backgroundColor: LoopColors.background,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => const _PromoteSheet(),
  );
  if (weeks == null || !context.mounted) return;
  await runWithLoading(
    context,
    () => ref.read(appProvider.notifier).promote(weeks),
    successMessage: t('Račun je istaknut ⭐ — oglasi ti se prikazuju prvi'),
  );
}

class _PromoteSheet extends ConsumerStatefulWidget {
  const _PromoteSheet();

  @override
  ConsumerState<_PromoteSheet> createState() => _PromoteSheetState();
}

class _PromoteSheetState extends ConsumerState<_PromoteSheet> {
  int _weeks = 1;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appProvider.select((s) => s.currentUser));
    final cost = CommunityService.promotionWeekly * _weeks;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('Istakni svoj račun ⭐'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              t(
                'Tvoji oglasi prikazuju se prvi u Marketu (Preporučeno) i na početnoj, s oznakom "Istaknuto". Cijena: {0} tjedno.',
                [formatCredits(CommunityService.promotionWeekly)],
              ),
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            if (user != null && user.isPromoted) ...[
              const SizedBox(height: 8),
              Text(
                t('Istaknut si do {0} — novo razdoblje se nadovezuje.', [
                  formatDateTime(user.promotedUntil!),
                ]),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (var w = 1; w <= CommunityService.maxPromotionWeeks; w++)
                  ChoiceChip(
                    label: Text(
                      w == 1 ? t('1 tjedan') : t('{0} tjedna', ['$w']),
                    ),
                    selected: _weeks == w,
                    onSelected: (_) => setState(() => _weeks = w),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('promote-pay'),
              onPressed: () => Navigator.pop(context, _weeks),
              icon: const Icon(Icons.campaign_outlined),
              label: Text(t('Plati {0}', [formatCredits(cost)])),
            ),
            const SizedBox(height: 6),
            Text(
              t(
                'Plaća se karticom. Istaknuti oglasi označeni su kao "Sponzorirano".',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Naziv mini webshopa.
Future<void> showShopNameDialog(BuildContext context, WidgetRef ref) async {
  final user = ref.read(appProvider).currentUser;
  if (user == null) return;
  final c = TextEditingController(text: user.shopName);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Naziv trgovine')),
      content: TextField(
        key: const ValueKey('shop-name'),
        controller: c,
        autofocus: true,
        maxLength: AppUser.maxShopName,
        decoration: InputDecoration(
          hintText: user.handle,
          helperText: t('Prazno = korisničko ime.'),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t('Odustani')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: Text(t('Spremi')),
        ),
      ],
    ),
  );
  if (name == null || !context.mounted) return;
  await runWithLoading(
    context,
    () => ref.read(appProvider.notifier).setShopName(name),
    successMessage: t('Naziv trgovine je spremljen'),
  );
}

/// Sve trgovine (svaki račun s oglasima je webshop): pretraga i redoslijed.
class ShopsScreen extends ConsumerStatefulWidget {
  const ShopsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ShopsScreen()));

  @override
  ConsumerState<ShopsScreen> createState() => _ShopsScreenState();
}

enum _ShopOrder {
  followers('Najviše pratitelja'),
  rating('Najbolje ocijenjene'),
  sales('Najviše prodaja'),
  listings('Najviše oglasa');

  const _ShopOrder(this._label);
  final String _label;
  String get label => t(_label);
}

class _ShopsScreenState extends ConsumerState<ShopsScreen> {
  String _query = '';
  _ShopOrder _order = _ShopOrder.followers;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final q = normalizeSearch(_query.replaceAll('@', ''));
    final shops =
        state.shops
            .where(
              (u) =>
                  q.isEmpty ||
                  normalizeSearch(
                    '${u.username} ${u.name} ${u.shopName} ${u.city ?? ''}',
                  ).contains(q),
            )
            .toList()
          ..sort((a, b) {
            num key(AppUser u) => switch (_order) {
              _ShopOrder.followers => state.followersOf(u.id),
              _ShopOrder.rating => state.ratingOf(u.id).average,
              _ShopOrder.sales => state.salesCountOf(u.id),
              _ShopOrder.listings => state.listingsOf(u.id).length,
            };
            final p = (b.isPromoted ? 1 : 0) - (a.isPromoted ? 1 : 0);
            return p != 0 ? p : key(b).compareTo(key(a));
          });
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Trgovine')),
        actions: [
          IconButton(
            key: const ValueKey('open-leaderboard'),
            tooltip: t('Top prodavatelji'),
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => LeaderboardScreen.open(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              t(
                'Svaki račun na LOOP-u je webshop: objavi predmet i tvoja trgovina se pojavljuje ovdje.',
              ),
              style: TextStyle(color: LoopColors.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('shops-search'),
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: t('Traži trgovinu ili korisnika…'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<_ShopOrder>(
                  tooltip: t('Sortiraj'),
                  initialValue: _order,
                  onSelected: (v) => setState(() => _order = v),
                  itemBuilder: (_) => [
                    for (final o in _ShopOrder.values)
                      PopupMenuItem(value: o, child: Text(o.label)),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.sort),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: shops.isEmpty
                ? EmptyState(
                    icon: Icons.storefront_outlined,
                    title: t('Nema trgovina'),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          mainAxisExtent: 262,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: shops.length,
                    itemBuilder: (context, i) =>
                        ShopCard(user: shops[i], width: double.infinity),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Pratitelji i računi koje korisnik prati (dvije kartice).
class FollowListScreen extends ConsumerWidget {
  const FollowListScreen({
    super.key,
    required this.userId,
    this.showFollowing = false,
  });

  final String userId;
  final bool showFollowing;

  static Future<void> open(
    BuildContext context,
    String userId, {
    bool following = false,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          FollowListScreen(userId: userId, showFollowing: following),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final user = state.userById(userId);
    final followers = state.followersListOf(userId);
    final following = state.followingListOf(userId);
    Widget list(List<AppUser> users, String empty) => users.isEmpty
        ? EmptyState(icon: Icons.people_outline, title: empty)
        : ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: users.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final u = users[i];
              return ListTile(
                leading: UserAvatar(user: u, size: 40),
                title: Text(
                  u.shopTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  t('{0} · {1} pratitelja', [
                    u.handle,
                    '${state.followersOf(u.id)}',
                  ]),
                ),
                trailing: FollowButton(userId: u.id, compact: true),
                onTap: () => PublicProfileScreen.open(context, u.id),
              );
            },
          );
    return DefaultTabController(
      length: 2,
      initialIndex: showFollowing ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(user?.shopTitle ?? ''),
          bottom: TabBar(
            tabs: [
              Tab(text: t('Pratitelji ({0})', ['${followers.length}'])),
              Tab(text: t('Prati ({0})', ['${following.length}'])),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            list(followers, t('Još nema pratitelja')),
            list(following, t('Još nikoga ne prati')),
          ],
        ),
      ),
    );
  }
}

/// Prodaje trgovine (predmet, datum, cijena).
class SalesListScreen extends ConsumerWidget {
  const SalesListScreen({super.key, required this.userId});
  final String userId;

  static Future<void> open(BuildContext context, String userId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SalesListScreen(userId: userId),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final sales = state.salesOf(userId);
    final user = state.userById(userId);
    return Scaffold(
      appBar: AppBar(title: Text(t('Prodaje: {0}', [user?.shopTitle ?? '']))),
      body: sales.isEmpty
          ? EmptyState(icon: Icons.sell_outlined, title: t('Još nema prodaja'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sales.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = sales[i];
                return ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(s.deviceName),
                  subtitle: Text(
                    t('{0} · kupac {1}', [
                      formatDateTime(s.createdAt),
                      s.buyerLabel,
                    ]),
                  ),
                  trailing: Text(
                    formatCredits(s.price),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                );
              },
            ),
    );
  }
}
