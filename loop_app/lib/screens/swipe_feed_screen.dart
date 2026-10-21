import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/fee.dart';
import '../widgets/item_image.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/trade_actions.dart';
import '../widgets/user_avatar.dart';
import '../utils/formatters.dart';
import 'device_detail_screen.dart';
import 'public_profile_screen.dart';

/// Objave preko cijelog ekrana koje se listaju gore/dolje (kao TikTok):
/// prati, ponudi cijenu, lajk, prikazi, podijeli i kupnja.
class SwipeFeedScreen extends ConsumerStatefulWidget {
  const SwipeFeedScreen({
    super.key,
    required this.deviceIds,
    this.initialIndex = 0,
  });

  final List<String> deviceIds;
  final int initialIndex;

  static Future<void> open(
    BuildContext context,
    List<Device> posts,
    int index,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SwipeFeedScreen(
        deviceIds: [for (final d in posts) d.id],
        initialIndex: index,
      ),
    ),
  );

  @override
  ConsumerState<SwipeFeedScreen> createState() => _SwipeFeedScreenState();
}

class _SwipeFeedScreenState extends ConsumerState<SwipeFeedScreen> {
  late final _pages = PageController(initialPage: widget.initialIndex);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _seen(widget.initialIndex),
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _seen(int i) {
    if (i < widget.deviceIds.length) {
      ref.read(appProvider.notifier).recordView(widget.deviceIds[i]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final ids = widget.deviceIds;
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          brightness: Brightness.dark,
          surface: Colors.black,
          onSurface: Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(t('Za tebe')),
          centerTitle: true,
        ),
        body: PageView.builder(
          key: const ValueKey('swipe-feed'),
          controller: _pages,
          scrollDirection: Axis.vertical,
          itemCount: ids.length + 1,
          onPageChanged: _seen,
          itemBuilder: (context, i) {
            if (i == ids.length) {
              return _EndPage(onBack: () => Navigator.pop(context));
            }
            final d = state.deviceById(ids[i]);
            if (d == null || !d.isForSale) {
              return Center(
                child: Text(
                  t('Oglas više nije dostupan.'),
                  style: const TextStyle(color: Colors.white70),
                ),
              );
            }
            return _Post(device: d, state: state);
          },
        ),
      ),
    );
  }
}

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

class _Post extends ConsumerWidget {
  const _Post({required this.device, required this.state});
  final Device device;
  final AppState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = device;
    final owner = state.userById(d.ownerId);
    final me = state.currentUser;
    final isMine = owner != null && owner.id == me?.id;
    final liked = state.isFavorite(d.id);
    final price = state.priceForMe(d);
    const shadow = [Shadow(blurRadius: 8, color: Colors.black87)];
    final photo = d.imagePaths.isEmpty
        ? ItemIllustration(category: d.category, iconSize: 120)
        : LocalPhoto(
            path: d.imagePaths.first,
            fit: BoxFit.contain,
            fallback: ItemIllustration(category: d.category, iconSize: 120),
          );

    Widget action(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      Color color = Colors.white,
      Key? key,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        key: key,
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Column(
          children: [
            Icon(icon, color: color, size: 34, shadows: shadow),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                shadows: shadow,
              ),
            ),
          ],
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onDoubleTap: liked || isMine ? null : () => toggleFavorite(ref, d),
          child: ColoredBox(color: Colors.black, child: photo),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black38, Colors.transparent, Colors.black87],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
        ),
        // Desni stupac akcija.
        Positioned(
          right: 10,
          bottom: 120,
          child: Column(
            children: [
              if (owner != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: SizedBox(
                    width: 52,
                    height: 62,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onTap: () =>
                              PublicProfileScreen.open(context, owner.id),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: UserAvatar(user: owner, size: 48),
                          ),
                        ),
                        if (!isMine && !state.isFollowing(owner.id))
                          Positioned(
                            left: 14,
                            bottom: 0,
                            child: GestureDetector(
                              key: const ValueKey('post-follow'),
                              onTap: () async {
                                if (blockGuest(context)) return;
                                await ref
                                    .read(appProvider.notifier)
                                    .toggleFollow(owner.id);
                                showLoopSnackBar(
                                  t('Pratiš {0}', [owner.handle]),
                                );
                              },
                              child: const CircleAvatar(
                                radius: 12,
                                backgroundColor: Color(0xFFFF2D55),
                                child: Icon(
                                  Icons.add,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              action(
                liked ? Icons.favorite : Icons.favorite_border,
                '${state.likesOf(d.id)}',
                isMine ? null : () => toggleFavorite(ref, d),
                color: liked ? const Color(0xFFFF2D55) : Colors.white,
                key: const ValueKey('post-like'),
              ),
              if (!isMine && d.isListed)
                action(
                  Icons.price_change_outlined,
                  t('Ponudi'),
                  () => showBargainDialog(context, ref, d),
                  key: const ValueKey('post-offer'),
                ),
              action(
                Icons.ios_share,
                t('Podijeli'),
                () => shareLink(
                  context,
                  publicLink(item: d.id),
                  text: t('{0} za {1} na LOOP-u', [
                    d.name,
                    formatCredits(d.shownPrice),
                  ]),
                ),
                key: const ValueKey('post-share'),
              ),
              action(Icons.play_arrow_outlined, '${state.viewsOf(d.id)}', null),
            ],
          ),
        ),
        // Opis i kupnja.
        Positioned(
          left: 14,
          right: 80,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (owner != null)
                GestureDetector(
                  onTap: () => PublicProfileScreen.open(context, owner.id),
                  child: Text(
                    owner.shopName.isNotEmpty
                        ? '${owner.handle} · ${owner.shopName}'
                        : owner.handle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      shadows: shadow,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                '${d.name} · ${d.model}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: shadow,
                ),
              ),
              if (d.description.isNotEmpty)
                Text(
                  d.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    shadows: shadow,
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Flexible(
                    child: PriceTag(
                      device: d,
                      price: isMine ? d.askPrice : buyTotal(price),
                      basePrice: isMine ? null : d.shownBasePrice,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!isMine)
                    FilledButton.icon(
                      key: const ValueKey('post-buy'),
                      onPressed: () => confirmAndBuy(context, ref, d),
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: Text(
                        d.isDigital ? t('Kupi i preuzmi') : t('Kupi'),
                      ),
                    ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                    ),
                    onPressed: () => DeviceDetailScreen.open(context, d),
                    child: Text(t('Detalji')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
