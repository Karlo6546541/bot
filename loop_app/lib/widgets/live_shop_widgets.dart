import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../providers/app_state.dart';
import '../screens/auctions_screen.dart' show BrowseCardMedia;
import '../theme/app_theme.dart';
import 'formatters.dart';
import 'item_image.dart';

/// Product rows keep browsing quiet; payment still happens in the item flow.
class ShopProductRow extends StatelessWidget {
  const ShopProductRow({
    super.key,
    required this.device,
    required this.onTap,
    this.price,
  });
  final Device device;
  final VoidCallback onTap;
  final double? price;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ItemThumb(device: device, size: 68),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    formatCredits(price ?? device.askPrice),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right,
              color: LoopColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}

/// One featured broadcast is the entry point to live shopping.
class LiveShopFeature extends StatelessWidget {
  const LiveShopFeature({
    super.key,
    required this.show,
    required this.host,
    required this.onTap,
    required this.viewers,
    this.device,
  });
  final LiveShow show;
  final AppUser? host;
  final Device? device;
  final int viewers;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: t('Uđi u live'),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: MediaQuery.sizeOf(context).width >= 840
              ? 2.8
              : 16 /
                    (10 +
                        6 *
                            (MediaQuery.textScalerOf(context).scale(14) / 14 -
                                    1)
                                .clamp(0, 2)),
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
                      Colors.black26,
                      Colors.transparent,
                      Colors.black87,
                    ],
                    stops: [0, .3, 1],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                top: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: LoopColors.live,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    t('UŽIVO'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            host?.shopTitle ?? show.hostLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            show.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                              letterSpacing: -.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            t('{0} gledatelja', ['$viewers']),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: const Icon(
                        Icons.arrow_forward,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class LiveShopRow extends StatelessWidget {
  const LiveShopRow({
    super.key,
    required this.show,
    required this.subtitle,
    required this.onTap,
    this.device,
  });
  final LiveShow show;
  final String subtitle;
  final Device? device;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: BrowseCardMedia(device: device, cover: show.coverPath),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    show.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: LoopColors.textSecondary),
          ],
        ),
      ),
    ),
  );
}

/// Products assigned to a live or active auction are not separate shop offers.
Set<String> liveShopReservedIds(AppState state) => {
  for (final (_, live) in state.activeLives)
    for (final lot in live.lots) lot.lot.deviceId,
  for (final auction in state.activeAuctions) auction.deviceId,
};

List<Device> liveShopProducts(AppState state, String hostId) {
  final reserved = liveShopReservedIds(state);
  return state
      .listingsOf(hostId)
      .where((d) => !reserved.contains(d.id))
      .toList();
}
