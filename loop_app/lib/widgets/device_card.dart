import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/app_theme.dart';
import 'device_icon.dart';
import 'formatters.dart';

/// Kartica uređaja s jednim akcijskim gumbom ("Prodaj odmah" / "Kupi odmah").
class DeviceCard extends StatefulWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.actionLabel,
    required this.onAction,
    this.actionIcon,
  });

  final Device device;
  final String actionLabel;
  final IconData? actionIcon;
  final VoidCallback onAction;

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final accent = Theme.of(context).colorScheme.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hover ? LoopColors.surfaceHover : LoopColors.surface,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(iconForCategory(d.category), color: accent),
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
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(label: d.condition.label),
                _Chip(label: d.category.label),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatCredits(d.price),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
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
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: LoopColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: LoopColors.textSecondary, fontSize: 12),
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
                        ? itemBuilder(context, devices[i])
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
