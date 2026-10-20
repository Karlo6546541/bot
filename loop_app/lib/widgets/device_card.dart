import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/app_theme.dart';
import 'category_style.dart';
import 'formatters.dart';

/// Kartica uređaja s jednim akcijskim gumbom ("Prodaj odmah" / "Kupi odmah").
/// Dodir na karticu otvara detalje ([onTap]); [onFavorite] prikazuje srce.
class DeviceCard extends StatefulWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.actionLabel,
    required this.onAction,
    this.actionIcon,
    this.onTap,
    this.isFavorite = false,
    this.onFavorite,
  });

  final Device device;
  final String actionLabel;
  final IconData? actionIcon;
  final VoidCallback onAction;
  final VoidCallback? onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final catColor = d.category.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.015 : 1,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _hover ? LoopColors.surfaceHover : LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(
              color: catColor.withValues(alpha: _hover ? 0.55 : 0.18),
            ),
            boxShadow: [
              if (_hover)
                BoxShadow(
                  color: catColor.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              child: Stack(
                children: [
                  // Diskretni sjaj boje kategorije u kutu kartice.
                  Positioned(
                    right: -40,
                    top: -40,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            catColor.withValues(alpha: 0.16),
                            catColor.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _content(d),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(Device d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Hero(
              tag: 'device-${d.id}',
              child: CategoryAvatar(category: d.category),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    d.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: LoopColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (widget.onFavorite != null)
              IconButton(
                tooltip: widget.isFavorite ? 'Ukloni iz favorita' : 'Favorit',
                onPressed: widget.onFavorite,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, a) =>
                      ScaleTransition(scale: a, child: child),
                  child: Icon(
                    widget.isFavorite ? Icons.favorite : Icons.favorite_border,
                    key: ValueKey(widget.isFavorite),
                    color: widget.isFavorite
                        ? const Color(0xFFFF5C8A)
                        : LoopColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _Chip(label: d.condition.label, dot: d.condition.color),
            _Chip(label: d.category.singular, dot: d.category.color),
          ],
        ),
        const Spacer(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatCredits(d.price),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: widget.onAction,
              icon: Icon(widget.actionIcon ?? Icons.bolt, size: 18),
              label: Text(widget.actionLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.dot});
  final String label;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: LoopColors.background.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: LoopColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Responzivna mreža kartica: jedan stupac na mobitelu, više na desktopu.
/// Redovi se prilagođavaju visini sadržaja (nema fiksne visine kartice),
/// pa raspored radi i s većim sistemskim fontom.
class DeviceGrid extends StatelessWidget {
  const DeviceGrid({
    super.key,
    required this.devices,
    required this.itemBuilder,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 96),
  });

  final List<Device> devices;
  final Widget Function(BuildContext, Device) itemBuilder;
  final EdgeInsets padding;

  static const _maxCardWidth = 420.0;
  static const _spacing = 12.0;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: padding,
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final columns = ((width + _spacing) / (_maxCardWidth + _spacing))
              .ceil()
              .clamp(1, 6);
          final rows = (devices.length / columns).ceil();
          return SliverList.separated(
            itemCount: rows,
            separatorBuilder: (_, _) => const SizedBox(height: _spacing),
            itemBuilder: (context, row) {
              final cells = <Widget>[];
              for (var c = 0; c < columns; c++) {
                if (c > 0) cells.add(const SizedBox(width: _spacing));
                final i = row * columns + c;
                cells.add(
                  Expanded(
                    child: i < devices.length
                        ? FadeSlideIn(
                            // Ključ po uređaju: animacija se pokreće samo za nove kartice.
                            key: ValueKey(devices[i].id),
                            index: i,
                            child: itemBuilder(context, devices[i]),
                          )
                        : const SizedBox.shrink(),
                  ),
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: cells,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
