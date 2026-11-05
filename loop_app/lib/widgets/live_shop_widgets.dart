import '../config/design_variant.dart';
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
import 'vision_glass.dart';

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
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: LoopColors.glass.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: LoopColors.glassBorder),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
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
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: LoopColors.gold,
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

/// The live stage follows the supplied VisionOS reference.
class LiveShopFeature extends StatelessWidget {
  const LiveShopFeature({
    super.key,
    required this.show,
    required this.host,
    required this.onTap,
    required this.viewers,
    this.price,
    this.device,
  });
  final LiveShow show;
  final AppUser? host;
  final Device? device;
  final int viewers;
  final double? price;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    if (kSimpleDesign) {
      return StageFeatureCard(
        media: BrowseCardMedia(device: device, cover: show.coverPath),
        title: show.title,
        subtitle: price == null
            ? host?.shopTitle ?? show.hostLabel
            : '${t('Trenutna ponuda')}: ${formatCredits(price!)}',
        actionLabel: t('Uđi u prijenos'),
        semanticsLabel: t('Uđi u live'),
        onTap: onTap,
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Semantics(
      button: true,
      label: t('Uđi u live'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Container(
          height:
              (width >= 840
                  ? 440.0
                  : width < 350
                  ? 380.0
                  : 460.0) +
              100 * (scale - 1).clamp(0, 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: LoopColors.glassBorder),
          ),
          clipBehavior: Clip.antiAlias,
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
                      Colors.black38,
                      Colors.transparent,
                      Color(0xF2000000),
                    ],
                    stops: [0, .35, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: LoopColors.live,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${t('UŽIVO')} · $viewers',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: VisionGlass(
                              radius: 99,
                              dark: true,
                              blur: false,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Text(
                                host?.handle ?? show.hostLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      show.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        height: 1.12,
                        letterSpacing: -.7,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      host?.shopTitle ?? show.hostLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .96),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        t('Uđi u prijenos'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LiveShopMini extends StatelessWidget {
  const LiveShopMini({
    super.key,
    required this.show,
    this.device,
    required this.viewers,
    required this.onTap,
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
      borderRadius: BorderRadius.circular(kSimpleDesign ? 28 : 24),
      child: Container(
        height:
            (kSimpleDesign ? 250.0 : 230.0) +
            64 *
                (MediaQuery.textScalerOf(context).scale(14) / 14 - 1).clamp(
                  0,
                  2,
                ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kSimpleDesign ? 28 : 24),
          border: Border.all(
            color: kSimpleDesign
                ? Colors.white.withValues(alpha: .20)
                : LoopColors.glassBorder,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BrowseCardMedia(device: device, cover: show.coverPath),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black26, Colors.transparent, Colors.black87],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: LoopColors.live,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '● $viewers',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    show.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    kSimpleDesign && price != null
                        ? t('Sada: {0}', [formatCredits(price!)])
                        : show.hostLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFFD60A),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                borderRadius: BorderRadius.circular(14),
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

/// One photographic stage, shared by real live shows and the shop fallback.
class StageFeatureCard extends StatelessWidget {
  const StageFeatureCard({
    super.key,
    required this.media,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    this.semanticsLabel,
  });
  final Widget media;
  final String title;
  final String subtitle;
  final String actionLabel;
  final String? semanticsLabel;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(36),
        child: Container(
          height:
              (width >= 840
                  ? 440.0
                  : width < 350
                  ? 380.0
                  : 430.0) +
              120 * (scale - 1).clamp(0, 2),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: Colors.white.withValues(alpha: .20)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              media,
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x18000000),
                      Color(0xF51C1C1E),
                    ],
                    stops: [0, .35, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .96),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        actionLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
