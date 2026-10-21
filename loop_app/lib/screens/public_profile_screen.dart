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
    final auctions = state.activeAuctions
        .where((a) => a.sellerId == user!.id)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(user.handle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              ProfileHeader(user: user),
              const SizedBox(height: 20),
              Text(
                t('Aktivne aukcije ({0})', [auctions.length]),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              if (auctions.isEmpty)
                Text(
                  t('Nema aukcija'),
                  style: TextStyle(color: LoopColors.textSecondary),
                )
              else
                for (final a in auctions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AuctionCard(auction: a, viewerId: viewer),
                  ),
            ],
          ),
        ),
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
