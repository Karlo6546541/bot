import '../config/features.dart';
import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../screens/add_device_screen.dart';
import '../screens/create_auction_screen.dart';
import '../screens/live_screens.dart';
import '../theme/app_theme.dart';
import 'trade_actions.dart';

/// "+ Objavi": live (odmah ili zakazan), aukcija ili predmet za prodaju —
/// Kupi odmah, aukcija ili live biraju se na samom predmetu.
Future<void> showCreateSheet(BuildContext context) async {
  if (blockGuest(context)) return;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    // Visina prema sadržaju (zadana granica od pola ekrana rezala je dno).
    isScrollControlled: true,
    backgroundColor: LoopColors.background,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (ctx) {
      Widget option(
        String key,
        IconData icon,
        String title,
        String subtitle,
      ) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: LoopColors.surface,
          borderRadius: BorderRadius.circular(kRadius),
          child: InkWell(
            key: ValueKey('create-$key'),
            borderRadius: BorderRadius.circular(kRadius),
            onTap: () => Navigator.pop(ctx, key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(icon, size: 26, color: LoopColors.accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: LoopColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('Što želiš pokrenuti?'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 16),
              option(
                'item',
                Icons.sell_outlined,
                t('Prodaj predmet'),
                t('Slikaj, upiši cijenu i objavi'),
              ),
              if (kLiveEnabled)
                option(
                  'live',
                  Icons.videocam_outlined,
                  t('Live aukcija'),
                  t('Kreni odmah ili zakaži · video, chat, brze licitacije'),
                ),
              option(
                'auction',
                Icons.gavel,
                t('Aukcija'),
                t('Traje satima ili danima, najviša ponuda pobjeđuje'),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'live':
      await CreateLiveShowScreen.open(context);
    case 'auction':
      await CreateAuctionScreen.open(context);
    case 'item':
      await AddDeviceScreen.open(context);
  }
}
