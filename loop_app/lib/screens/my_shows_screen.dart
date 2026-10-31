import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/live_show.dart';
import '../providers/app_providers.dart';
import '../services/live_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/trade_actions.dart';
import 'auctions_screen.dart' show BrowseCardMedia;
import 'live_screens.dart';

/// Moji showovi (Seller Hub): nadolazeći (otvori, kopiraj link, otkaži) i
/// prošli (sažetak, dupliciraj show).
class MyShowsScreen extends ConsumerWidget {
  const MyShowsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const MyShowsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId;
    final now = DateTime.now();
    final mine = [
      for (final show in s.liveShows)
        if (show.hostId == me) show,
    ];
    final upcoming = [
      for (final show in mine)
        if (!s.liveStateOf(show, now).isOver) show,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past = [
      for (final show in mine)
        if (s.liveStateOf(show, now).isOver) show,
    ]..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('Moji showovi')),
          bottom: TabBar(
            tabs: [
              Tab(
                key: const ValueKey('shows-tab-upcoming'),
                text: t('Nadolazeći ({0})', ['${upcoming.length}']),
              ),
              Tab(
                key: const ValueKey('shows-tab-past'),
                text: t('Prošli ({0})', ['${past.length}']),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const ValueKey('shows-schedule'),
          onPressed: () => CreateLiveShowScreen.open(context),
          icon: const Icon(Icons.event_outlined),
          label: Text(t('Zakaži show')),
        ),
        body: TabBarView(
          children: [
            _list(
              context,
              upcoming,
              t('Nemaš zakazanih showova.'),
              (show) => _UpcomingCard(show: show),
            ),
            _list(
              context,
              past,
              t('Još nemaš završenih showova.'),
              (show) => _PastCard(show: show),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<LiveShow> shows,
    String empty,
    Widget Function(LiveShow) card,
  ) => shows.isEmpty
      ? EmptyState(icon: Icons.videocam_outlined, title: empty, message: '')
      : ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: shows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => card(shows[i]),
        );
}

class _ShowHeader extends StatelessWidget {
  const _ShowHeader({required this.show, required this.subtitle});
  final LiveShow show;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 66,
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BrowseCardMedia(device: null, cover: show.coverPath),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              show.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              formatDateTime(show.startsAt),
              style: TextStyle(
                color: LoopColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );
}

class _UpcomingCard extends ConsumerWidget {
  const _UpcomingCard({required this.show});
  final LiveShow show;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final st = s.liveStateOf(show, DateTime.now());
    return Card(
      key: ValueKey('show-card-${show.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ShowHeader(
              show: show,
              subtitle: st.isLive
                  ? t('Uživo sada · {0} predmeta', ['${show.lots.length}'])
                  : itemsLabel(show.lots.length),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: ValueKey('show-open-${show.id}'),
                  onPressed: () => LiveRoomScreen.open(context, show.id),
                  child: Text(st.isLive ? t('Vrati se u show') : t('Otvori')),
                ),
                OutlinedButton(
                  key: ValueKey('show-link-${show.id}'),
                  onPressed: () => shareLink(
                    context,
                    publicLink(live: show.id),
                    text: t('Gledaj "{0}" uživo na Subhastu', [show.title]),
                  ),
                  child: Text(t('Kopiraj link')),
                ),
                if (st.isScheduled)
                  OutlinedButton(
                    key: ValueKey('show-cancel-${show.id}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: LoopColors.error,
                    ),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(t('Otkazati show?')),
                          content: Text(
                            t(
                              'Pratitelji koji su označili show više ga neće moći gledati.',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(t('Odustani')),
                            ),
                            FilledButton(
                              key: const ValueKey('show-cancel-confirm'),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(t('Otkaži show')),
                            ),
                          ],
                        ),
                      );
                      if (ok != true || !context.mounted) return;
                      await runWithLoading(
                        context,
                        () =>
                            ref.read(appProvider.notifier).endLiveShow(show.id),
                        successMessage: t('Show je otkazan'),
                      );
                    },
                    child: Text(t('Otkaži show')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PastCard extends ConsumerWidget {
  const _PastCard({required this.show});
  final LiveShow show;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final st = s.liveStateOf(show, DateTime.now());
    final me = s.currentUserId ?? '';
    final reusable = LiveService(
      ref.read(storageProvider),
    ).duplicableLots(me, show).length;
    return Card(
      key: ValueKey('show-card-${show.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ShowHeader(
              show: show,
              subtitle: t('Prodano {0} od {1} predmeta', [
                '${st.soldCount}',
                '${st.lots.length}',
              ]),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: ValueKey('show-duplicate-${show.id}'),
                  onPressed: () => _duplicate(context, ref, reusable),
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: Text(t('Dupliciraj show')),
                ),
                OutlinedButton(
                  key: ValueKey('show-open-${show.id}'),
                  onPressed: () => LiveRoomScreen.open(context, show.id),
                  child: Text(t('Sažetak')),
                ),
              ],
            ),
            if (reusable > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t('{0} predmeta se prenosi u novi show.', ['$reusable']),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _duplicate(
    BuildContext context,
    WidgetRef ref,
    int reusable,
  ) async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      helpText: t('Kada je novi show?'),
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(LiveShow.maxScheduleAhead),
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(show.startsAt),
    );
    if (time == null || !context.mounted) return;
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    final ok = await runWithLoading(
      context,
      () => ref.read(appProvider.notifier).duplicateLiveShow(show.id, at),
      successMessage: t('Show je zakazan: {0}', [formatDateTime(at)]),
    );
    if (ok && context.mounted) DefaultTabController.of(context).animateTo(0);
  }
}
