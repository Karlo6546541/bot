import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../widgets/user_avatar.dart';
import 'auctions_screen.dart';
import 'device_detail_screen.dart';
import 'messages_screen.dart';
import '../widgets/device_card.dart';
import '../widgets/trade_actions.dart';

/// Javni profil korisnika kao mini webshop: naziv trgovine, pratitelji,
/// prodaje, pretraga i sortiranje oglasa, aukcije i ocjene.
class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  static Future<void> open(BuildContext context, String userId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PublicProfileScreen(userId: userId),
        ),
      );

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

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  String _query = '';
  _ShopSort _sort = _ShopSort.newest;

  String get userId => widget.userId;

  List<Device> _shopItems(List<Device> all) {
    final q = normalizeSearch(_query);
    final list = all
        .where(
          (d) =>
              q.isEmpty ||
              normalizeSearch(
                '${d.name} ${d.model} ${d.description} ${d.category.label}',
              ).contains(q),
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
    final allListings = state.listingsOf(user.id);
    final listings = _shopItems(allListings);
    final auctions = state.activeAuctions
        .where((a) => a.sellerId == user!.id)
        .toList();
    Widget title(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
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
    final reviews = state.reviewsOf(user.id);
    final blocked = state.isBlocked(user.id);
    final other = user;
    return Scaffold(
      appBar: AppBar(
        title: Text(user.shopTitle, overflow: TextOverflow.ellipsis),
        actions: [
          if (user.username.isNotEmpty)
            ShareButton(
              url: publicLink(shop: user.username),
              text: t('Trgovina {0} na LOOP-u', [user.shopTitle]),
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
                  ProfileHeader(user: user, rating: state.ratingOf(user.id)),
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
                  _ShopRatingCard(
                    sellerId: user.id,
                    sellerLabel: user.shopTitle,
                    canRate:
                        !isMe &&
                        state.currentUser != null &&
                        !state.currentUser!.isGuest,
                  ),
                  if (!isMe && !blocked) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: FollowButton(userId: other.id)),
                        const SizedBox(width: 10),
                        Expanded(
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
          box(title(t('Trgovina ({0})', [allListings.length]))),
          if (allListings.length > 3)
            box(
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('shop-search'),
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
                    child: Chip(
                      avatar: const Icon(Icons.sort, size: 18),
                      label: Text(_sort.label),
                    ),
                  ),
                ],
              ),
            ),
          if (allListings.length > 3) box(const SizedBox(height: 10)),
          if (listings.isEmpty)
            box(
              Text(
                t('Nema predmeta.'),
                style: TextStyle(color: LoopColors.textSecondary),
              ),
            )
          else
            DeviceGrid(
              devices: listings,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemBuilder: (context, d) => DeviceCard(
                device: d,
                actionLabel: isMe ? t('Detalji') : t('Kupi odmah'),
                actionIcon: isMe
                    ? Icons.info_outline
                    : Icons.shopping_bag_outlined,
                onAction: isMe
                    ? () => DeviceDetailScreen.open(context, d)
                    : () => confirmAndBuy(context, ref, d),
                onTap: () => DeviceDetailScreen.open(context, d),
                promoted: user!.isPromoted,
                sellerView: isMe,
                isFavorite: state.isFavorite(d.id),
                onFavorite: isMe ? null : () => toggleFavorite(ref, d),
              ),
            ),
          box(title(t('Aktivne aukcije ({0})', [auctions.length]))),
          if (auctions.isEmpty)
            box(
              Text(
                t('Nema aukcija'),
                style: TextStyle(color: LoopColors.textSecondary),
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
          box(title(t('Ocjene ({0})', [reviews.length]))),
          if (reviews.isEmpty)
            box(
              Text(
                t('Još nema ocjena'),
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
                      for (final (i, r) in reviews.take(20).indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ReviewTile(review: r),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// Zaglavlje profila (javni profil i "Profil" tab).
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.user,
    this.trailing,
    this.rating,
  });

  final AppUser user;
  final Widget? trailing;

  /// Prosjek ocjena (prikazuje se na javnom profilu).
  final Rating? rating;

  @override
  Widget build(BuildContext context) {
    final secondary = TextStyle(color: LoopColors.textSecondary, fontSize: 13);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(user: user, size: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (user.name.isNotEmpty)
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      UserHandle(
                        user: user,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: user.name.isEmpty
                              ? LoopColors.textPrimary
                              : LoopColors.textSecondary,
                          fontSize: user.name.isEmpty ? 20 : 14,
                        ),
                      ),
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
                            Text('📍 ${user.city}', style: secondary),
                          Text(
                            t('Član od {0}', [formatDate(user.createdAt)]),
                            style: secondary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            if (user.bio.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(user.bio, style: const TextStyle(height: 1.4)),
            ],
          ],
        ),
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
    Widget stat(String value, String label, VoidCallback? onTap, Key key) =>
        Expanded(
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Column(
          children: [
            Row(
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
                stat(
                  '$listings',
                  t('oglasa'),
                  null,
                  const ValueKey('stat-listings'),
                ),
              ],
            ),
            if (promoted) ...[const SizedBox(height: 8), const PromotedBadge()],
          ],
        ),
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
