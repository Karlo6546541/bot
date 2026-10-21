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

/// Prikaz u odjeljku Aukcije.
enum AuctionView {
  live('U tijeku', Icons.gavel),
  myBids('Moje ponude', Icons.back_hand_outlined),
  mine('Moje aukcije', Icons.storefront_outlined),
  ended('Završene', Icons.history);

  const AuctionView(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Odnos prijavljenog korisnika prema aukciji (za oznaku na kartici).
enum AuctionRole {
  seller('Tvoja aukcija', Icons.storefront),
  leading('Vodiš', Icons.emoji_events),
  outbid('Nadmašen si', Icons.trending_down),
  won('Osvojeno', Icons.emoji_events),
  none('', Icons.circle);

  const AuctionRole(this.label, this.icon);
  final String label;
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
    AuctionView.live => s.activeAuctions,
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
    final held = s.heldCreditsOf(me);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _RulesBanner(
              credits: s.currentUser?.credits ?? 0,
              held: held,
            ),
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
                AuctionView.live => 'Trenutno nema aukcija',
                AuctionView.myBids => 'Još nisi dao nijednu ponudu',
                AuctionView.mine => 'Nemaš svojih aukcija',
                AuctionView.ended => 'Još nema završenih aukcija',
              },
              message: _view == AuctionView.mine || _view == AuctionView.live
                  ? 'Objavi predmet iz svog portfolija gumbom "Nova aukcija".'
                  : null,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 420,
                mainAxisExtent: 168,
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

/// Sažetak pravila i stanje kredita (raspoloživo / blokirano).
class _RulesBanner extends StatelessWidget {
  const _RulesBanner({required this.credits, required this.held});
  final double credits;
  final double held;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: LoopColors.surfaceHover),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 6,
            children: [
              _Kv('Raspoloživo za ponude', formatCredits(credits)),
              _Kv('Blokirano u vodećim ponudama', formatCredits(held)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ponude su obvezujuće i ne mogu se povući. Iznos vodeće ponude se '
            'blokira i vraća ti se čim te netko nadmaši. Ponuda ne može biti '
            'veća od raspoloživih kredita.',
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: TextStyle(color: LoopColors.textSecondary, fontSize: 12)),
      Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
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
                              ? 'Prodaješ ti'
                              : 'Prodaje ${a.sellerLabel}',
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
                          a.bids.isEmpty ? 'Početna cijena' : 'Najviša ponuda',
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
                        '${a.bids.length} '
                        '${a.bids.length == 1 ? 'ponuda' : 'ponuda'}',
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
