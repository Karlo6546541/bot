import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../screens/add_device_screen.dart';
import '../screens/create_auction_screen.dart';
import '../theme/app_theme.dart';
import 'story_editor.dart';
import 'trade_actions.dart';

/// "+ Objavi": jedno mjesto za sve što korisnik objavljuje — oglas u
/// Marketu, aukciju ili priču.
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
        String emoji,
        Color color,
        String title,
        String subtitle,
      ) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(kRadius),
          child: InkWell(
            key: ValueKey('create-$key'),
            borderRadius: BorderRadius.circular(kRadius),
            onTap: () => Navigator.pop(ctx, key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 13,
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
                t('Što želiš objaviti?'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              option(
                'item',
                '📦',
                LoopColors.mint,
                t('Oglas'),
                t('Fiksna cijena u Marketu'),
              ),
              option(
                'auction',
                '🔨',
                LoopColors.lilac,
                t('Aukcija'),
                t('Najviša ponuda pobjeđuje'),
              ),
              option(
                'story',
                '✨',
                LoopColors.peach,
                t('Priča'),
                t('Vidljivo 24 sata'),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'item':
      await AddDeviceScreen.open(context);
    case 'auction':
      await CreateAuctionScreen.open(context);
    case 'story':
      await CreateStoryScreen.open(context);
  }
}
