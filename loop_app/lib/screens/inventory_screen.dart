import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../models/loop_transaction.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/live_service.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import 'add_device_screen.dart';
import 'create_auction_screen.dart';
import 'device_detail_screen.dart';
import 'live_screens.dart';

/// Gdje je predmet u inventaru.
enum InventoryState { active, draft }

/// Moji predmeti koji su još moji (bez kupljenih koje nisam ponovno stavio
/// na prodaju), s oznakom: aktivno (Kupi odmah, aukcija, live) ili
/// spremljeno.
List<(Device, InventoryState, String)> inventoryOf(
  AppState s,
  bool Function(String deviceId) inLive,
) {
  final user = s.currentUser;
  if (user == null) return const [];
  final boughtIds = {for (final x in s.myDeliveries) x.deviceId};
  final out = <(Device, InventoryState, String)>[];
  for (final d in s.myDevices) {
    if (d.ownerId != user.id) continue;
    final auction = s.activeAuctionFor(d.id) != null;
    final live = inLive(d.id);
    final active = auction || live || d.isListed;
    final bought = boughtIds.contains(d.id) || s.hasPurchased(d.id);
    if (bought && !active) continue;
    out.add((
      d,
      active ? InventoryState.active : InventoryState.draft,
      auction
          ? t('Na aukciji')
          : live
          ? t('U liveu')
          : d.isListed
          ? t('Kupi odmah')
          : t('Spremljeno'),
    ));
  }
  return out;
}

/// Izbornik "Kreiraj" (kao Whatnot Sell): brzi predmet za live, predmet s
/// detaljima, aukcija ili uvoz iz inventara u show.
Future<void> showCreateSheet(BuildContext context, WidgetRef ref) async {
  final s = ref.read(appProvider);
  final me = s.currentUserId;
  final now = DateTime.now();
  final shows = [
    for (final show in s.liveShows)
      if (show.hostId == me && !s.liveStateOf(show, now).isOver) show,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  final LiveShow? next = shows.firstOrNull;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      Widget option(String key, IconData icon, String title, String subtitle) =>
          ListTile(
            key: ValueKey('create-$key'),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: LoopColors.surfaceHover,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20),
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(subtitle),
            onTap: () => Navigator.pop(ctx, key),
          );
      return SafeArea(
        child: Column(
          key: const ValueKey('create-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('Kreiraj'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            option(
              'quick',
              Icons.bolt,
              t('Brzi predmet za live'),
              next == null
                  ? t('Naziv i cijena, prvo kreiraš show.')
                  : t('Naziv i cijena, ide u "{0}".', [next.title]),
            ),
            option(
              'item',
              Icons.sell_outlined,
              t('Predmet s detaljima'),
              t('Fotografije, opis, stanje i dostava.'),
            ),
            option(
              'auction',
              Icons.gavel,
              t('Aukcija'),
              t('Licitacija s rokom, bez livea.'),
            ),
            if (next != null)
              option(
                'import',
                Icons.move_to_inbox_outlined,
                t('Uvezi iz inventara'),
                t('Spremljeni predmet u "{0}".', [next.title]),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'quick':
    case 'import':
      if (next == null) {
        await CreateLiveShowScreen.open(context);
      } else {
        await showAddToShowSheet(context, ref, next);
      }
    case 'item':
      await AddDeviceScreen.open(context);
    case 'auction':
      await CreateAuctionScreen.open(context);
  }
}

/// Inventar kao Whatnot: Aktivno / Spremljeno / Prodano, pretraga i
/// "Kreiraj" na dnu.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const InventoryScreen()));

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _query = '';

  bool _match(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final storage = ref.read(storageProvider);
    final me = s.currentUserId;
    final items = [
      for (final e in inventoryOf(s, (id) => LiveService.isLocked(storage, id)))
        if (_match('${e.$1.name} ${e.$1.model}')) e,
    ];
    final active = [
      for (final e in items)
        if (e.$2 == InventoryState.active) e,
    ];
    final drafts = [
      for (final e in items)
        if (e.$2 == InventoryState.draft) e,
    ];
    final sold = [
      for (final tx in s.transactions)
        if (tx.type == TransactionType.sell &&
            (tx.sellerId ?? tx.userId) == me &&
            tx.buyerId != null &&
            tx.buyerId != me &&
            _match(tx.deviceName))
          tx,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final muted = TextStyle(color: LoopColors.textSecondary, fontSize: 12);

    Widget empty(String text) => Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 44,
            color: LoopColors.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );

    Widget itemList(
      List<(Device, InventoryState, String)> list,
      String emptyText,
    ) => list.isEmpty
        ? ListView(children: [empty(emptyText)])
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: LoopColors.surfaceHover),
            itemBuilder: (_, i) {
              final (d, _, label) = list[i];
              return InkWell(
                key: ValueKey('inv-${d.id}'),
                onTap: () => DeviceDetailScreen.open(context, d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      ItemThumb(device: d, size: 56),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '$label · ${t('Količina: {0}', ['${d.quantity}'])}',
                              style: muted,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatCredits(d.listPrice ?? d.price),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: LoopColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              );
            },
          );

    final soldList = sold.isEmpty
        ? ListView(children: [empty(t('Još ništa nije prodano.'))])
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: sold.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: LoopColors.surfaceHover),
            itemBuilder: (_, i) {
              final tx = sold[i];
              return ListTile(
                key: ValueKey('inv-sold-${tx.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: LoopColors.surfaceHover,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.sell_outlined, size: 20),
                ),
                title: Text(
                  tx.deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${formatDate(tx.createdAt)} · @${s.userLabel(tx.buyerId)}',
                ),
                trailing: Text(
                  formatCredits(tx.price),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              );
            },
          );

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('Inventar')),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(112),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: TextField(
                    key: const ValueKey('inv-search'),
                    onChanged: (v) => setState(() => _query = v.trim()),
                    decoration: InputDecoration(
                      hintText: t('Pretraži inventar'),
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                TabBar(
                  dividerColor: LoopColors.surfaceHover,
                  indicatorColor: LoopColors.textPrimary,
                  labelColor: LoopColors.textPrimary,
                  unselectedLabelColor: LoopColors.textSecondary,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                  tabs: [
                    Tab(
                      key: const ValueKey('inv-tab-active'),
                      text: t('Aktivno ({0})', ['${active.length}']),
                    ),
                    Tab(
                      key: const ValueKey('inv-tab-draft'),
                      text: t('Spremljeno ({0})', ['${drafts.length}']),
                    ),
                    Tab(
                      key: const ValueKey('inv-tab-sold'),
                      text: t('Prodano ({0})', ['${sold.length}']),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            itemList(active, t('Nema aktivnih predmeta.')),
            itemList(drafts, t('Nema spremljenih predmeta.')),
            soldList,
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const ValueKey('inv-create'),
                onPressed: () => showCreateSheet(context, ref),
                icon: const Icon(Icons.add),
                label: Text(t('Kreiraj')),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
