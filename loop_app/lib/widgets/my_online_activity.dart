import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../providers/my_activity_provider.dart';
import '../screens/cloud_commerce_screen.dart';
import '../services/commerce_backend.dart';
import '../services/stripe_backend.dart';

/// Online records stay in their authoritative tables, alongside legacy history.
class MyOnlineActivityPanel extends ConsumerWidget {
  const MyOnlineActivityPanel({
    super.key,
    this.shipmentsOnly = false,
    this.filter = 'all',
  });
  final bool shipmentsOnly;
  final String filter;

  Future<void> _orders(
    BuildContext context,
    WidgetRef ref, {
    String? id,
  }) async {
    final client = ref.read(preparedLiveBackendProvider)?.client;
    if (client == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudCommerceScreen(
          client: client,
          initialTab: 2,
          liveOnly: true,
          initialOrder: id,
        ),
      ),
    );
    if (context.mounted) ref.invalidate(myOnlineActivityProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(myOnlineActivityProvider);
    final uid = ref.watch(appProvider.select((s) => s.currentUserId));
    return result.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (_, _) => ListTile(
        title: const Text('Podaci iz baze nisu učitani.'),
        trailing: TextButton(
          onPressed: () => ref.invalidate(myOnlineActivityProvider),
          child: const Text('Pokušaj ponovno'),
        ),
      ),
      data: (data) {
        if (data == null) return const SizedBox.shrink();
        final orders = data.orders.where((o) {
          if (shipmentsOnly) {
            if (o['seller_id'] != uid) return false;
            if (filter == 'ship') return o['status'] == 'paid';
            if (filter == 'sent') {
              return o['status'] == 'shipped' || o['status'] == 'delivered';
            }
            return o['status'] != 'cancelled' && o['status'] != 'refunded';
          }
          return filter == 'all' ||
              (filter == 'bought' && o['buyer_id'] == uid) ||
              (filter == 'sold' && o['seller_id'] == uid);
        }).toList();
        final showRooms =
            !shipmentsOnly && (filter == 'all' || filter == 'mine');
        final showBids = !shipmentsOnly && filter == 'all';
        final showAwards =
            !shipmentsOnly && (filter == 'all' || filter == 'bought');
        final cards = <Widget>[
          if (showRooms)
            for (final room in data.rooms)
              ListTile(
                key: ValueKey('online-room-${room['id']}'),
                leading: const Icon(Icons.videocam_outlined),
                title: Text(room['title'] as String),
                subtitle: Text(switch (room['status']) {
                  'live' => 'Uživo',
                  'scheduled' => 'Zakazano',
                  _ => 'Završeno',
                }),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final client = ref.read(preparedLiveBackendProvider)?.client;
                  if (client == null) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CloudCommerceScreen(
                        client: client,
                        initialRoom: room['id'] as String,
                        liveOnly: true,
                      ),
                    ),
                  );
                  if (context.mounted) ref.invalidate(myOnlineActivityProvider);
                },
              ),
          if (showBids)
            for (final bid in data.bids)
              if (bid['live_lots'] case final Map lot)
                ListTile(
                  key: ValueKey('online-bid-${bid['lot_id']}'),
                  leading: const Icon(Icons.gavel),
                  title: Text('${lot['title']}'),
                  subtitle: Text(
                    'Tvoja ponuda · ${((bid['amount_cents'] as num) / 100).toStringAsFixed(2)} €',
                  ),
                  trailing: Text(
                    lot['status'] == 'running'
                        ? (lot['winner_id'] == uid ? 'Vodiš' : 'Nadmašen')
                        : 'Završeno',
                  ),
                  onTap: () {
                    final client = ref
                        .read(preparedLiveBackendProvider)
                        ?.client;
                    if (client != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CloudCommerceScreen(
                            client: client,
                            initialRoom: lot['room_id'] as String,
                            liveOnly: true,
                          ),
                        ),
                      );
                    }
                  },
                ),
          if (showAwards)
            for (final award in data.unclaimedAwards)
              ListTile(
                key: ValueKey('online-award-${award['lot_id']}'),
                leading: const Icon(Icons.emoji_events_outlined),
                title: Text(
                  '${(award['live_lots'] as Map?)?['title'] ?? 'Osvojen predmet'}',
                ),
                subtitle: const Text('Osvojeno · dovrši narudžbu'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final client = ref.read(preparedLiveBackendProvider)?.client;
                  if (client == null) return;
                  try {
                    // Award identity is stable: retries return the existing order.
                    final order = await CommerceBackend(client).claimAward(
                      award['lot_id'] as String,
                      award['lot_id'] as String,
                    );
                    ref.invalidate(myOnlineActivityProvider);
                    if (context.mounted) {
                      await _orders(
                        context,
                        ref,
                        id: (order as Map)['id'] as String,
                      );
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(paymentActionErrorMessage(error)),
                        ),
                      );
                    }
                  }
                },
              ),
          for (final order in orders)
            ListTile(
              key: ValueKey('online-order-${order['id']}'),
              leading: Icon(
                shipmentsOnly
                    ? Icons.local_shipping_outlined
                    : Icons.shopping_bag_outlined,
              ),
              title: Text(
                '${order['buyer_id'] == uid ? 'Kupnja' : 'Prodaja'} · ${((order['total_cents'] as num) / 100).toStringAsFixed(2)} €',
              ),
              subtitle: Text(switch (order['status']) {
                'awaiting_payment' => 'Čeka plaćanje',
                'paid' => 'Plaćeno · priprema dostave',
                'shipped' => 'Poslano',
                'delivered' => 'Dostavljeno',
                'refunded' => 'Vraćeno',
                _ => 'Otkazano',
              }),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _orders(context, ref, id: order['id'] as String),
            ),
        ];
        if (cards.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    shipmentsOnly ? 'Narudžbe i dostava' : 'Aktivnost u liveu',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                ...cards,
                TextButton.icon(
                  onPressed: () => ref.invalidate(myOnlineActivityProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Osvježi'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
