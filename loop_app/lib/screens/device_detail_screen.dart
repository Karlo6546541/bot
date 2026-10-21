import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/trade_actions.dart';
import 'auction_detail_screen.dart';
import 'create_auction_screen.dart';

/// Detalji uređaja: veliki prikaz, specifikacije, izračun fee-a i akcija
/// (kupnja za uređaje iz Marketa, prodaja za vlastite).
class DeviceDetailScreen extends ConsumerWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});

  final String deviceId;

  static Future<void> open(BuildContext context, Device device) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DeviceDetailScreen(deviceId: device.id),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final device = state.deviceById(deviceId);
    final user = state.currentUser;

    // Uređaj je u međuvremenu obrisan (npr. u admin panelu).
    if (device == null || user == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Predmet više nije dostupan.')),
      );
    }

    final isMine = device.ownerId == user.id;
    final canBuy = device.isOnMarket && !isMine;
    final auction = state.activeAuctionFor(device.id);
    final cat = device.category;
    final fee = feeFor(device.price);
    final isFav = state.isFavorite(device.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(device.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (canBuy)
            IconButton(
              tooltip: isFav ? 'Ukloni iz favorita' : 'Dodaj u favorite',
              onPressed: () => toggleFavorite(ref, device),
              icon: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? const Color(0xFFFF5C8A) : null,
              ),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // Velika "hero" kartica u bojama kategorije.
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cat.color.withValues(alpha: 0.32),
                      LoopColors.surface,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(kRadius * 1.5),
                  border: Border.all(color: cat.color.withValues(alpha: 0.35)),
                  boxShadow: [
                    BoxShadow(
                      color: cat.color.withValues(alpha: 0.18),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ItemGallery(
                      // Ključ: nakon dodavanja/brisanja slike galerija kreće iznova.
                      key: ValueKey(device.imagePaths.join('|')),
                      device: device,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      device.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      device.model,
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      formatCredits(device.price),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              if (isMine) ...[
                const SizedBox(height: 12),
                _PhotoActions(device: device),
              ],
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    _Spec(
                      Icons.category_outlined,
                      'Kategorija',
                      cat.singular,
                      cat.color,
                    ),
                    _Spec(
                      Icons.verified_outlined,
                      'Stanje',
                      device.condition.label,
                      device.condition.color,
                    ),
                    _Spec(
                      Icons.person_outline,
                      'Vlasnik',
                      isMine ? 'Ti' : state.userLabel(device.ownerId),
                      null,
                    ),
                    _Spec(
                      Icons.schedule,
                      'Dodano',
                      formatDateTime(device.createdAt),
                      null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _Line('Cijena', formatCredits(device.price)),
                      _Line(
                        'Fee platforme (5%)',
                        '${isMine ? '−' : '+'} ${formatCredits(fee)}',
                      ),
                      const Divider(height: 20),
                      _Line(
                        isMine ? 'Dobivaš prodajom' : 'Ukupno plaćaš',
                        formatCredits(
                          isMine
                              ? sellPayout(device.price)
                              : buyTotal(device.price),
                        ),
                        bold: true,
                      ),
                      if (canBuy)
                        _Line('Tvoji krediti', formatCredits(user.credits)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (isMine && auction != null) ...[
                // Predmet je zaključan dok aukcija traje.
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: LoopColors.surfaceHover,
                    borderRadius: BorderRadius.circular(kRadius),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.gavel, color: LoopColors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Na aukciji · ${auction.bids.length} ponuda · '
                          'trenutno ${formatCredits(auction.currentPrice)}. '
                          'Predmet se ne može prodati dok aukcija traje.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      AuctionDetailScreen.open(context, auction.id),
                  icon: const Icon(Icons.gavel),
                  label: const Text('Pogledaj aukciju'),
                ),
              ] else if (isMine) ...[
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await confirmAndSell(context, ref, device);
                    if (ok && context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.sell_outlined),
                  label: const Text('Prodaj odmah'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () =>
                      CreateAuctionScreen.open(context, deviceId: device.id),
                  icon: const Icon(Icons.gavel),
                  label: const Text('Stavi na aukciju'),
                ),
              ] else if (canBuy)
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await confirmAndBuy(context, ref, device);
                    if (ok && context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Kupi odmah'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Spec extends StatelessWidget {
  const _Spec(this.icon, this.label, this.value, this.dot);
  final IconData icon;
  final String label;
  final String value;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: LoopColors.textSecondary),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: LoopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: bold ? LoopColors.textPrimary : LoopColors.textSecondary,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 17 : 14,
              color: bold ? LoopColors.accent : LoopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Upravljanje fotografijama vlastitog predmeta.
class _PhotoActions extends ConsumerWidget {
  const _PhotoActions({required this.device});
  final Device device;

  Future<void> _add(WidgetRef ref, {bool camera = false}) async {
    try {
      final n = await ref
          .read(appProvider.notifier)
          .addImages(device.id, camera: camera);
      if (n > 0) {
        showLoopSnackBar(
          n == 1 ? 'Fotografija dodana' : 'Dodano fotografija: $n',
        );
      }
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } catch (e) {
      showLoopSnackBar('Fotografiju nije moguće učitati: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(imageStoreProvider);
    final full = device.imagePaths.length >= maxImages;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fotografije (${device.imagePaths.length}/$maxImages)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final path in device.imagePaths)
                  _Thumb(
                    path: path,
                    device: device,
                    onRemove: () => ref
                        .read(appProvider.notifier)
                        .removeImage(device.id, path),
                  ),
                if (!full)
                  _AddTile(
                    icon: Icons.add_photo_alternate_outlined,
                    label: 'Galerija',
                    onTap: () => _add(ref),
                  ),
                if (!full && store.canUseCamera)
                  _AddTile(
                    icon: Icons.photo_camera_outlined,
                    label: 'Kamera',
                    onTap: () => _add(ref, camera: true),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.path,
    required this.device,
    required this.onRemove,
  });

  final String path;
  final Device device;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LocalPhoto(
                path: path,
                cacheWidth: 216,
                fallback: CategoryAvatar(category: device.category, size: 72),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: LoopColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: LoopColors.surfaceHover, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: LoopColors.textSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: LoopColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
