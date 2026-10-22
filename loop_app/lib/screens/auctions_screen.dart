import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auction.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/countdown.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import 'auction_detail_screen.dart';
import '../l10n/tr.dart';

/// Prikaz u odjeljku Aukcije.
enum AuctionView {
  live('U tijeku', Icons.gavel),
  myBids('Moje ponude', Icons.back_hand_outlined),
  mine('Moje aukcije', Icons.storefront_outlined),
  ended('Završene', Icons.history);

  const AuctionView(this._label, this.icon);
  final String _label;
  String get label => t(_label);
  final IconData icon;
}

/// Odnos prijavljenog korisnika prema aukciji (za oznaku na kartici).
enum AuctionRole {
  seller('Tvoja aukcija', Icons.storefront),
  leading('Vodiš', Icons.emoji_events),
  outbid('Nadmašen si', Icons.trending_down),
  won('Osvojeno', Icons.emoji_events),
  none('', Icons.circle);

  const AuctionRole(this._label, this.icon);
  final String _label;
  String get label => t(_label);
  final IconData icon;

  /// Boja ovisi o temi, pa je getter (enum vrijednosti moraju biti const).
  Color get color => switch (this) {
    leading || won => LoopColors.success,
    outbid => LoopColors.error,
    seller || none => LoopColors.textSecondary,
  };

  static AuctionRole of(Auction a, String? me) {
    if (me == null) return none;
    if (a.sellerId == me) return seller;
    final top = a.highestBid?.userId == me;
    if (a.status == AuctionStatus.sold && top) return won;
    if (!a.isActive) return none;
    if (top) return leading;
    if (a.bids.any((b) => b.userId == me)) return outbid;
    return none;
  }
}

class AuctionsScreen extends ConsumerStatefulWidget {
  const AuctionsScreen({super.key});

  @override
  ConsumerState<AuctionsScreen> createState() => _AuctionsScreenState();
}

class _AuctionsScreenState extends ConsumerState<AuctionsScreen> {
  AuctionView _view = AuctionView.live;

  List<Auction> _filter(AppState s, String me) => switch (_view) {
    AuctionView.live =>
      s.activeAuctions.where((a) => !s.isBlocked(a.sellerId)).toList(),
    AuctionView.myBids =>
      s.auctions.where((a) => a.bids.any((b) => b.userId == me)).toList(),
    AuctionView.mine => s.auctions.where((a) => a.sellerId == me).toList(),
    AuctionView.ended =>
      s.auctions.where((a) => !a.isActive).toList().reversed.toList(),
  };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId ?? '';
    final list = _filter(s, me);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: const _RulesBanner(),
          ),
        ),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AuctionView>(
              showSelectedIcon: false,
              segments: [
                for (final v in AuctionView.values)
                  ButtonSegment(
                    value: v,
                    label: Text(v.label),
                    icon: Icon(v.icon, size: 18),
                  ),
              ],
              selected: {_view},
              onSelectionChanged: (v) => setState(() => _view = v.first),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        if (list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.gavel,
              title: switch (_view) {
                AuctionView.live => t('Trenutno nema aukcija'),
                AuctionView.myBids => t('Još nisi dao nijednu ponudu'),
                AuctionView.mine => t('Nemaš svojih aukcija'),
                AuctionView.ended => t('Još nema završenih aukcija'),
              },
              message: _view == AuctionView.mine || _view == AuctionView.live
                  ? t('Pokreni aukciju gumbom + u donjoj traci.')
                  : null,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 420,
                mainAxisExtent: MediaQuery.sizeOf(context).width < 600
                    ? 136
                    : 156,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => AuctionCard(auction: list[i], viewerId: me),
                childCount: list.length,
              ),
            ),
          ),
      ],
    );
  }
}

/// Sažetak pravila aukcija (dodir otvara sva pravila).
class _RulesBanner extends StatelessWidget {
  const _RulesBanner();

  void _showRules(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: LoopColors.surface,
    builder: (_) => Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('Pravila aukcija'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 12),
          Text(
            t(
              '🔒  Ponuda je obvezujuća — ne može se povući ni smanjiti.\n\n🥇  Dok vodiš, ne možeš licitirati ponovno (možeš povisiti automatsku ponudu).\n\n💳  Pobjednik plaća karticom kad aukcija završi — ništa se ne blokira unaprijed.\n\n⏱️  Ponuda u zadnjoj minuti produljuje aukciju za 1 minutu.\n\n🎁  Pobjednik dobiva predmet, prodavatelj cijelu ponudu (bez naknade).',
            ),
            style: TextStyle(height: 1.4, fontSize: 15),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Material(
    color: LoopColors.surface,
    borderRadius: BorderRadius.circular(kRadius),
    child: InkWell(
      key: const ValueKey('auction-rules'),
      borderRadius: BorderRadius.circular(kRadius),
      onTap: () => _showRules(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            const Text('🔒', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t(
                  'Ponude su obvezujuće · pobjednik plaća karticom na kraju aukcije',
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Icon(Icons.info_outline, color: LoopColors.textSecondary),
          ],
        ),
      ),
    ),
  );
}

/// Kartica aukcije: slika, naziv, trenutna cijena, broj ponuda,
/// odbrojavanje i oznaka odnosa korisnika (vodiš / nadmašen si …).
class AuctionCard extends ConsumerWidget {
  const AuctionCard({super.key, required this.auction, required this.viewerId});

  final Auction auction;
  final String viewerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = auction;
    final device = ref.watch(
      appProvider.select((s) => s.deviceById(a.deviceId)),
    );
    final role = AuctionRole.of(a, viewerId);
    final cat = device?.category;

    return Material(
      color: LoopColors.surface,
      borderRadius: BorderRadius.circular(kRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => AuctionDetailScreen.open(context, a.id),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(
              color: role == AuctionRole.leading || role == AuctionRole.won
                  ? LoopColors.success.withValues(alpha: 0.5)
                  : role == AuctionRole.outbid
                  ? LoopColors.error.withValues(alpha: 0.5)
                  : (cat?.color ?? LoopColors.surfaceHover).withValues(
                      alpha: 0.25,
                    ),
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (device != null)
                    ItemThumb(device: device, size: 52)
                  else
                    const SizedBox(width: 52, height: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device?.name ?? a.deviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          a.sellerId == viewerId
                              ? t('Prodaješ ti')
                              : t('Prodaje {0}', [a.sellerLabel]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (role != AuctionRole.none) RoleBadge(role: role),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.bids.isEmpty
                              ? t('Početna cijena')
                              : t('Najviša ponuda'),
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatCredits(a.currentPrice),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        a.bids.length == 1
                            ? t('1 ponuda')
                            : t('{0} ponuda', [a.bids.length]),
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (a.isActive)
                        AuctionCountdown(endsAt: a.endsAt)
                      else
                        Text(
                          a.status.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Oznaka odnosa korisnika prema aukciji (ikona + tekst, nikad samo boja).
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});
  final AuctionRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: role.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(role.icon, size: 14, color: role.color),
          const SizedBox(width: 4),
          Text(
            role.label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// "marko@loop.com" → "m***o@loop.com" (ponuđači su djelomično skriveni).
String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 1) return email;
  final name = email.substring(0, at);
  final masked = name.length <= 2
      ? '${name[0]}***'
      : '${name[0]}***${name[name.length - 1]}';
  return '$masked${email.substring(at)}';
}
