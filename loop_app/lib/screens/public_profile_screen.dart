import '../services/app_location/app_location.dart';
import 'package:flutter/material.dart';
import '../widgets/country_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/trust_widgets.dart';

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
          settings: AppPlace.of(
            'shop',
            ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(appProvider).userById(userId)?.username ??
                '',
          ).settings,
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

/// Dio trgovine koji se prikazuje.
enum _ShopTab { items, auctions, reviews }

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  String _query = '';
  _ShopSort _sort = _ShopSort.newest;
  _ShopTab _tab = _ShopTab.auctions;

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
                  SellerTrustCard(user: user),
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
          // Odabir dijela trgovine.
          box(
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 10),
              child: SegmentedButton<_ShopTab>(
                key: const ValueKey('shop-tabs'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _ShopTab.auctions,
                    icon: const Icon(Icons.gavel, size: 18),
                    label: Text(t('Aukcije ({0})', [auctions.length])),
                  ),
                  ButtonSegment(
                    value: _ShopTab.reviews,
                    icon: const Icon(Icons.star_outline, size: 18),
                    label: Text('${reviews.length}'),
                    tooltip: t('Ocjene'),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (v) => setState(() => _tab = v.first),
              ),
            ),
          ),
          if (_tab == _ShopTab.items) ...[
            if (allListings.isNotEmpty) ...[
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
                  onFavorite: isMe
                      ? null
                      : () => toggleFavorite(ref, d, context: context),
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: kLiveRed,
                    borderRadius: BorderRadius.circular(kRadius),
                    child: ListTile(
                      key: ValueKey('profile-live-${show.id}'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kRadius),
                      ),
                      leading: const Icon(Icons.videocam, color: Colors.white),
                      title: Text(
                        show.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      subtitle: Text(
                        live.isLive
                            ? t('Uživo sada')
                            : formatDateTime(show.startsAt),
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                      ),
                      onTap: () => LiveRoomScreen.open(context, show.id),
                    ),
                  ),
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
  });

  final AppUser user;
  final Widget? trailing;

  /// Prosjek ocjena (prikazuje se na javnom profilu).
  final Rating? rating;

  /// Vlastiti profil: gumbi za promjenu naslovne i profilne slike.
  final bool editable;
  final bool compact;

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
        ? chip('seller-kind-business', t('🏪 Trgovac'), LoopColors.sky)
        : chip('seller-kind-private', t('👤 Fizička osoba'), LoopColors.peach);
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
        elevation: 2,
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: compact ? 132 : 184,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Naslovna slika ima svoj prostor; profilna slika samo
                // prelazi preko donjeg ruba.
                Positioned.fill(
                  bottom: 44,
                  child: cover == null
                      ? gradient
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
                      t('🏪 Trgovac · {0}', [info.name]),
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
                      Text('📍 ${user.city}', style: secondary),
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
