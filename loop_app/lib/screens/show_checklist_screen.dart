import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/live_show.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import 'live_promote_sheet.dart';
import 'live_screens.dart';
import 'my_shows_screen.dart';

/// Koraci pripreme zakazanog showa.
enum ShowPrepStep { create, products, buyers, goLive }

/// Što je od pripreme gotovo: show postoji, ima predmete, kupci znaju za
/// njega (podsjetnici, dijeljenje ili promocija). "Kreni uživo" se
/// otključava kad show ima predmete.
Set<ShowPrepStep> showPrepDone(
  LiveShow show,
  Iterable<LiveEvent> events, {
  required bool promoted,
}) => {
  ShowPrepStep.create,
  if (show.lots.isNotEmpty) ShowPrepStep.products,
  if (promoted ||
      events.any(
        (e) =>
            e.showId == show.id &&
            (e.type == LiveEventType.remind || e.type == LiveEventType.share),
      ))
    ShowPrepStep.buyers,
};

/// "Spremi se za live": popis koraka do početka showa (kao Whatnot), u
/// Subhasto stilu.
class ShowChecklistScreen extends ConsumerWidget {
  const ShowChecklistScreen({super.key, required this.showId});
  final String showId;

  static Future<void> open(BuildContext context, String showId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShowChecklistScreen(showId: showId),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final show = s.liveShowById(showId);
    if (show == null) return const Scaffold(body: SizedBox.shrink());
    final st = s.liveStateOf(show);
    final done = showPrepDone(show, s.liveEvents, promoted: st.boost.active);
    final reminders = s.liveEvents
        .where((e) => e.showId == show.id && e.type == LiveEventType.remind)
        .length;
    final name = (s.currentUser?.name.trim().isNotEmpty ?? false)
        ? s.currentUser!.name.trim()
        : (s.currentUser?.handle ?? '?');

    Widget step(
      ShowPrepStep id,
      String title,
      String subtitle,
      VoidCallback onTap, {
      bool locked = false,
    }) {
      final isDone = done.contains(id);
      return InkWell(
        key: ValueKey('prep-${id.name}'),
        onTap: locked ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (locked)
                Icon(Icons.lock_outline, color: LoopColors.textSecondary)
              else if (isDone)
                Icon(
                  Icons.check_circle,
                  key: ValueKey('prep-${id.name}-done'),
                  color: LoopColors.success,
                )
              else
                Icon(Icons.circle_outlined, color: LoopColors.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: locked ? LoopColors.textSecondary : null,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        decorationColor: LoopColors.textSecondary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: LoopColors.textSecondary),
            ],
          ),
        ),
      );
    }

    final canGoLive = done.contains(ShowPrepStep.products);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        key: const ValueKey('show-checklist'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SizedBox(
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 40,
                  top: 30,
                  child: Icon(
                    Icons.auto_awesome,
                    color: LoopColors.accent.withValues(alpha: 0.7),
                    size: 28,
                  ),
                ),
                Positioned(
                  right: 50,
                  bottom: 30,
                  child: Icon(
                    Icons.event_available,
                    color: LoopColors.accent,
                    size: 30,
                  ),
                ),
                Positioned(
                  right: 70,
                  top: 18,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF2D55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.graphic_eq,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                CircleAvatar(
                  radius: 52,
                  backgroundColor: LoopColors.accent,
                  child: Text(
                    name.characters.first.toUpperCase(),
                    style: TextStyle(
                      color: LoopColors.onAccent,
                      fontSize: 46,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            t('Spremi se za live'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26),
          ),
          const SizedBox(height: 4),
          Text(
            '${show.title} · ${formatDateTime(show.startsAt)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            t(
              'Show možeš urediti ili prebaciti na drugi termin kad god želiš.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: LoopColors.textSecondary),
          ),
          const SizedBox(height: 18),
          Material(
            color: LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                step(
                  ShowPrepStep.create,
                  t('Kreiraj show'),
                  t('Naslov, kategorija, termin i naslovnica.'),
                  () => MyShowsScreen.open(context),
                ),
                step(
                  ShowPrepStep.products,
                  t('Dodaj predmete'),
                  show.lots.isEmpty
                      ? t('Show još nema predmeta.')
                      : itemsLabel(show.lots.length),
                  () => showAddToShowSheet(context, ref, show),
                ),
                step(
                  ShowPrepStep.buyers,
                  t('Dovedi kupce'),
                  reminders > 0
                      ? t('{0} kupaca čeka podsjetnik', ['$reminders'])
                      : t('Podijeli link ili promoviraj show.'),
                  () => showPromoteSheet(context, ref, show),
                ),
                step(
                  ShowPrepStep.goLive,
                  t('Kreni uživo!'),
                  canGoLive
                      ? t('Uđi u sobu i pokreni prvi predmet.')
                      : t('Zahtijeva prethodne korake.'),
                  () => LiveRoomScreen.open(context, show.id),
                  locked: !canGoLive,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            t('Savjeti za prvi show'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 10),
          for (final (icon, text) in [
            (Icons.schedule, t('Odvoji barem 30 minuta za prodaju.')),
            (
              Icons.lightbulb_outline,
              t('Dobro svjetlo i miran kadar prodaju bolje od skupe kamere.'),
            ),
            (
              Icons.card_giftcard,
              t('Giveaway na početku zadrži gledatelje do prvog predmeta.'),
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: LoopColors.surface,
                  borderRadius: BorderRadius.circular(kRadius),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: LoopColors.accent),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
