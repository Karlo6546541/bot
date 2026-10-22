import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_notification.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import 'auction_detail_screen.dart';
import 'deliveries_screen.dart';
import 'device_detail_screen.dart';
import 'messages_screen.dart';
import 'public_profile_screen.dart';

/// Obavijesti: nadmašen na aukciji, prodan predmet, ocjene, poruke…
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));

  /// Dodir vodi na ono na što se obavijest odnosi.
  static Future<void> openTarget(
    BuildContext context,
    WidgetRef ref,
    AppNotification n,
  ) async {
    final id = n.targetId;
    final state = ref.read(appProvider);
    switch (n.kind) {
      case NotificationKind.outbid ||
          NotificationKind.outbidAuto ||
          NotificationKind.followedAuction ||
          NotificationKind.auctionEndingSoon ||
          NotificationKind.newBid ||
          NotificationKind.auctionLost ||
          NotificationKind.auctionSold ||
          NotificationKind.auctionUnsold:
        if (id != null) await AuctionDetailScreen.open(context, id);
      case NotificationKind.auctionWon:
        await DeliveriesScreen.open(context);
      case NotificationKind.itemSold ||
          NotificationKind.priceDrop ||
          NotificationKind.bargainNew ||
          NotificationKind.bargainAccepted ||
          NotificationKind.bargainDeclined ||
          NotificationKind.bargainCountered ||
          NotificationKind.counterAccepted ||
          NotificationKind.followedNewItem ||
          NotificationKind.followedDiscount ||
          NotificationKind.soldOut:
        final d = id == null ? null : state.deviceById(id);
        if (d != null) await DeviceDetailScreen.open(context, d);
      case NotificationKind.newReview ||
          NotificationKind.referral ||
          NotificationKind.newFollower:
        if (id != null) await PublicProfileScreen.open(context, id);
      case NotificationKind.newMessage ||
          NotificationKind.swapOffer ||
          NotificationKind.swapAccepted ||
          NotificationKind.swapDeclined:
        if (id != null) await ChatScreen.open(context, id);
      case NotificationKind.reportResolved:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(appProvider.select((s) => s.myNotifications));
    final unread = list.where((n) => !n.read).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Obavijesti')),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () =>
                  ref.read(appProvider.notifier).markNotificationsRead(),
              child: Text(t('Označi sve kao pročitano')),
            ),
        ],
      ),
      body: list.isEmpty
          ? EmptyState(
              icon: Icons.notifications_none,
              title: t('Nema obavijesti'),
              message: t(
                'Ovdje stižu ponude na aukcijama, prodaje, ocjene i poruke.',
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final n = list[i];
                    return Material(
                      color: n.read ? LoopColors.surface : LoopColors.peach,
                      borderRadius: BorderRadius.circular(kRadius),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kRadius),
                        ),
                        leading: Text(
                          n.kind.emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                        title: Text(
                          n.text,
                          style: TextStyle(
                            fontWeight: n.read
                                ? FontWeight.w500
                                : FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(formatDateTime(n.createdAt)),
                        onTap: () async {
                          await ref
                              .read(appProvider.notifier)
                              .markNotificationsRead(id: n.id);
                          if (context.mounted) {
                            await openTarget(context, ref, n);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

/// Zvono s brojem nepročitanih obavijesti (gornja traka).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(appProvider.select((s) => s.unreadNotifications));
    return IconButton(
      key: const ValueKey('notification-bell'),
      tooltip: t('Obavijesti'),
      onPressed: () => NotificationsScreen.open(context),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
