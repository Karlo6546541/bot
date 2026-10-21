import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/formatters.dart';
import '../widgets/description_card.dart';
import '../widgets/item_image.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/trade_actions.dart';
import 'auction_detail_screen.dart';
import 'create_auction_screen.dart';
import 'public_profile_screen.dart';
import '../widgets/user_avatar.dart';
import '../l10n/tr.dart';

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
        body: Center(child: Text(t('Predmet više nije dostupan.'))),
      );
    }

    final isMine = device.ownerId == user.id;
    final canBuy = device.isForSale && !isMine;
    final auction = state.activeAuctionFor(device.id);
    final cat = device.category;
    // Kupac vidi cijenu iz Marketa; vlasnik vrijednost i isplatu.
    final price = isMine ? device.price : device.askPrice;
    final fee = feeFor(price);
    final owner = state.userById(device.ownerId);
    final isFav = state.isFavorite(device.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(device.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (canBuy)
            IconButton(
              tooltip: isFav ? t('Ukloni iz favorita') : t('Dodaj u favorite'),
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
                      formatCredits(isMine ? device.askPrice : price),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (device.isListed) ...[
                      const SizedBox(height: 6),
                      Text(
                        t('🏷️ U Marketu'),
                        style: TextStyle(
                          color: LoopColors.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              if (isMine && ref.read(imageStoreProvider).supported) ...[
                const SizedBox(height: 12),
                _PhotoActions(device: device),
              ],
              if (device.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                DescriptionCard(text: device.description),
              ],
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    _Spec(
                      Icons.category_outlined,
                      t('Kategorija'),
                      cat.singular,
                      cat.color,
                    ),
                    _Spec(
                      Icons.verified_outlined,
                      t('Stanje'),
                      device.condition.label,
                      device.condition.color,
                    ),
                    if (isMine || owner == null)
                      _Spec(
                        Icons.person_outline,
                        device.isListed || owner == null
                            ? t('Prodavatelj')
                            : t('Vlasnik'),
                        isMine ? t('Ti') : state.userLabel(device.ownerId),
                        null,
                      )
                    else
                      ListTile(
                        leading: UserAvatar(user: owner, size: 32),
                        title: Text(
                          device.isListed ? t('Prodavatelj') : t('Vlasnik'),
                        ),
                        trailing: UserHandle(
                          user: owner,
                          onTap: () =>
                              PublicProfileScreen.open(context, owner.id),
                        ),
                        onTap: () =>
                            PublicProfileScreen.open(context, owner.id),
                      ),
                    _Spec(
                      Icons.schedule,
                      t('Dodano'),
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
                      _Line(
                        isMine ? t('Vrijednost') : t('Cijena'),
                        formatCredits(price),
                      ),
                      _Line(
                        t('Fee platforme (5%)'),
                        '${isMine ? '−' : '+'} ${formatCredits(fee)}',
                      ),
                      const Divider(height: 20),
                      _Line(
                        isMine ? t('Dobivaš prodajom') : t('Ukupno plaćaš'),
                        formatCredits(
                          isMine ? sellPayout(price) : buyTotal(price),
                        ),
                        bold: true,
                      ),
                      if (canBuy)
                        _Line(t('Tvoji krediti'), formatCredits(user.credits)),
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
                          t(
                            'Na aukciji · {0} ponuda · trenutno {1}. Predmet se ne može prodati dok aukcija traje.',
                            [
                              auction.bids.length,
                              formatCredits(auction.currentPrice),
                            ],
                          ),
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
                  label: Text(t('Pogledaj aukciju')),
                ),
              ] else if (isMine) ...[
                if (device.isListed) ...[
                  _ListingInfo(device: device),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => showListDialog(context, ref, device),
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(t('Promijeni cijenu')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('unlist'),
                          onPressed: () => runWithLoading(
                            context,
                            () => ref
                                .read(appProvider.notifier)
                                .unlist(device.id),
                            successMessage: t('Uklonjeno iz Marketa'),
                          ),
                          icon: const Icon(Icons.remove_shopping_cart_outlined),
                          label: Text(t('Ukloni iz Marketa')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  FilledButton.icon(
                    onPressed: () => showListDialog(context, ref, device),
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(t('Objavi u Marketu')),
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirmAndSell(context, ref, device);
                    if (ok && context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.sell_outlined),
                  label: Text(t('Prodaj odmah LOOP-u')),
                ),
                if (!device.isListed) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () =>
                        CreateAuctionScreen.open(context, deviceId: device.id),
                    icon: const Icon(Icons.gavel),
                    label: Text(t('Stavi na aukciju')),
                  ),
                ],
                const SizedBox(height: 10),
                TextButton.icon(
                  key: const ValueKey('delete-item'),
                  style: TextButton.styleFrom(
                    foregroundColor: LoopColors.error,
                  ),
                  onPressed: () => _delete(context, ref, device),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t('Obriši predmet')),
                ),
              ] else if (canBuy)
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await confirmAndBuy(context, ref, device);
                    if (ok && context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(t('Kupi odmah')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _delete(BuildContext context, WidgetRef ref, Device d) async {
  final ok = await confirmDialog(
    context,
    title: t('Obrisati predmet?'),
    message: t(
      '"{0}" bit će trajno uklonjen iz tvog portfolija{1}. Ovo se ne može poništiti.',
      [d.name, d.isListed ? t(' i iz Marketa') : ''],
    ),
    confirmLabel: t('Obriši'),
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  final done = await runWithLoading(
    context,
    () => ref.read(appProvider.notifier).deleteMyDevice(d.id),
    successMessage: t('Predmet obrisan'),
  );
  if (done && context.mounted) Navigator.pop(context);
}

/// "U Marketu za X — kupac plaća X + 5%, ti dobivaš X − 5%".
class _ListingInfo extends StatelessWidget {
  const _ListingInfo({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context) {
    final p = device.askPrice;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LoopColors.mint,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Row(
        children: [
          const Text('🏷️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t(
                'U Marketu za {0}. Kad netko kupi, dobivaš {1} (− 5% fee), a predmet prelazi kupcu.',
                [formatCredits(p), formatCredits(sellPayout(p))],
              ),
            ),
          ),
        ],
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
          n == 1 ? t('Fotografija dodana') : t('Dodano fotografija: {0}', [n]),
        );
      }
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } catch (e) {
      showLoopSnackBar(
        t('Fotografiju nije moguće učitati: {0}', [e]),
        error: true,
      );
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
              t('Fotografije ({0}/{1})', [device.imagePaths.length, maxImages]),
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
                if (!full && store.canUseCamera)
                  _AddTile(
                    icon: Icons.photo_camera_outlined,
                    label: t('Uslikaj'),
                    onTap: () => _add(ref, camera: true),
                  ),
                if (!full)
                  _AddTile(
                    icon: Icons.add_photo_alternate_outlined,
                    label: t('Galerija'),
                    onTap: () => _add(ref),
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
            child: GestureDetector(
              onTap: () => PhotoViewer.open(
                context,
                device.imagePaths,
                initial: device.imagePaths.indexOf(path),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LocalPhoto(
                  path: path,
                  cacheWidth: 216,
                  fallback: CategoryAvatar(category: device.category, size: 72),
                ),
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
