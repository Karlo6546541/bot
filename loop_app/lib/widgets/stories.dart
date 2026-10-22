import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/story.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../screens/device_detail_screen.dart';
import '../screens/public_profile_screen.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'item_image.dart';
import 'category_style.dart';
import 'trade_actions.dart';
import 'user_avatar.dart';

const _ring = [Color(0xFFFFC233), Color(0xFFFF2D55), Color(0xFF7B2FF7)];

/// "Prije 5 min", "prije 3 h".
String storyAge(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return t('upravo');
  if (d.inHours < 1) return t('prije {0} min', ['${d.inMinutes}']);
  return t('prije {0} h', ['${d.inHours}']);
}

/// Profilna slika s prstenom priče: šareni prsten = nepogledano, sivi =
/// pogledano, bez prstena = nema priča.
class StoryRing extends StatelessWidget {
  const StoryRing({
    super.key,
    required this.user,
    required this.size,
    this.state = StoryRingState.none,
  });

  final AppUser user;
  final double size;
  final StoryRingState state;

  @override
  Widget build(BuildContext context) {
    final ring = switch (state) {
      StoryRingState.unseen => const SweepGradient(
        colors: [..._ring, Color(0xFFFFC233)],
      ),
      StoryRingState.seen => const LinearGradient(
        colors: [Color(0xFFBDBDBD), Color(0xFFBDBDBD)],
      ),
      StoryRingState.none => null,
    };
    if (ring == null) return UserAvatar(user: user, size: size);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: ring),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: LoopColors.background,
        ),
        child: UserAvatar(user: user, size: size - 10),
      ),
    );
  }
}

enum StoryRingState { none, unseen, seen }

/// Red s pričama na početnoj (kao na Instagramu).
class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final me = state.currentUser;
    final groups = state.storyGroups;
    final mine = me == null ? null : state.storiesOf(me.id);
    final others = groups.where((g) => g.user.id != me?.id).toList();
    if (me == null || (me.isGuest && others.isEmpty)) {
      return const SizedBox.shrink();
    }

    Widget bubble({
      required Widget avatar,
      required String label,
      required VoidCallback onTap,
      Key? key,
      bool bold = false,
    }) => SizedBox(
      width: 76,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              avatar,
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return SizedBox(
      height: 98,
      child: ListView(
        key: const ValueKey('stories-row'),
        scrollDirection: Axis.horizontal,
        children: [
          if (!me.isGuest)
            bubble(
              key: const ValueKey('my-story'),
              label: t('Tvoja priča'),
              bold: true,
              onTap: () => mine == null
                  ? CreateStoryScreen.open(context)
                  : _myStoryMenu(context, groups, mine),
              avatar: Stack(
                clipBehavior: Clip.none,
                children: [
                  StoryRing(
                    user: me,
                    size: 64,
                    state: mine == null
                        ? StoryRingState.none
                        : mine.seen
                        ? StoryRingState.seen
                        : StoryRingState.unseen,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: LoopColors.accent,
                        border: Border.all(
                          color: LoopColors.background,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final g in others)
            bubble(
              key: ValueKey('story-${g.user.id}'),
              label: g.user.username.isEmpty ? g.user.name : g.user.username,
              onTap: () => StoryViewer.open(context, groups, groups.indexOf(g)),
              avatar: StoryRing(
                user: g.user,
                size: 64,
                state: g.seen ? StoryRingState.seen : StoryRingState.unseen,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _myStoryMenu(
    BuildContext context,
    List<StoryGroup> groups,
    StoryGroup mine,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: LoopColors.background,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(t('Pogledaj svoju priču')),
              onTap: () => Navigator.pop(ctx, 'view'),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(t('Nova priča')),
              onTap: () => Navigator.pop(ctx, 'new'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'view') {
      await StoryViewer.open(context, groups, groups.indexOf(mine));
    } else if (choice == 'new') {
      await CreateStoryScreen.open(context);
    }
  }
}

/// Preglednik priča preko cijelog ekrana: trake napretka, dodir lijevo /
/// desno za prethodnu / sljedeću, držanje za pauzu, povlačenje u stranu
/// za sljedeću trgovinu.
class StoryViewer extends ConsumerStatefulWidget {
  const StoryViewer({super.key, required this.groups, required this.initial});

  final List<StoryGroup> groups;
  final int initial;

  /// Trajanje jedne priče.
  static const duration = Duration(seconds: 5);

  static Future<void> open(
    BuildContext context,
    List<StoryGroup> groups,
    int index,
  ) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => StoryViewer(groups: groups, initial: index),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(a),
          child: child,
        ),
      ),
    ),
  );

  @override
  ConsumerState<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends ConsumerState<StoryViewer>
    with SingleTickerProviderStateMixin {
  late final _pages = PageController(initialPage: widget.initial);
  late final _progress = AnimationController(
    vsync: this,
    duration: StoryViewer.duration,
  );
  late int _group = widget.initial;
  int _story = 0;
  bool _autoplay = true;

  @override
  void initState() {
    super.initState();
    // U testovima (bez timera) priče se ne izmjenjuju same.
    _autoplay = ref.read(tickIntervalProvider) != null;
    _progress.addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _progress.dispose();
    _pages.dispose();
    super.dispose();
  }

  StoryGroup get _g => widget.groups[_group];

  void _start() {
    if (!mounted) return;
    final s = _g.stories[_story];
    ref.read(appProvider.notifier).markStorySeen(s.id);
    _progress.value = 0;
    if (_autoplay) _progress.forward();
  }

  void _next() {
    if (_story < _g.stories.length - 1) {
      setState(() => _story++);
      _start();
    } else if (_group < widget.groups.length - 1) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _previous() {
    if (_story > 0) {
      setState(() => _story--);
      _start();
    } else if (_group > 0) {
      _pages.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      _start();
    }
  }

  Future<void> _delete(Story s) async {
    _progress.stop();
    final ok = await confirmDialog(
      context,
      title: t('Obrisati priču?'),
      message: t('Priča će nestati za sve.'),
      confirmLabel: t('Obriši'),
      destructive: true,
    );
    if (!ok || !mounted) {
      if (_autoplay) _progress.forward();
      return;
    }
    await ref.read(appProvider.notifier).deleteStory(s.id);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: PageView.builder(
            key: const ValueKey('story-viewer'),
            controller: _pages,
            itemCount: widget.groups.length,
            onPageChanged: (i) {
              setState(() {
                _group = i;
                _story = 0;
              });
              _start();
            },
            itemBuilder: (context, gi) {
              final g = widget.groups[gi];
              final index = gi == _group ? _story : 0;
              final story = g.stories[index.clamp(0, g.stories.length - 1)];
              return _StoryPage(
                group: g,
                story: story,
                index: index,
                progress: gi == _group ? _progress : null,
                state: state,
                onPrevious: _previous,
                onNext: _next,
                onPause: () => _progress.stop(),
                onResume: () {
                  if (_autoplay) _progress.forward();
                },
                onDelete: g.user.id == state.currentUserId
                    ? () => _delete(story)
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StoryPage extends StatelessWidget {
  const _StoryPage({
    required this.group,
    required this.story,
    required this.index,
    required this.progress,
    required this.state,
    required this.onPrevious,
    required this.onNext,
    required this.onPause,
    required this.onResume,
    required this.onDelete,
  });

  final StoryGroup group;
  final Story story;
  final int index;
  final AnimationController? progress;
  final AppState state;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback? onDelete;

  static const _shadow = [Shadow(blurRadius: 8, color: Colors.black54)];

  @override
  Widget build(BuildContext context) {
    final s = story;
    final d = s.deviceId == null ? null : state.deviceById(s.deviceId!);
    final photo =
        s.imagePath ??
        (d != null && d.imagePaths.isNotEmpty ? d.imagePaths.first : null);
    final background = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: s.gradient,
        ),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // Pozadina: fotografija (cijela, preko zamućene kopije) ili boja.
        if (photo == null)
          background
        else ...[
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: LocalPhoto(
              path: photo,
              cacheWidth: 200,
              fallback: background,
            ),
          ),
          LocalPhoto(
            path: photo,
            fit: BoxFit.contain,
            cacheWidth: 1080,
            fallback: background,
          ),
        ],
        if (photo == null && d != null)
          Center(
            child: Icon(d.category.icon, size: 150, color: Colors.white24),
          ),
        // Tekst priče.
        if (s.text.isNotEmpty)
          Align(
            alignment: photo == null && d == null
                ? Alignment.center
                : const Alignment(0, -0.45),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                s.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: photo == null && d == null ? 30 : 24,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                  shadows: _shadow,
                ),
              ),
            ),
          ),
        // Dodir lijevo/desno, držanje = pauza.
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                key: const ValueKey('story-prev'),
                behavior: HitTestBehavior.opaque,
                onTap: onPrevious,
                onLongPressStart: (_) => onPause(),
                onLongPressEnd: (_) => onResume(),
              ),
            ),
            Expanded(
              flex: 2,
              child: GestureDetector(
                key: const ValueKey('story-next'),
                behavior: HitTestBehavior.opaque,
                onTap: onNext,
                onLongPressStart: (_) => onPause(),
                onLongPressEnd: (_) => onResume(),
                onVerticalDragEnd: (e) {
                  if ((e.primaryVelocity ?? 0) > 300) {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
            ),
          ],
        ),
        // Gore: trake napretka, trgovina, vrijeme, zatvori.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < group.stories.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: SizedBox(
                              height: 3,
                              child: i < index
                                  ? const ColoredBox(color: Colors.white)
                                  : i > index || progress == null
                                  ? const ColoredBox(color: Colors.white38)
                                  : AnimatedBuilder(
                                      animation: progress!,
                                      builder: (_, _) =>
                                          LinearProgressIndicator(
                                            value: progress!.value,
                                            backgroundColor: Colors.white38,
                                            valueColor:
                                                const AlwaysStoppedAnimation(
                                                  Colors.white,
                                                ),
                                          ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        PublicProfileScreen.open(context, group.user.id);
                      },
                      child: Row(
                        children: [
                          UserAvatar(user: group.user, size: 36),
                          const SizedBox(width: 8),
                          Text(
                            group.user.shopTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              shadows: _shadow,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      storyAge(s.createdAt),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        shadows: _shadow,
                      ),
                    ),
                    const Spacer(),
                    if (onDelete != null)
                      IconButton(
                        key: const ValueKey('story-delete'),
                        tooltip: t('Obriši priču'),
                        color: Colors.white,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: onDelete,
                      ),
                    IconButton(
                      key: const ValueKey('story-close'),
                      tooltip: t('Zatvori'),
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Dolje: oglas iz priče.
        if (d != null && d.isForSale)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  key: const ValueKey('story-item'),
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    Navigator.of(context).pop();
                    DeviceDetailScreen.open(context, d);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        ItemThumb(device: d, size: 52),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                formatCredits(
                                  d.ownerId == state.currentUserId
                                      ? d.askPrice
                                      : d.shownPrice,
                                ),
                                style: TextStyle(
                                  color: d.hasDiscount
                                      ? const Color(0xFFE5254B)
                                      : Colors.black87,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            DeviceDetailScreen.open(context, d);
                          },
                          child: Text(t('Pogledaj')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Izrada priče: tekst na boji, fotografija i/ili jedan od mojih oglasa.
class CreateStoryScreen extends ConsumerStatefulWidget {
  const CreateStoryScreen({super.key});

  static Future<void> open(BuildContext context) {
    if (blockGuest(context)) return Future.value();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CreateStoryScreen()));
  }

  @override
  ConsumerState<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends ConsumerState<CreateStoryScreen> {
  final _text = TextEditingController();
  int _color = 0;
  String? _deviceId;
  String? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final p = await ref.read(appProvider.notifier).pickStoryPhoto();
      if (p != null && mounted) setState(() => _photo = p);
    } catch (e) {
      showLoopSnackBar(t('Slika nije spremljena: {0}', [e]), error: true);
    }
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(appProvider.notifier)
          .createStory(
            text: _text.text,
            deviceId: _deviceId,
            imagePath: _photo,
            color: _color,
          );
      if (!mounted) return;
      Navigator.pop(context);
      showLoopSnackBar(t('Priča je objavljena — vidljiva je 24 sata ✨'));
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final listings = state.myListings;
    final d = _deviceId == null ? null : state.deviceById(_deviceId!);
    final preview = Story(
      id: 'preview',
      userId: state.currentUserId ?? '',
      text: _text.text,
      deviceId: _deviceId,
      imagePath: _photo,
      color: _color,
      createdAt: DateTime.now(),
    );
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(t('Nova priča')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const ValueKey('publish-story'),
              onPressed: _busy ? null : _publish,
              child: Text(t('Objavi')),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // Pregled priče.
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: 200,
                    height: 330,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: preview.gradient,
                            ),
                          ),
                        ),
                        if (_photo != null)
                          LocalPhoto(
                            path: _photo!,
                            fit: BoxFit.cover,
                            fallback: const SizedBox(),
                          ),
                        if (_text.text.isNotEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                _text.text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 8,
                                      color: Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (d != null)
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  ItemThumb(device: d, size: 30),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      d.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('story-text'),
                controller: _text,
                maxLength: Story.maxText,
                maxLines: 2,
                minLines: 1,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: t('Tekst priče'),
                  hintText: t('npr. Novo stiglo! · Danas −20% na sve'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t('Boja'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: [
                  for (var i = 0; i < Story.palettes.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _color = i),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: Story.palettes[i]),
                          border: Border.all(
                            color: _color == i
                                ? LoopColors.textPrimary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        _photo == null
                            ? t('Dodaj fotografiju')
                            : t('Promijeni fotografiju'),
                      ),
                    ),
                  ),
                  if (_photo != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: t('Ukloni sliku'),
                      onPressed: () => setState(() => _photo = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ],
              ),
              if (listings.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  t('Pokaži oglas (neobavezno)'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 92,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final item in listings)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            key: ValueKey('story-pick-${item.id}'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setState(
                              () => _deviceId = _deviceId == item.id
                                  ? null
                                  : item.id,
                            ),
                            child: Container(
                              width: 82,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _deviceId == item.id
                                      ? LoopColors.accent
                                      : LoopColors.surfaceHover,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                children: [
                                  ItemThumb(device: item, size: 46),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
