import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/price_offer.dart';
import '../providers/app_providers.dart';
import '../services/community_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/empty_state.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/trade_actions.dart';
import '../widgets/user_avatar.dart';
import 'device_detail_screen.dart';
import 'public_profile_screen.dart';

/// Sve moje ponude cijena: najprije one koje čekaju moj odgovor.
class BargainsScreen extends ConsumerWidget {
  const BargainsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const BargainsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final toAnswer = state.bargainsToAnswer;
    final rest = state.myBargains
        .where((o) => !toAnswer.contains(o))
        .take(50)
        .toList();
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
    Widget tile(PriceOffer o) => Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: () {
          final d = state.deviceById(o.deviceId);
          if (d != null) DeviceDetailScreen.open(context, d);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: BargainTile(offer: o, showItem: true),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t('Ponude cijena'))),
      body: state.myBargains.isEmpty
          ? EmptyState(
              icon: Icons.price_change_outlined,
              title: t('Još nema ponuda'),
              message: t(
                'Na tuđem oglasu dodirni "Ponudi cijenu". Ponude za tvoje oglase pojavit će se ovdje.',
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    if (toAnswer.isNotEmpty) ...[
                      section(t('Čeka tvoj odgovor ({0})', [toAnswer.length])),
                      for (final o in toAnswer) tile(o),
                    ],
                    if (rest.isNotEmpty) ...[
                      section(t('Ostale ponude')),
                      for (final o in rest) tile(o),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

/// Ljestvica prodavatelja po broju prodaja (tjedan, mjesec, ukupno).
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const LeaderboardScreen()));

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  int? _days = 30;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final board = state.leaderboard(days: _days);
    final periods = <(int?, String)>[
      (7, t('Tjedan')),
      (30, t('Mjesec')),
      (null, t('Ukupno')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(t('Top prodavatelji'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final (days, label) in periods)
                    ChoiceChip(
                      label: Text(label),
                      selected: _days == days,
                      onSelected: (_) => setState(() => _days = days),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (board.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: t('Još nema prodaja u ovom razdoblju'),
                    message: t(
                      'Objavi oglas — prva prodaja te stavlja na ljestvicu.',
                    ),
                  ),
                )
              else
                for (final (i, s) in board.indexed)
                  Card(
                    child: ListTile(
                      key: ValueKey('rank-${s.user.id}'),
                      onTap: () => PublicProfileScreen.open(context, s.user.id),
                      leading: SizedBox(
                        width: 72,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: Text(
                                i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}.',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            UserAvatar(user: s.user, size: 36),
                          ],
                        ),
                      ),
                      title: Text(
                        s.user.shopTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        t('{0} prodaja · {1}', [
                          '${s.sales}',
                          formatCredits(s.revenue),
                        ]),
                      ),
                      trailing: s.user.isPromoted
                          ? const PromotedBadge(small: true)
                          : null,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plaćeno isticanje računa (tjedno).
Future<void> showPromoteSheet(BuildContext context, WidgetRef ref) async {
  if (blockGuest(context)) return;
  final weeks = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    backgroundColor: LoopColors.background,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => const _PromoteSheet(),
  );
  if (weeks == null || !context.mounted) return;
  await runWithLoading(
    context,
    () => ref.read(appProvider.notifier).promote(weeks),
    successMessage: t('Račun je istaknut ⭐ — oglasi ti se prikazuju prvi'),
  );
}

class _PromoteSheet extends ConsumerStatefulWidget {
  const _PromoteSheet();

  @override
  ConsumerState<_PromoteSheet> createState() => _PromoteSheetState();
}

class _PromoteSheetState extends ConsumerState<_PromoteSheet> {
  int _weeks = 1;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appProvider.select((s) => s.currentUser));
    final cost = CommunityService.promotionWeekly * _weeks;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('Istakni svoj račun ⭐'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              t(
                'Tvoji oglasi prikazuju se prvi u Marketu (Preporučeno) i na početnoj, s oznakom "Istaknuto". Cijena: {0} tjedno.',
                [formatCredits(CommunityService.promotionWeekly)],
              ),
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            if (user != null && user.isPromoted) ...[
              const SizedBox(height: 8),
              Text(
                t('Istaknut si do {0} — novo razdoblje se nadovezuje.', [
                  formatDateTime(user.promotedUntil!),
                ]),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (var w = 1; w <= CommunityService.maxPromotionWeeks; w++)
                  ChoiceChip(
                    label: Text(
                      w == 1 ? t('1 tjedan') : t('{0} tjedna', ['$w']),
                    ),
                    selected: _weeks == w,
                    onSelected: (_) => setState(() => _weeks = w),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('promote-pay'),
              onPressed: () => Navigator.pop(context, _weeks),
              icon: const Icon(Icons.campaign_outlined),
              label: Text(t('Plati {0}', [formatCredits(cost)])),
            ),
            const SizedBox(height: 6),
            Text(
              t('Plaća se s LOOP stanja. Stanje: {0}', [
                formatCredits(user?.credits ?? 0),
              ]),
              textAlign: TextAlign.center,
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Naziv mini webshopa.
Future<void> showShopNameDialog(BuildContext context, WidgetRef ref) async {
  final user = ref.read(appProvider).currentUser;
  if (user == null) return;
  final c = TextEditingController(text: user.shopName);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Naziv trgovine')),
      content: TextField(
        key: const ValueKey('shop-name'),
        controller: c,
        autofocus: true,
        maxLength: AppUser.maxShopName,
        decoration: InputDecoration(
          hintText: user.handle,
          helperText: t('Prazno = korisničko ime.'),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t('Odustani')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: Text(t('Spremi')),
        ),
      ],
    ),
  );
  if (name == null || !context.mounted) return;
  await runWithLoading(
    context,
    () => ref.read(appProvider.notifier).setShopName(name),
    successMessage: t('Naziv trgovine je spremljen'),
  );
}
