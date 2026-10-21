import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/user_avatar.dart';
import 'auctions_screen.dart';
import 'device_detail_screen.dart';
import '../widgets/device_card.dart';
import '../widgets/trade_actions.dart';

/// Javni profil korisnika: fotografija, @ime, opis, grad i aukcije.
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  static Future<void> open(BuildContext context, String userId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PublicProfileScreen(userId: userId),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final listings = state.listingsOf(user.id);
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
    return Scaffold(
      appBar: AppBar(title: Text(user.handle)),
      body: CustomScrollView(
        slivers: [
          box(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ProfileHeader(user: user),
            ),
          ),
          box(title(t('Na prodaju u Marketu ({0})', [listings.length]))),
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
                  child: AuctionCard(auction: a, viewerId: viewer),
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
  const ProfileHeader({super.key, required this.user, this.trailing});

  final AppUser user;
  final Widget? trailing;

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
