import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/formatters.dart';
import '../widgets/community_widgets.dart';
import '../widgets/description_card.dart';
import '../widgets/item_image.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/trade_actions.dart';
import 'auction_detail_screen.dart';
import 'wishlists_screen.dart';
import 'create_auction_screen.dart';
import 'messages_screen.dart';
import 'public_profile_screen.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/user_avatar.dart';
import '../l10n/tr.dart';

/// Detalji uređaja: veliki prikaz, specifikacije, izračun fee-a i akcija
/// (kupnja za uređaje iz Marketa, prodaja za vlastite).
class DeviceDetailScreen extends ConsumerWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});

  final String deviceId;

  static Future<void> open(BuildContext context, Device device) {
    // Otvaranje oglasa broji se kao prikaz objave.
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(appProvider.notifier).recordView(device.id);
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceDetailScreen(deviceId: device.id),
      ),
    );
  }

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
    final price = isMine ? device.askPrice : state.priceForMe(device);
    final owner = state.userById(device.ownerId);
    final isFav = state.isFavorite(device.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(device.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (device.isForSale)
            ShareButton(
              url: publicLink(item: device.id),
              text: t('{0} za {1} na LOOP-u', [
                device.name,
                formatCredits(device.shownPrice),
              ]),
              tooltip: t('Podijeli oglas'),
            ),
          // Jedno srce: dodir = sviđa mi se (obavijest nudi spremanje u
          // listu); ostale radnje su u izborniku ⋮.
          if (!isMine && !user.isGuest)
            IconButton(
              key: const ValueKey('like-item'),
              tooltip: isFav ? t('Ukloni iz favorita') : t('Dodaj u favorite'),
              onPressed: () => toggleFavorite(ref, device, context: context),
              icon: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? const Color(0xFFFF5C8A) : null,
              ),
            ),
          if (!isMine && !user.isGuest)
            PopupMenuButton<String>(
              key: const ValueKey('item-menu'),
              tooltip: t('Više'),
              onSelected: (v) {
                if (v == 'save') {
                  showSaveToListSheet(context, ref, device);
                } else if (v == 'report' && owner != null) {
                  showReportSheet(
                    context,
                    ref,
                    targetType: 'device',
                    targetId: device.id,
                    targetLabel: '${device.name} ${device.model}',
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: const ValueKey('save-item'),
                  value: 'save',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bookmarks_outlined),
                    title: Text(t('Spremi u listu')),
                  ),
                ),
                if (owner != null)
                  PopupMenuItem(
                    key: const ValueKey('report-item'),
                    value: 'report',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.flag_outlined),
                      title: Text(t('Prijavi oglas')),
                    ),
                  ),
              ],
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
                    PriceTag(
                      device: device,
                      price: isMine ? device.askPrice : buyTotal(price),
                      basePrice: isMine ? null : device.shownBasePrice,
                      fontSize: 32,
                      center: true,
                    ),
                    if (device.isListed) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          t('🏷️ U Marketu'),
                          if (!device.isDigital && device.quantity > 1)
                            t('na zalihi: {0} kom', ['${device.quantity}']),
                          if (device.hasDiscount) discountLabel(device),
                        ].join(' · '),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: LoopColors.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    // Uz popust: najniža cijena u 30 dana (Omnibus).
                    if (device.hasDiscount && !isMine) ...[
                      const SizedBox(height: 4),
                      Text(
                        t('Najniža cijena u zadnjih 30 dana: {0}', [
                          formatCredits(
                            buyTotal(device.lowestPrice30(DateTime.now())),
                          ),
                        ]),
                        key: const ValueKey('lowest-30'),
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (device.isListed) ...[
                      const SizedBox(height: 6),
                      Text(
                        t('▶ {0} prikaza · ♥ {1}', [
                          '${state.viewsOf(device.id)}',
                          '${state.likesOf(device.id)}',
                        ]),
                        style: TextStyle(color: LoopColors.textSecondary),
                      ),
                    ],
                    if (owner != null &&
                        owner.isPromoted &&
                        device.isListed) ...[
                      const SizedBox(height: 6),
                      const PromotedBadge(),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              if (isMine && ref.read(imageStoreProvider).supported) ...[
                const SizedBox(height: 12),
                _PhotoActions(device: device),
              ],
              if (device.isDigital && device.file != null) ...[
                const SizedBox(height: 16),
                _DigitalFileCard(
                  device: device,
                  isMine: isMine,
                  purchased: state.hasPurchased(device.id),
                  buyers: state.buyersCount(device.id),
                ),
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
                    if (!device.isDigital)
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
                        subtitle: Align(
                          alignment: Alignment.centerLeft,
                          child: RatingBadge(
                            rating: state.ratingOf(owner.id),
                            compact: true,
                          ),
                        ),
                        trailing: UserHandle(
                          user: owner,
                          onTap: () =>
                              PublicProfileScreen.open(context, owner.id),
                        ),
                        onTap: () =>
                            PublicProfileScreen.open(context, owner.id),
                      ),
                    if (owner != null && !isMine && !user.isGuest)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t('{0} pratitelja · {1} prodaja', [
                                  '${state.followersOf(owner.id)}',
                                  '${state.salesCountOf(owner.id)}',
                                ]),
                                style: TextStyle(
                                  color: LoopColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            FollowButton(userId: owner.id, compact: true),
                          ],
                        ),
                      ),
                    // Svi prodavatelji su fizičke osobe — o tome ovise
                    // prava kupca.
                    if (owner != null && device.isListed && !isMine)
                      ListTile(
                        key: const ValueKey('seller-type'),
                        leading: Icon(
                          Icons.person_outline,
                          color: LoopColors.textSecondary,
                        ),
                        title: Text(t('Privatni prodavatelj (fizička osoba)')),
                        subtitle: Text(
                          t(
                            'Kupnja od fizičke osobe: zakonsko pravo na povrat od 14 dana ne vrijedi.',
                          ),
                        ),
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
                      if (isMine) ...[
                        _Line(
                          t('Kupci vide cijenu'),
                          formatCredits(buyTotal(price)),
                        ),
                        const Divider(height: 20),
                        _Line(
                          t('Dobivaš prodajom'),
                          formatCredits(sellPayout(price)),
                          bold: true,
                        ),
                      ] else
                        _Line(
                          t('Cijena'),
                          formatCredits(buyTotal(price)),
                          bold: true,
                        ),
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
                  SellerBargainsCard(device: device),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => showListDialog(context, ref, device),
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(
                            device.isDigital
                                ? t('Promijeni cijenu')
                                : t('Cijena i zaliha'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('discount'),
                          onPressed: () =>
                              showDiscountSheet(context, ref, device),
                          icon: const Icon(Icons.local_offer_outlined),
                          label: Text(
                            device.hasDiscount
                                ? t('Popust {0}', [discountLabel(device)])
                                : t('Popust'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
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
                if (!device.isListed && !device.isDigital) ...[
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
              ] else if (device.isDigital && state.hasPurchased(device.id)) ...[
                FilledButton.icon(
                  key: const ValueKey('download-file'),
                  onPressed: () => downloadDigital(context, ref, device),
                  icon: const Icon(Icons.download),
                  label: Text(t('Preuzmi datoteku')),
                ),
              ] else if (canBuy) ...[
                FilledButton.icon(
                  key: const ValueKey('buy-now'),
                  onPressed: () async {
                    final ok = await confirmAndBuy(context, ref, device);
                    // Digitalni proizvod: ostani na ekranu (preuzimanje).
                    if (ok && !device.isDigital && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  icon: Icon(
                    device.isDigital
                        ? Icons.download_for_offline_outlined
                        : Icons.shopping_bag_outlined,
                  ),
                  label: Text(
                    device.isDigital ? t('Kupi i preuzmi') : t('Kupi odmah'),
                  ),
                ),
                if (device.isListed && owner != null) ...[
                  const SizedBox(height: 10),
                  BuyerBargainCard(device: device),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('message-seller'),
                          onPressed: () => ChatScreen.open(
                            context,
                            owner.id,
                            deviceId: device.id,
                          ),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: Text(t('Pošalji poruku')),
                        ),
                      ),
                      if (!device.isDigital) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const ValueKey('offer-swap'),
                            onPressed: () =>
                                showSwapSheet(context, ref, device),
                            icon: const Icon(Icons.swap_horiz),
                            label: Text(t('Ponudi zamjenu')),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Datoteka digitalnog proizvoda: naziv, veličina, preuzimanje/zamjena.
class _DigitalFileCard extends ConsumerWidget {
  const _DigitalFileCard({
    required this.device,
    required this.isMine,
    required this.purchased,
    required this.buyers,
  });

  final Device device;
  final bool isMine;
  final bool purchased;
  final int buyers;

  Future<void> _replace(BuildContext context, WidgetRef ref) async {
    final store = ref.read(fileStoreProvider);
    try {
      final f = await store.pick();
      if (f == null || !context.mounted) return;
      final error = store.validate(f);
      if (error != null) {
        showLoopSnackBar(error, error: true);
        return;
      }
      await runWithLoading(
        context,
        () => ref.read(appProvider.notifier).replaceFile(device.id, f),
        successMessage: t('Nova datoteka je učitana'),
      );
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = device.file!;
    return Card(
      color: LoopColors.sky,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: LoopColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    f.extension.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: LoopColors.info,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        t('{0} · digitalni proizvod', [f.sizeLabel]),
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isMine
                  ? t(
                      'Kupaca: {0}. Svaki kupac plaća cijenu + 2%, a ti dobivaš punu cijenu.',
                      [buyers],
                    )
                  : purchased
                  ? t(
                      'Kupio si ovaj proizvod — datoteku možeš preuzeti kad god želiš.',
                    )
                  : t('Datoteka se preuzima odmah nakon plaćanja.'),
            ),
            if (isMine) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => downloadDigital(context, ref, device),
                    icon: const Icon(Icons.download),
                    label: Text(t('Preuzmi')),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('replace-file'),
                    onPressed: () => _replace(context, ref),
                    icon: const Icon(Icons.upload_file),
                    label: Text(t('Zamijeni datoteku')),
                  ),
                ],
              ),
            ],
          ],
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

/// "U Marketu za X — ti dobivaš punu cijenu".
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(
                    'U Marketu: kupci vide cijenu {0}. Kad netko kupi, dobivaš {1}, a predmet prelazi kupcu.',
                    [formatCredits(buyTotal(p)), formatCredits(sellPayout(p))],
                  ),
                ),
                if (device.hasStock)
                  Text(
                    t('Na zalihi: {0} kom — svaka kupnja skida jedan.', [
                      '${device.quantity}',
                    ]),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
              ],
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
