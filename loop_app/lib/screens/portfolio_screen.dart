import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../models/delivery.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/stories.dart';
import '../widgets/device_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/feed.dart';
import '../widgets/formatters.dart';
import 'auction_detail_screen.dart';
import 'seller_screens.dart';
import 'deliveries_screen.dart';
import 'add_device_screen.dart';
import 'device_detail_screen.dart';
import '../l10n/tr.dart';
import '../services/live_service.dart';

/// Početna: stanje, dostave u tijeku, priče, objave i trgovine.
/// Moji predmeti (grafikon, raspodjela, popis) su na [MyItemsScreen].
class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key, required this.onGoToMarket});

  final VoidCallback onGoToMarket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final user = state.currentUser;
    if (user == null) return const SizedBox.shrink();

    final devices = state.myDevices;
    final total = state.totalValueOf(user);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _CreditsHero(
              name: user.name.isNotEmpty
                  ? user.name.split(' ').first
                  : user.handle,
              credits: user.credits,
              totalValue: total,
              deviceCount: devices.length,
              onPayout: () => showPayoutDialog(context, ref),
            ),
          ),
        ),
        if (state.myOpenDeliveries.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _DeliveryBanner(deliveries: state.myOpenDeliveries),
            ),
          ),
        // Priče (24 h) kao na Instagramu.
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: StoriesRow(),
          ),
        ),
        // Feed odmah ispod stanja i brzih akcija: objave (swipe kao TikTok)
        // i trgovine za tebe.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: HomeFeed(onGoToMarket: onGoToMarket),
          ),
        ),
        if (state.showHowItWorks)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _HowItWorks(),
            ),
          ),
      ],
    );
  }
}

/// Moji predmeti — jednostavno: filtri (Sve · Na prodaji · Nije na prodaji ·
/// Kupljeno) i popis, a svaki predmet ima jedan jasan gumb.
class MyItemsScreen extends StatelessWidget {
  const MyItemsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const MyItemsScreen()));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t('Moji predmeti')),
      actions: [
        IconButton(
          key: const ValueKey('my-items-add'),
          tooltip: t('Dodaj predmet'),
          onPressed: () => AddDeviceScreen.open(context),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: const MyItemsView(),
  );
}

/// Popis mojih predmeta s filtrima (i u kartici Moje → Prodajem).
class MyItemsView extends ConsumerStatefulWidget {
  const MyItemsView({super.key});

  @override
  ConsumerState<MyItemsView> createState() => _MyItemsViewState();
}

/// Gdje je moj predmet: spremljen (čeka prodaju), Kupi odmah, na aukciji
/// ili u liveu.
enum ItemStatus {
  draft('💾 Spremljeno'),
  buyNow('🏷️ Kupi odmah'),
  auction('⏱ Na aukciji'),
  live('🔴 U liveu');

  const ItemStatus(this._label);
  final String _label;
  String get label => t(_label);
}

class _MyItemsViewState extends ConsumerState<MyItemsView> {
  /// Filter stanja (`null` = sve).
  ItemStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final storage = ref.read(storageProvider);
    final user = state.currentUser;
    if (user == null) return const SizedBox.shrink();
    ItemStatus statusOf(Device d) => state.activeAuctionFor(d.id) != null
        ? ItemStatus.auction
        : LiveService.isLocked(storage, d.id)
        ? ItemStatus.live
        : d.isListed
        ? ItemStatus.buyNow
        : ItemStatus.draft;
    // Kupljeno: Kupi odmah, osvojeno na aukciji ili u liveu (ima pošiljku).
    final boughtIds = {for (final x in state.myDeliveries) x.deviceId};
    bool bought(Device d) =>
        d.ownerId != user.id ||
        boughtIds.contains(d.id) ||
        state.hasPurchased(d.id);
    // Kupljene stvari su portfolio u "Kupljeno"; ovdje samo ako ih je
    // korisnik sam ponovno stavio na prodaju.
    final own = [
      for (final d in state.myDevices)
        if (d.ownerId == user.id &&
            (!bought(d) || statusOf(d) != ItemStatus.draft))
          d,
    ];
    final counts = {
      for (final st in ItemStatus.values)
        st: own.where((d) => statusOf(d) == st).length,
    };
    final list = _filter == null
        ? own
        : own.where((d) => statusOf(d) == _filter).toList();

    Widget chip(ItemStatus? st, String label, int n) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        key: ValueKey('my-items-${st?.name ?? 'all'}'),
        label: Text('$label ($n)'),
        selected: _filter == st,
        onSelected: (_) => setState(() => _filter = st),
      ),
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Objašnjenje u jednoj rečenici + novi predmet.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t(
                          'Spremljeni predmeti čekaju — stavi ih na Kupi odmah, aukciju ili u live.',
                        ),
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      key: const ValueKey('my-items-new'),
                      onPressed: () => AddDeviceScreen.open(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(t('Novi predmet')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      chip(null, t('Sve'), own.length),
                      for (final st in ItemStatus.values)
                        chip(st, st.label, counts[st]!),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.inventory_2_outlined,
              title: own.isEmpty
                  ? t('Još ništa ne prodaješ')
                  : t('Ovdje trenutno nema predmeta'),
              message: t(
                'Dodaj predmet — spremi ga, pa ga stavi na Kupi odmah, aukciju ili u live.',
              ),
              action: FilledButton.icon(
                key: const ValueKey('my-items-add-empty'),
                onPressed: () => AddDeviceScreen.open(context),
                icon: const Icon(Icons.add),
                label: Text(t('Novi predmet')),
              ),
            ),
          )
        else
          DeviceGrid(
            devices: list,
            itemBuilder: (context, d) {
              final st = statusOf(d);
              final auction = state.activeAuctionFor(d.id);
              // Jedan gumb po stanju: spremljeno → Prodaj (Kupi odmah,
              // aukcija ili live na detaljima), aukcija → aukcija.
              return DeviceCard(
                device: d,
                actionLabel: switch (st) {
                  ItemStatus.draft => t('Prodaj'),
                  ItemStatus.auction => t('Aukcija'),
                  ItemStatus.live => t('U liveu'),
                  ItemStatus.buyNow => t('Detalji'),
                },
                actionIcon: switch (st) {
                  ItemStatus.draft => Icons.sell_outlined,
                  ItemStatus.auction => Icons.gavel,
                  ItemStatus.live => Icons.videocam,
                  ItemStatus.buyNow => Icons.info_outline,
                },
                onAction: auction != null
                    ? () => AuctionDetailScreen.open(context, auction.id)
                    : () => DeviceDetailScreen.open(context, d),
                onTap: () => DeviceDetailScreen.open(context, d),
                sellerView: true,
                showPrice: st != ItemStatus.draft,
                badge: st.label,
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

class _CreditsHero extends StatelessWidget {
  const _CreditsHero({
    required this.name,
    required this.credits,
    required this.totalValue,
    required this.deviceCount,
    required this.onPayout,
  });

  final VoidCallback onPayout;
  final String name;
  final double credits;
  final double totalValue;
  final int deviceCount;

  /// Kompaktna kartica: stanje lijevo, gumb za uplatu desno.
  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius * 1.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [LoopColors.peach, LoopColors.sunny],
        ),
        boxShadow: LoopColors.softShadow,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -60,
            child: _Glow(color: LoopColors.lilac, size: 160),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('Bok, {0} 👋 · zarada za isplatu', [name]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      // Stanje se animira pri svakoj promjeni.
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: credits),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatCredits(value),
                            key: const ValueKey('credits-balance'),
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.8,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ),
                      // Dodir otvara Moje predmete.
                      InkWell(
                        key: const ValueKey('open-my-items'),
                        onTap: () => MyItemsScreen.open(context),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                t('Ukupno {0} · {1} {2}{3}', [
                                  formatCredits(totalValue),
                                  deviceCount,
                                  deviceCount == 1
                                      ? t('predmet')
                                      : t('predmeta'),
                                  '',
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: LoopColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: LoopColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Zarada od prodaja ide na IBAN (novac kupaca ne držimo).
                FilledButton.icon(
                  key: const ValueKey('payout'),
                  onPressed: credits > 0 ? onPayout : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.account_balance_outlined, size: 18),
                  label: Text(t('Isplati')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kratko objašnjenje kako Subhasto radi (može se zatvoriti).
class _HowItWorks extends ConsumerWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = [
      (
        '1',
        '📸',
        t('Dodaj predmet'),
        t('Uslikaj stvar koju više ne koristiš.'),
      ),
      (
        '2',
        '🔁',
        t('Otvori svoj webshop'),
        t(
          'Svaki račun je trgovina: objavi po svojoj cijeni ili na aukciji, a kupci te mogu pratiti.',
        ),
      ),
      (
        '3',
        '🎁',
        t('Uzmi nešto novo'),
        t('Kupuj od drugih prodavatelja — prati trgovine koje ti se sviđaju.'),
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('Kako Subhasto radi'),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: t('Sakrij'),
                  onPressed: () =>
                      ref.read(appProvider.notifier).dismissHowItWorks(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (final (n, emoji, title, text) in steps)
                  SizedBox(
                    width: 250,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: LoopColors.peach,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$n. $title',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                text,
                                style: TextStyle(
                                  color: LoopColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// Traka s pošiljkama u tijeku; dodir otvara "Moje dostave".
class _DeliveryBanner extends StatelessWidget {
  const _DeliveryBanner({required this.deliveries});
  final List<Delivery> deliveries;

  @override
  Widget build(BuildContext context) {
    final first = deliveries.first;
    final waiting = deliveries.where((d) => d.awaitingChoice).length;
    final text = waiting > 0
        ? t('Odaberi dostavu za predmet ({0})', [waiting])
        : '${first.deviceName}: ${first.status(DateTime.now()).label}';
    return Material(
      color: LoopColors.sky,
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: () => DeliveriesScreen.open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Text('🚚', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deliveries.length == 1
                          ? t('1 dostava u tijeku')
                          : t('{0} dostave u tijeku', [deliveries.length]),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: LoopColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: LoopColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
