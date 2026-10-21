import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/app_theme.dart';
import 'category_style.dart';
import 'item_image.dart';
import 'formatters.dart';
import '../l10n/tr.dart';

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
    this.badge,
    this.promoted = false,
  });

  final Device device;
  final String actionLabel;
  final IconData? actionIcon;
  final VoidCallback onAction;
  final VoidCallback? onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;

  /// Kratka oznaka (npr. prodavatelj "@ana" ili "U Marketu").
  final String? badge;

  /// Prodavatelj ima plaćeno isticanje (oznaka ⭐).
  final bool promoted;

  String? get _badgeText =>
      badge == null ? null : (promoted ? '⭐ $badge' : badge);

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
        scale: _hover ? 1.02 : 1,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          clipBehavior: Clip.antiAlias,
          // Bijela kartica s mekom sjenom; pri prelasku mišem se "podigne"
          // i dobije obrub u boji kategorije.
          decoration: BoxDecoration(
            color: LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(
              color: _hover ? catColor : LoopColors.surfaceHover,
              width: 1.5,
            ),
            boxShadow: [
              ...LoopColors.softShadow,
              if (_hover)
                BoxShadow(
                  color: catColor.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              // Na mobitelu pločica sa slikom (2 stupca), inače široka kartica.
              child: isCompactGrid(context)
                  ? _tile(d)
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: _content(d),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Kompaktna pločica: slika gore, naziv, cijena i akcija ispod.
  Widget _tile(Device d) {
    final photo = d.imagePaths.isEmpty
        ? ItemIllustration(category: d.category, iconSize: 40)
        : LocalPhoto(
            path: d.imagePaths.first,
            cacheWidth: 480,
            fallback: ItemIllustration(category: d.category, iconSize: 40),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            AspectRatio(aspectRatio: 1.15, child: photo),
            if (widget.onFavorite != null)
              Positioned(
                top: 6,
                right: 6,
                child: Material(
                  color: LoopColors.surface.withValues(alpha: 0.9),
                  shape: const CircleBorder(),
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: widget.isFavorite
                        ? t('Ukloni iz favorita')
                        : t('Favorit'),
                    onPressed: widget.onFavorite,
                    icon: Icon(
                      widget.isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      size: 20,
                      color: widget.isFavorite
                          ? const Color(0xFFE5486F)
                          : LoopColors.textSecondary,
                    ),
                  ),
                ),
              ),
            Positioned(left: 8, bottom: 8, child: _conditionChip(d)),
            if (d.hasDiscount)
              Positioned(right: 8, bottom: 8, child: _discount(d)),
            if (widget._badgeText != null)
              Positioned(
                left: 8,
                top: 8,
                right: widget.onFavorite != null ? 52 : 8,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _Badge(widget._badgeText!),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                d.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                d.model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _price(d, 16),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: widget.onAction,
                icon: Icon(widget.actionIcon ?? Icons.bolt, size: 16),
                label: FittedBox(child: Text(widget.actionLabel)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(
                    fontFamily: kFontFamily,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _content(Device d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ItemThumb(device: d, size: 52),
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
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (widget.onFavorite != null)
              IconButton(
                tooltip: widget.isFavorite
                    ? t('Ukloni iz favorita')
                    : t('Favorit'),
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
            _conditionChip(d),
            _Chip(label: d.category.singular, dot: d.category.color),
            if (widget._badgeText != null) _Badge(widget._badgeText!),
            if (d.hasDiscount) _discount(d),
            if (d.isListed && d.quantity > 1)
              _Chip(
                label: t('{0} kom', ['${d.quantity}']),
                dot: LoopColors.info,
              ),
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
                child: _price(d, 18),
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
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Uski ekran (mobitel): predmeti se prikazuju kao pločice u 2 stupca.
bool isCompactGrid(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600;

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
          // Mobitel: 2 stupca pločica; šire: kartice do 420 px.
          final columns = isCompactGrid(context)
              ? 2
              : ((width + _spacing) / (_maxCardWidth + _spacing)).ceil().clamp(
                  1,
                  6,
                );
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

/// Istaknuta oznaka na kartici (prodavatelj / "U Marketu").
class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: LoopColors.accent,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: LoopColors.onAccent,
        fontWeight: FontWeight.w800,
        fontSize: 11,
      ),
    ),
  );
}

/// Stanje predmeta, a za digitalni proizvod vrsta datoteke ("⬇ STL").
Widget _conditionChip(Device d) => d.isDigital
    ? _Chip(
        label: '⬇ ${(d.file?.extension ?? '').toUpperCase()}',
        dot: d.category.color,
      )
    : _Chip(label: d.condition.label, dot: d.condition.color);

/// Cijena; na popustu crvena uz prekriženu redovnu cijenu.
Widget _price(Device d, double size) {
  final cut = d.hasDiscount;
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(
        formatCredits(d.askPrice),
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: size,
          color: cut ? LoopColors.error : null,
        ),
      ),
      if (cut) ...[
        const SizedBox(width: 6),
        Text(
          formatCredits(d.basePrice),
          style: TextStyle(
            fontSize: size * 0.7,
            color: LoopColors.textSecondary,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    ],
  );
}

Widget _discount(Device d) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
  decoration: BoxDecoration(
    color: LoopColors.error,
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    '−${d.discountPercent}%',
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w900,
      fontSize: 11,
    ),
  ),
);
