import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/feed.dart';
import '../widgets/formatters.dart';
import 'live_screens.dart';
import 'swipe_feed_screen.dart';

/// Kartica "Uživo" (dizajn Subhasto): aplikacija se otvara ravno u live
/// preko cijelog ekrana, kao Taobao Live i Whatnot. Povuci gore/dolje za
/// sljedeći show. Kad nitko nije uživo: nadolazeći showovi i "Pokreni live".
class StageTab extends ConsumerWidget {
  const StageTab({super.key, required this.visible, required this.onExplore});

  /// Je li kartica vidljiva (live se gleda samo tada).
  final bool visible;

  /// "Istraži" — prelazak na pregled svih liveova, aukcija i predmeta.
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final live = [
      for (final (show, st) in s.activeLives)
        if (st.isLive) (show, st),
    ]..sort((a, b) => b.$2.viewers.compareTo(a.$2.viewers));
    if (live.isNotEmpty) {
      return SwipeFeedScreen(
        key: const ValueKey('stage-feed'),
        embedded: true,
        active: visible,
        title: t('Uživo'),
        entries: [for (final (show, _) in live) FeedEntry.live(show.id)],
      );
    }
    final soon = [
      for (final (show, st) in s.activeLives)
        if (st.isScheduled) show,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return Theme(
      data: buildLiveTheme(),
      child: DecoratedBox(
        key: const ValueKey('stage-empty'),
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 1.1,
            colors: [Color(0x332A3A66), Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 120),
            children: [
              const Icon(Icons.sensors, size: 44, color: Colors.white54),
              const SizedBox(height: 18),
              Text(
                t('Trenutno nitko nije uživo'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t('Pokreni svoj live ili pogledaj aukcije i predmete.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 15),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('stage-go-live'),
                onPressed: () => CreateLiveShowScreen.open(context),
                child: Text(t('Pokreni live')),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const ValueKey('stage-explore'),
                onPressed: onExplore,
                child: Text(t('Istraži')),
              ),
              if (soon.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text(
                  t('Uskoro'),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                for (final show in soon.take(5))
                  ListTile(
                    key: ValueKey('stage-soon-${show.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      show.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${show.hostLabel} · ${formatDateTime(show.startsAt)}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.white54,
                    ),
                    onTap: () => LiveRoomScreen.open(context, show.id),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
