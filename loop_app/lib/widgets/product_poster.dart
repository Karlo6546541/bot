import 'package:flutter/material.dart';
import '../models/device.dart';
import '../theme/app_theme.dart';
import 'item_image.dart';
import 'vision_glass.dart';

/// Real product imagery with a quiet category silhouette when no photo exists.
class ProductPoster extends StatelessWidget {
  const ProductPoster({
    super.key,
    this.device,
    required this.title,
    this.price,
    this.status,
    this.onTap,
  });
  final Device? device;
  final String title;
  final String? price, status;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final d = device;
    final fallback = d == null
        ? ColoredBox(
            color: LoopColors.surfaceHover,
            child: Center(
              child: Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: LoopColors.textSecondary,
              ),
            ),
          )
        : ItemIllustration(category: d.category);
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Material(
        color: LoopColors.surface,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Semantics(
                image: true,
                label: title,
                child: d == null || d.imagePaths.isEmpty
                    ? fallback
                    : LocalPhoto(
                        path: d.imagePaths.first,
                        fallback: fallback,
                        cacheWidth: 800,
                      ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE6000000)],
                  ),
                ),
              ),
              if (price != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: VisionGlass(
                    dark: true,
                    opacity: .72,
                    radius: 99,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      price!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (status != null)
                      Text(
                        status!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD1D1D6),
                          fontSize: 11,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                        letterSpacing: -.4,
                        height: 1.15,
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
