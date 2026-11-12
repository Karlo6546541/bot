import '../config/features.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/device.dart';
import '../models/wishlist.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/device_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/item_image.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/trade_actions.dart';
import 'device_detail_screen.dart';

/// Oznaka ugrađene liste "Sviđa mi se" (favoriti).
const kLikesList = 'likes';

/// Predmeti liste (samo oni koji još postoje).
List<Device> wishlistItems(AppState s, AppUser owner, String listId) {
  final ids = listId == kLikesList
      ? owner.favorites.reversed.toList()
      : owner.wishlistById(listId)?.deviceIds ?? const <String>[];
  return [for (final id in ids) ?s.deviceById(id)];
}

/// Kartica liste: mozaik do 4 predmeta, simbol, naziv i broj predmeta.
class _ListCover extends StatelessWidget {
  const _ListCover({required this.items, required this.emoji});
  final List<Device> items;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              LoopColors.accent.withValues(alpha: 0.25),
              const Color(0xFF7B2FF7).withValues(alpha: 0.25),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 44)),
      );
    }
    final four = items.take(4).toList();
    return GridView.count(
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      children: [
        for (var i = 0; i < 4; i++)
          i < four.length
              ? (four[i].imagePaths.isEmpty
                    ? ItemIllustration(category: four[i].category, iconSize: 26)
                    : LocalPhoto(
                        path: four[i].imagePaths.first,
                        cacheWidth: 300,
                        fallback: ItemIllustration(
                          category: four[i].category,
                          iconSize: 26,
                        ),
                      ))
              : ColoredBox(color: LoopColors.surfaceHover),
      ],
    );
  }
}

/// Spremi oglas u listu želja: odabir lista (kvačice) i nova lista.
Future<void> showSaveToListSheet(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  if (blockGuest(context)) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: LoopColors.background,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => _SaveSheet(device: device),
  );
}

class _SaveSheet extends ConsumerWidget {
  const _SaveSheet({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final me = s.currentUser;
    if (me == null) return const SizedBox.shrink();
    final c = ref.read(appProvider.notifier);
    final liked = me.favorites.contains(device.id);
    Future<void> run(Future<void> Function() f) async {
      try {
        await f();
      } on TradeException catch (e) {
        showLoopSnackBar(e.message, error: true);
      }
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              t('Spremi u listu'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            Text(
              device.name,
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: liked,
              onChanged: (_) => run(() async {
                await c.toggleFavorite(device.id);
              }),
              secondary: const _Emoji('❤️'),
              title: Text(t('Sviđa mi se')),
              subtitle: Text(itemsLabel(me.favorites.length)),
            ),
            for (final w in me.wishlists)
              CheckboxListTile(
                key: ValueKey('save-${w.id}'),
                contentPadding: EdgeInsets.zero,
                value: w.deviceIds.contains(device.id),
                onChanged: (_) => run(() async {
                  final added = await c.toggleWishlistItem(w.id, device.id);
                  showLoopSnackBar(
                    added
                        ? t('Spremljeno u "{0}"', [w.name])
                        : t('Uklonjeno iz "{0}"', [w.name]),
                  );
                }),
                secondary: _Emoji(w.emoji),
                title: Text(w.name),
                subtitle: Text(itemsLabel(w.deviceIds.length)),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const ValueKey('new-list'),
              onPressed: () async {
                final w = await showNewListDialog(context, ref);
                if (w != null) {
                  await run(() async {
                    await c.toggleWishlistItem(w.id, device.id);
                    showLoopSnackBar(t('Spremljeno u "{0}"', [w.name]));
                  });
                }
              },
              icon: const Icon(Icons.add),
              label: Text(t('Nova lista')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Emoji extends StatelessWidget {
  const _Emoji(this.emoji);
  final String emoji;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: LoopColors.surfaceHover,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(emoji, style: const TextStyle(fontSize: 22)),
  );
}

/// Nova lista (ili preimenovanje): naziv i simbol. Prozor je pri vrhu i ne
/// pomiče se zbog tipkovnice.
Future<Wishlist?> showNewListDialog(
  BuildContext context,
  WidgetRef ref, {
  Wishlist? edit,
}) => showDialog<Wishlist>(
  context: context,
  builder: (ctx) => MediaQuery.removeViewInsets(
    context: ctx,
    removeBottom: true,
    child: _ListDialog(edit: edit),
  ),
);

class _ListDialog extends ConsumerStatefulWidget {
  const _ListDialog({this.edit});
  final Wishlist? edit;

  @override
  ConsumerState<_ListDialog> createState() => _ListDialogState();
}

class _ListDialogState extends ConsumerState<_ListDialog> {
  late final _name = TextEditingController(text: widget.edit?.name ?? '');
  late String _emoji = widget.edit?.emoji ?? Wishlist.emojis.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = ref.read(appProvider.notifier);
    try {
      if (widget.edit == null) {
        final w = await c.createWishlist(_name.text, emoji: _emoji);
        if (mounted) Navigator.pop(context, w);
      } else {
        await c.editWishlist(widget.edit!.id, name: _name.text, emoji: _emoji);
        if (mounted) Navigator.pop(context, widget.edit);
      }
    } on TradeException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    alignment: Alignment.topCenter,
    insetPadding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
    scrollable: true,
    title: Text(widget.edit == null ? t('Nova lista') : t('Uredi listu')),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('list-name'),
            controller: _name,
            maxLength: Wishlist.maxName,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: t('Naziv'),
              hintText: t('npr. Za stan, Pokloni, Gaming'),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in Wishlist.emojis)
                ChoiceChip(
                  label: Text(e, style: const TextStyle(fontSize: 18)),
                  selected: _emoji == e,
                  onSelected: (_) => setState(() => _emoji = e),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('Odustani')),
      ),
      FilledButton(
        key: const ValueKey('list-save'),
        onPressed: _save,
        child: Text(t('Spremi')),
      ),
    ],
  );
}

/// Moje liste želja.
class WishlistsScreen extends ConsumerWidget {
  const WishlistsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const WishlistsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final me = s.currentUser;
    if (me == null) return const Scaffold();
    final cards = <(String, String, String)>[
      (kLikesList, '❤️', t('Sviđa mi se')),
      for (final w in me.wishlists) (w.id, w.emoji, w.name),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(t('Liste želja'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-list'),
        onPressed: () => showNewListDialog(context, ref),
        icon: const Icon(Icons.add),
        label: Text(t('Nova lista')),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 236,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: cards.length,
        itemBuilder: (context, i) {
          final (id, emoji, name) = cards[i];
          final items = wishlistItems(s, me, id);
          return Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('list-$id'),
              onTap: () => WishlistDetailScreen.open(context, me.id, id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ListCover(items: items, emoji: emoji),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$emoji  $name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          itemsLabel(items.length),
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Jedna lista želja (moja ili tuđa, npr. s dijeljene poveznice).
class WishlistDetailScreen extends ConsumerWidget {
  const WishlistDetailScreen({
    super.key,
    required this.ownerId,
    required this.listId,
  });

  final String ownerId;
  final String listId;

  static Future<void> open(
    BuildContext context,
    String ownerId,
    String listId,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WishlistDetailScreen(ownerId: ownerId, listId: listId),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final owner = s.userById(ownerId);
    final list = owner?.wishlistById(listId);
    if (owner == null || (listId != kLikesList && list == null)) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.bookmark_remove_outlined,
          title: t('Lista ne postoji.'),
        ),
      );
    }
    final isMine = owner.id == s.currentUserId;
    final name = list?.name ?? t('Sviđa mi se');
    final emoji = list?.emoji ?? '❤️';
    final items = wishlistItems(s, owner, listId);
    final c = ref.read(appProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text('$emoji  $name', overflow: TextOverflow.ellipsis),
        actions: [
          if (list != null)
            ShareButton(
              url: publicLink(list: '${owner.id}.${list.id}'),
              text: t('Moja lista "{0}" na Subhastu', [list.name]),
              tooltip: t('Podijeli listu'),
            ),
          if (isMine && list != null)
            PopupMenuButton<String>(
              key: const ValueKey('list-menu'),
              onSelected: (v) async {
                if (v == 'edit') {
                  await showNewListDialog(context, ref, edit: list);
                } else if (v == 'delete') {
                  final ok = await confirmDialog(
                    context,
                    title: t('Obrisati listu?'),
                    message: t(
                      'Predmeti ostaju na prodaji, briše se samo lista.',
                    ),
                    confirmLabel: t('Obriši'),
                    destructive: true,
                  );
                  if (!ok || !context.mounted) return;
                  await c.deleteWishlist(list.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(t('Uredi listu'))),
                PopupMenuItem(value: 'delete', child: Text(t('Obriši listu'))),
              ],
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                isMine
                    ? itemsLabel(items.length)
                    : t('Lista korisnika {0} · {1} predmeta', [
                        owner.handle,
                        '${items.length}',
                      ]),
                style: TextStyle(color: LoopColors.textSecondary),
              ),
            ),
          ),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.bookmark_border,
                title: t('Lista je prazna'),
                message: t(
                  'Na oglasu ili u objavama dodirni "Spremi" i odaberi ovu listu.',
                ),
              ),
            )
          else
            DeviceGrid(
              devices: items,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemBuilder: (context, d) {
                final mineItem = d.ownerId == s.currentUserId;
                final available = kBuyNowEnabled && d.isForSale && !mineItem;
                return DeviceCard(
                  device: d,
                  actionLabel: available ? t('Kupi odmah') : t('Detalji'),
                  actionIcon: available
                      ? Icons.shopping_bag_outlined
                      : Icons.info_outline,
                  onAction: available
                      ? () => confirmAndBuy(context, ref, d)
                      : () => DeviceDetailScreen.open(context, d),
                  onTap: () => DeviceDetailScreen.open(context, d),
                  sellerView: mineItem,
                  badge: !d.isForSale ? t('Prodano') : null,
                  isFavorite: isMine && listId == kLikesList,
                  onFavorite: !isMine
                      ? null
                      : () => listId == kLikesList
                            ? c.toggleFavorite(d.id)
                            : c.toggleWishlistItem(listId, d.id),
                );
              },
            ),
        ],
      ),
    );
  }
}
