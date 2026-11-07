import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../models/app_user.dart';
import '../models/live_show.dart';
import 'user_avatar.dart';
import '../screens/auctions_screen.dart' show BrowseCardMedia;
import '../theme/app_theme.dart';
import 'formatters.dart';

class DiscoveryLiveCard extends StatelessWidget {
  const DiscoveryLiveCard({
    super.key,
    required this.show,
    required this.viewers,
    required this.onTap,
    this.device,
    this.price,
  });
  final LiveShow show;
  final Device? device;
  final int viewers;
  final double? price;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BrowseCardMedia(device: device, cover: show.coverPath),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black12,
                          Colors.transparent,
                          Colors.black87,
                        ],
                        stops: [0, .4, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: LoopColors.live,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        t('UŽIVO'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          show.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          viewers > 0
                              ? '${show.hostLabel} · $viewers'
                              : show.hostLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            price == null ? t('Uđi u prijenos') : formatCredits(price!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    ),
  );
}

/// Kartica prijenosa u mreži (2 stupca): naslovnica 3:4, oznaka UŽIVO,
/// gledatelji samo kad postoje, pa naslov i prodavač s avatarom.
class LiveGridCard extends StatelessWidget {
  const LiveGridCard({
    super.key,
    required this.show,
    required this.host,
    required this.viewers,
    required this.onTap,
    this.device,
    this.priceLabel,
    this.soon = false,
  });
  final LiveShow show;
  final AppUser? host;
  final Device? device;
  final int viewers;
  final String? priceLabel;
  final bool soon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        '${soon ? t('Uskoro') : t('Uživo')}: ${show.title}, ${show.hostLabel}',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BrowseCardMedia(device: device, cover: show.coverPath),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: soon ? Colors.black87 : LoopColors.live,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        soon ? t('USKORO') : '● ${t('UŽIVO')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (viewers > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.visibility_outlined,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$viewers',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (priceLabel != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          priceLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            show.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              UserAvatar(user: host, size: 24),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  host?.handle ?? show.hostLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: LoopColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
