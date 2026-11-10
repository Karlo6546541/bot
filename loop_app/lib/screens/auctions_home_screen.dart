import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'auctions_screen.dart' show AuctionCard;
import 'messages_screen.dart' show MessagesButton;
import 'notifications_screen.dart' show NotificationBell;
import 'search_screen.dart';

/// Početna u aplikaciji samo za aukcije: tražilica, tabovi (Za tebe, Pratim,
/// Završavaju uskoro), kategorije i popis aukcija. Bez livea i Kupi odmah.
class AuctionsHomeScreen extends ConsumerStatefulWidget {
  const AuctionsHomeScreen({super.key});

  @override
  ConsumerState<AuctionsHomeScreen> createState() => _AuctionsHomeScreenState();
}

enum _AuctionTab { forYou, following, ending }

class _AuctionsHomeScreenState extends ConsumerState<AuctionsHomeScreen> {
  _AuctionTab _tab = _AuctionTab.forYou;
  DeviceCategory? _cat;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId ?? '';
    final now = DateTime.now();
    final all = [
      for (final a in s.activeAuctions)
        if (!a.isExpired(now) && !s.isBlocked(a.sellerId)) a,
    ];
    final cats = <DeviceCategory>{
      for (final a in all) ?s.deviceById(a.deviceId)?.category,
    };
    var list = [
      for (final a in all)
        if (_cat == null || s.deviceById(a.deviceId)?.category == _cat) a,
    ];
    switch (_tab) {
      case _AuctionTab.following:
        list = [
          for (final a in list)
            if (s.isFollowing(a.sellerId)) a,
        ];
        list.sort((a, b) => a.endsAt.compareTo(b.endsAt));
      case _AuctionTab.ending:
        list.sort((a, b) => a.endsAt.compareTo(b.endsAt));
      case _AuctionTab.forYou:
        // Više ponuda i bliži kraj prvi.
        list.sort((a, b) {
          final byBids = b.bids.length.compareTo(a.bids.length);
          return byBids != 0 ? byBids : a.endsAt.compareTo(b.endsAt);
        });
    }
    Widget tab(Key key, String label, _AuctionTab id) => Expanded(
      child: Semantics(
        button: true,
        selected: _tab == id,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: key,
          onTap: () => setState(() => _tab = id),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: _tab == id
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: _tab == id
                          ? LoopColors.textPrimary
                          : LoopColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 2,
                  width: 28,
                  color: _tab == id
                      ? LoopColors.textPrimary
                      : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const ValueKey('home-search'),
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => SearchScreen.open(context),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: LoopColors.textPrimary.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            size: 20,
                            color: LoopColors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              t('Pretraži aukcije i prodavače'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: LoopColors.textSecondary,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const MessagesButton(),
                const NotificationBell(),
              ],
            ),
          ),
          Row(
            key: const ValueKey('home-tabs'),
            children: [
              tab(
                const ValueKey('home-view-for-you'),
                t('Za tebe'),
                _AuctionTab.forYou,
              ),
              tab(
                const ValueKey('home-view-following'),
                t('Pratim'),
                _AuctionTab.following,
              ),
              tab(
                const ValueKey('home-view-ending'),
                t('Završavaju uskoro'),
                _AuctionTab.ending,
              ),
            ],
          ),
          Divider(
            height: 1,
            color: LoopColors.textPrimary.withValues(alpha: .08),
          ),
          if (cats.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                key: const ValueKey('home-categories'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: const ValueKey('home-cat-all'),
                      label: Text(t('Sve')),
                      selected: _cat == null,
                      onSelected: (_) => setState(() => _cat = null),
                    ),
                  ),
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('home-category-${c.name}'),
                        label: Text(c.label),
                        selected: _cat == c,
                        onSelected: (_) => setState(() => _cat = c),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    key: const ValueKey('home-no-auctions'),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _tab == _AuctionTab.following
                            ? t('Prodavači koje pratiš nemaju aktivnih aukcija.')
                            : t('Trenutno nema aukcija.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: LoopColors.textSecondary),
                      ),
                    ),
                  )
                : ListView.separated(
                    key: const ValueKey('home-ending'),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => IntrinsicHeight(
                      child: AuctionCard(
                        key: ValueKey('home-auction-${list[i].id}'),
                        auction: list[i],
                        viewerId: me,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
