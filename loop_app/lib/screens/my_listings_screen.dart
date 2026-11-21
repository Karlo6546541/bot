import '../config/features.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/auction.dart';
import '../models/device.dart';
import '../models/loop_transaction.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import 'auctions_home_screen.dart' show AuctionTile, BuyNowTile;
import 'deliveries_screen.dart' show DeliveryDetailScreen;
import 'device_detail_screen.dart';
import 'sell_screens.dart';

/// "Moji oglasi" kao na Vintedu: Aktivni (oglasi Kupi odmah i aukcije u
/// tijeku) i Prodano (prodaje s cijenom, datumom i stanjem slanja).
class MyListingsScreen extends ConsumerStatefulWidget {
  const MyListingsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const MyListingsScreen()));

  @override
  ConsumerState<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<MyListingsScreen> {
  bool _sold = false;

  /// Oglasnik: 0 aktivni, 1 istekli, 2 prodani.
  int _tab = 0;

  Widget _classifieds(BuildContext context) {
    final s = ref.watch(appProvider);
    final now = DateTime.now();
    final mine = s.myDevices;
    final active = [
      for (final d in mine)
        if (d.isListed && !d.isExpiredAt(now)) d,
    ];
    final expired = [
      for (final d in mine)
        if (d.isExpiredAt(now)) d,
    ];
    final sold = [
      for (final d in mine)
        if (d.isSold) d,
    ]..sort((a, b) => b.soldAt!.compareTo(a.soldAt!));
    final lists = [active, expired, sold];
    final labels = [
      t('Aktivni ({0})', ['${active.length}']),
      t('Istekli ({0})', ['${expired.length}']),
      t('Prodano ({0})', ['${sold.length}']),
    ];
    final list = lists[_tab];
    return Scaffold(
      key: const ValueKey('my-listings'),
      appBar: AppBar(
        title: Text(t('Moji oglasi')),
        actions: [
          IconButton(
            key: const ValueKey('my-listings-new'),
            tooltip: t('Novi oglas'),
            icon: const Icon(Icons.add),
            onPressed: () => SellAuctionScreen.open(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: InkWell(
                    key: ValueKey('my-listings-tab-$i'),
                    onTap: () => setState(() => _tab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _tab == i
                                ? LoopColors.accent
                                : LoopColors.glassBorder,
                            width: _tab == i ? 2.5 : 1,
                          ),
                        ),
                      ),
                      child: Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: _tab == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _tab == i ? null : LoopColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: list.isEmpty
                ? EmptyState(
                    icon: Icons.sell_outlined,
                    title: _tab == 0
                        ? t('Nemaš aktivnih oglasa')
                        : _tab == 1
                        ? t('Nema isteklih oglasa')
                        : t('Još nemaš prodanih predmeta'),
                    message: _tab == 0
                        ? t('Objavi predmet i kupci će te kontaktirati porukom.')
                        : null,
                    action: _tab == 0
                        ? FilledButton(
                            key: const ValueKey('my-listings-sell'),
                            onPressed: () => SellAuctionScreen.open(context),
                            child: Text(t('Objavi oglas')),
                          )
                        : null,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: LoopColors.glassBorder),
                    itemBuilder: (_, i) {
                      final d = list[i];
                      final subtitle = _tab == 2
                          ? t('Prodano {0}', [formatDate(d.soldAt!)])
                          : _tab == 1
                          ? t('Istekao {0}', [formatDate(d.expiresAt!)])
                          : t('Aktivan do {0}', [formatDate(d.expiresAt!)]);
                      return ListTile(
                        key: ValueKey('my-listing-item-${d.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ItemThumb(device: d, size: 56),
                        ),
                        title: Text(
                          d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(subtitle),
                        trailing: Text(
                          formatCredits(
                            _tab == 2 ? (d.soldPrice ?? d.price) : d.askPrice,
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () => DeviceDetailScreen.open(context, d),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kClassifiedsMode) return _classifieds(context);
    final s = ref.watch(appProvider);
    final me = s.currentUserId ?? '';
    final auctions = [
      for (final a in s.activeAuctions)
        if (a.sellerId == me) a,
    ];
    final auctionDevices = {for (final a in auctions) a.deviceId};
    final listings = [
      for (final d in s.myListings)
        if (!auctionDevices.contains(d.id)) d,
    ];
    final active = <Object>[...auctions, ...listings];
    final sales = [
      for (final t in s.transactions)
        if (t.type == TransactionType.sell &&
            (t.sellerId ?? t.userId) == me &&
            t.buyerId != null &&
            t.buyerId != me)
          t,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final width = MediaQuery.sizeOf(context).width.clamp(0, 900).toDouble();
    final columns = width >= 700 ? 3 : 2;
    Widget tab(String key, String label, bool on, VoidCallback onTap) =>
        Expanded(
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: on ? LoopColors.accent : LoopColors.glassBorder,
                    width: on ? 2.5 : 1,
                  ),
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? null : LoopColors.textSecondary,
                ),
              ),
            ),
          ),
        );
    return Scaffold(
      key: const ValueKey('my-listings'),
      appBar: AppBar(
        title: Text(t('Moji oglasi')),
        actions: [
          IconButton(
            key: const ValueKey('my-listings-new'),
            tooltip: t('Novi oglas'),
            icon: const Icon(Icons.add),
            onPressed: () => SellAuctionScreen.open(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            children: [
              tab(
                'my-listings-active',
                t('Aktivni ({0})', ['${active.length}']),
                !_sold,
                () => setState(() => _sold = false),
              ),
              tab(
                'my-listings-sold',
                t('Prodano ({0})', ['${sales.length}']),
                _sold,
                () => setState(() => _sold = true),
              ),
            ],
          ),
          Expanded(
            child: !_sold
                ? active.isEmpty
                      ? EmptyState(
                          icon: Icons.sell_outlined,
                          title: t('Nemaš aktivnih oglasa'),
                          message: t(
                            'Objavi predmet za Kupi odmah ili ga stavi na aukciju.',
                          ),
                          action: FilledButton(
                            key: const ValueKey('my-listings-sell'),
                            onPressed: () => SellAuctionScreen.open(context),
                            child: Text(t('Prodaj')),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent:
                                    (width - 32 - (columns - 1) * 12) /
                                        columns +
                                    132 *
                                        MediaQuery.textScalerOf(
                                          context,
                                        ).scale(1),
                              ),
                          itemCount: active.length,
                          itemBuilder: (_, i) => switch (active[i]) {
                            final Auction a => AuctionTile(
                              key: ValueKey('my-listing-auction-${a.id}'),
                              auction: a,
                            ),
                            final Device d => BuyNowTile(
                              key: ValueKey('my-listing-item-${d.id}'),
                              device: d,
                            ),
                            _ => const SizedBox.shrink(),
                          },
                        )
                : sales.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: t('Još nemaš prodaja'),
                    message: t('Ovdje vidiš što si prodao i je li poslano.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: sales.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: LoopColors.glassBorder),
                    itemBuilder: (_, i) => _SoldRow(sale: sales[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SoldRow extends ConsumerWidget {
  const _SoldRow({required this.sale});
  final LoopTransaction sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final device = s.deviceById(sale.deviceId);
    final delivery = s.sellerDeliveries
        .where((d) => d.deviceId == sale.deviceId && d.buyerId == sale.buyerId)
        .firstOrNull;
    final now = DateTime.now();
    final status = delivery == null
        ? t('Prodano')
        : delivery.confirmedAt != null
        ? t('Završeno')
        : delivery.isDelivered(now)
        ? t('Dostavljeno')
        : delivery.handedOverAt != null
        ? t('Poslano')
        : t('Pošalji paket');
    final needsAction = status == t('Pošalji paket');
    return InkWell(
      key: ValueKey('my-sold-${sale.id}'),
      onTap: delivery == null
          ? null
          : () => DeliveryDetailScreen.open(context, delivery.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: device == null
                  ? Container(
                      width: 56,
                      height: 56,
                      color: LoopColors.surfaceHover,
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: LoopColors.textSecondary,
                      ),
                    )
                  : ItemThumb(device: device, size: 56),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${formatDate(sale.createdAt)} · ${sale.buyerLabel.isEmpty ? s.userLabel(sale.buyerId) : sale.buyerLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    style: TextStyle(
                      color: needsAction
                          ? LoopColors.accent
                          : LoopColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: needsAction
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatCredits(sale.price),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
