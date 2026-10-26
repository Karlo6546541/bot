import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_notification.dart';
import '../models/auction.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/auction_widgets.dart';
import '../widgets/countdown.dart';
import '../widgets/empty_state.dart';
import '../widgets/item_image.dart';
import '../widgets/loop_snackbar.dart';
import 'auction_detail_screen.dart';
import 'deliveries_screen.dart';
import 'device_detail_screen.dart';
import 'live_screens.dart';
import 'messages_screen.dart';
import 'public_profile_screen.dart';

/// Obavijesti: filteri po skupinama (aukcije, kupnje, ponude…), dani,
/// spojene ponovljene obavijesti, kartice aukcija s gumbima "Licitiraj" /
/// "Odaberi dostavu" i postavke (što želiš primati).
class NotificationsScreen extends ConsumerStatefulWidget {
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
      case NotificationKind.auctionWon || NotificationKind.giveawayWon:
        await DeliveriesScreen.open(context);
      case NotificationKind.liveStarted:
        if (id != null) await LiveRoomScreen.open(context, id);
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
      case NotificationKind.contentRemoved:
        if (id != null) await showAppealDialog(context, ref, id);
    }
  }

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

/// Jedna stavka popisa: najnovija obavijest + starije iste vrste za isti
/// predmet/aukciju (npr. 5 novih ponuda na istoj aukciji = jedna kartica).
class _Cluster {
  _Cluster(this.latest);
  final AppNotification latest;
  final List<AppNotification> all = [];

  bool get unread => all.any((n) => !n.read);
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  NotificationGroup? _filter;

  /// Danas / Jučer / Ovaj tjedan / Ranije.
  static String _section(DateTime at, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return t('Danas');
    if (diff == 1) return t('Jučer');
    if (diff < 7) return t('Ovaj tjedan');
    return t('Ranije');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final all = [...state.myNotifications]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final unread = all.where((n) => !n.read).length;
    final unreadBy = <NotificationGroup, int>{};
    final present = <NotificationGroup>{};
    for (final n in all) {
      present.add(n.kind.group);
      if (!n.read) {
        unreadBy.update(n.kind.group, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final filter = present.contains(_filter) ? _filter : null;
    final shown = filter == null
        ? all
        : all.where((n) => n.kind.group == filter).toList();

    // Sekcije po danima; unutar dana spoji istu vrstu za isti cilj.
    final now = DateTime.now();
    final sections = <String, List<_Cluster>>{};
    final index = <String, _Cluster>{};
    for (final n in shown) {
      final sec = _section(n.createdAt, now);
      // Aukcije: jedna kartica po aukciji; ostalo: ista vrsta za isti cilj.
      final key = n.targetId == null
          ? n.id
          : n.kind.group == NotificationGroup.auctions
          ? '$sec|auction|${n.targetId}'
          : '$sec|${n.kind.name}|${n.targetId}';
      final c = index[key] ??= () {
        final c = _Cluster(n);
        (sections[sec] ??= []).add(c);
        return c;
      }();
      c.all.add(n);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t('Obavijesti')),
        actions: [
          if (unread > 0)
            IconButton(
              key: const ValueKey('mark-all-read'),
              tooltip: t('Označi sve kao pročitano'),
              icon: const Icon(Icons.done_all),
              onPressed: () =>
                  ref.read(appProvider.notifier).markNotificationsRead(),
            ),
          IconButton(
            key: const ValueKey('notification-settings'),
            tooltip: t('Postavke obavijesti'),
            icon: const Icon(Icons.tune),
            onPressed: () => showNotificationSettings(context),
          ),
        ],
      ),
      body: all.isEmpty
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
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _Filters(
                        present: present,
                        unreadBy: unreadBy,
                        unreadAll: unread,
                        selected: filter,
                        onSelect: (g) => setState(() => _filter = g),
                      ),
                    ),
                    if (filter == NotificationGroup.auctions)
                      SliverToBoxAdapter(child: _AuctionSummary(state: state)),
                    for (final e in sections.entries) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                          child: Text(
                            e.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        sliver: SliverList.separated(
                          itemCount: e.value.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, i) =>
                              _NotificationTile(cluster: e.value[i]),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Filteri: Sve · Aukcije · Kupnje i prodaje · Ponude · Društvo · Poruke.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.present,
    required this.unreadBy,
    required this.unreadAll,
    required this.selected,
    required this.onSelect,
  });

  final Set<NotificationGroup> present;
  final Map<NotificationGroup, int> unreadBy;
  final int unreadAll;
  final NotificationGroup? selected;
  final ValueChanged<NotificationGroup?> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget chip(Key key, String label, int count, bool on, VoidCallback tap) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            key: key,
            selected: on,
            onSelected: (_) => tap(),
            showCheckmark: false,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: LoopColors.accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        children: [
          chip(
            const ValueKey('notif-filter-all'),
            t('Sve'),
            unreadAll,
            selected == null,
            () => onSelect(null),
          ),
          for (final g in NotificationGroup.values)
            if (present.contains(g))
              chip(
                ValueKey('notif-filter-${g.name}'),
                '${g.emoji} ${g.label}',
                unreadBy[g] ?? 0,
                selected == g,
                () => onSelect(g),
              ),
        ],
      ),
    );
  }
}

/// Sažetak mojih aktivnih aukcija (na filteru "Aukcije").
class _AuctionSummary extends StatelessWidget {
  const _AuctionSummary({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final me = state.currentUserId;
    final active = state.auctions.where((a) => a.isActive).toList();
    final leading = active.where((a) => a.highestBid?.userId == me).length;
    final outbid = active
        .where(
          (a) =>
              a.highestBid?.userId != me && a.bids.any((b) => b.userId == me),
        )
        .length;
    final selling = active.where((a) => a.sellerId == me).length;
    Widget stat(String emoji, String label, int value, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              '$emoji $value',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: LoopColors.textSecondary),
            ),
          ],
        ),
      ),
    );
    return Padding(
      key: const ValueKey('auction-summary'),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          stat('🏁', t('Vodiš'), leading, LoopColors.success),
          const SizedBox(width: 8),
          stat('⚠️', t('Nadmašen'), outbid, const Color(0xFFFF9500)),
          const SizedBox(width: 8),
          stat('🔨', t('Tvoje aukcije'), selling, LoopColors.accent),
        ],
      ),
    );
  }
}

/// "prije 5 min", "prije 3 h", inače datum i vrijeme.
String _when(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return t('upravo');
  if (d.inHours < 1) return t('prije {0} min', ['${d.inMinutes}']);
  if (d.inHours < 24) return t('prije {0} h', ['${d.inHours}']);
  return formatDateTime(at);
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.cluster});
  final _Cluster cluster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final n = cluster.latest;
    final c = ref.read(appProvider.notifier);
    final auction =
        n.kind.group == NotificationGroup.auctions && n.targetId != null
        ? state.auctionById(n.targetId!)
        : null;
    final device = auction != null
        ? state.deviceById(auction.deviceId)
        : n.targetId == null
        ? null
        : state.deviceById(n.targetId!);
    final more = cluster.all.length - 1;

    Future<void> open() async {
      for (final x in cluster.all.where((x) => !x.read)) {
        await c.markNotificationsRead(id: x.id);
      }
      if (context.mounted) {
        await NotificationsScreen.openTarget(context, ref, n);
      }
    }

    final leadingWidget = device == null
        ? Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LoopColors.surfaceHover,
              shape: BoxShape.circle,
            ),
            child: Text(n.kind.emoji, style: const TextStyle(fontSize: 22)),
          )
        : SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ItemThumb(device: device, size: 52),
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: LoopColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      n.kind.emoji,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          );

    return Dismissible(
      key: ValueKey('notif-${n.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: LoopColors.error,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => c.deleteNotifications(cluster.all.map((x) => x.id)),
      child: Material(
        color: cluster.unread ? LoopColors.peach : LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        child: InkWell(
          key: ValueKey('notif-tile-${n.id}'),
          borderRadius: BorderRadius.circular(kRadius),
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leadingWidget,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.text,
                        style: TextStyle(
                          fontWeight: cluster.unread
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        more > 0
                            ? moreSimilarLabel(_when(n.createdAt), more)
                            : _when(n.createdAt),
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (auction != null)
                        _AuctionActions(notification: n, auction: auction),
                    ],
                  ),
                ),
                if (cluster.unread)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 4),
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: LoopColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stanje aukcije i brze radnje ispod obavijesti.
class _AuctionActions extends ConsumerWidget {
  const _AuctionActions({required this.notification, required this.auction});
  final AppNotification notification;
  final Auction auction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = auction;
    final kind = notification.kind;
    final me = ref.watch(appProvider.select((s) => s.currentUserId));
    final mine = a.sellerId == me;
    final leading = a.highestBid?.userId == me;
    final bidding = a.bids.any((b) => b.userId == me);

    Widget pill(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );

    final status = <Widget>[
      if (a.isActive) ...[
        AuctionCountdown(
          endsAt: a.endsAt,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        Text(
          formatCredits(a.currentPrice),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
        if (!mine && leading) pill(t('Vodiš ✓'), LoopColors.success),
        if (!mine && bidding && !leading)
          pill(t('Nadmašen'), const Color(0xFFE67700)),
        if (mine)
          pill(t('{0} ponuda', ['${a.bids.length}']), LoopColors.accent),
      ] else
        pill(
          a.statusLabelFor(ref.read(appProvider).currentUserId),
          LoopColors.textSecondary,
        ),
    ];

    final compact = FilledButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(
        fontFamily: kFontFamily,
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
    );
    final action = kind == NotificationKind.auctionWon
        ? FilledButton.icon(
            key: ValueKey('notif-delivery-${a.id}'),
            style: compact,
            onPressed: () => DeliveriesScreen.open(context),
            icon: const Icon(Icons.local_shipping_outlined, size: 16),
            label: Text(t('Odaberi dostavu')),
          )
        : kind.invitesBid && a.isActive && !mine && !leading
        ? FilledButton.icon(
            key: ValueKey('notif-bid-${a.id}'),
            style: compact,
            onPressed: () => showBidSheet(context, ref, a.id),
            icon: const Icon(Icons.gavel, size: 16),
            label: Text(bidding ? t('Povisi ponudu') : t('Licitiraj')),
          )
        : null;

    // Stanje lijevo, radnja desno (u jednom retku kad stane).
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: status,
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Žalba na uklanjanje oglasa (DSA): kratko obrazloženje → admin.
Future<void> showAppealDialog(
  BuildContext context,
  WidgetRef ref,
  String reportId,
) async {
  final text = TextEditingController();
  final sent = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setState) => MediaQuery.removeViewInsets(
          context: ctx,
          removeBottom: true,
          child: AlertDialog(
            alignment: Alignment.topCenter,
            scrollable: true,
            title: Text(t('Žalba na odluku')),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t(
                      'Žalbu pregledava druga osoba. Imaš i pravo na izvansudsko rješavanje spora i sudsku zaštitu.',
                    ),
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('appeal-text'),
                    controller: text,
                    maxLines: 4,
                    maxLength: 300,
                    decoration: InputDecoration(
                      labelText: t('Zašto se ne slažeš?'),
                      errorText: error,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t('Odustani')),
              ),
              FilledButton(
                key: const ValueKey('appeal-send'),
                onPressed: () async {
                  try {
                    await ref
                        .read(appProvider.notifier)
                        .appeal(reportId, text.text);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } on TradeException catch (e) {
                    setState(() => error = e.message);
                  }
                },
                child: Text(t('Pošalji žalbu')),
              ),
            ],
          ),
        ),
      );
    },
  );
  text.dispose();
  if (sent == true) {
    showLoopSnackBar(t('Žalba je poslana — javit ćemo ti odluku.'));
  }
}

/// Postavke: koje obavijesti želiš primati (posebno za aukcije).
Future<void> showNotificationSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: LoopColors.background,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const _SettingsSheet(),
    );

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = ref.watch(
      appProvider.select((s) => s.currentUser?.mutedNotifications ?? const []),
    );
    final c = ref.read(appProvider.notifier);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              t('Postavke obavijesti'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'Rezultati aukcija, prodaje, ponude za cijenu i poruke stižu uvijek.',
              ),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
            ),
            for (final g in NotificationGroup.values)
              if (NotificationPref.values.any((p) => p.group == g)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                  child: Text(
                    '${g.emoji} ${g.label}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final p in NotificationPref.values)
                        if (p.group == g)
                          SwitchListTile(
                            key: ValueKey('pref-${p.name}'),
                            value: !muted.contains(p.name),
                            onChanged: (_) => c.toggleNotificationPref(p),
                            title: Text(
                              p.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(p.hint),
                          ),
                    ],
                  ),
                ),
              ],
          ],
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
