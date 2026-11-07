import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../screens/live_screens.dart';
import '../services/live_service.dart';
import '../services/live_video.dart';
import 'formatters.dart';
import 'item_image.dart';
import 'live_video_view.dart';

/// Navigator cijele aplikacije — mini live je iznad njega pa preko
/// ovog ključa otvara sobu. Svaka izgradnja aplikacije (tema, jezik) ima
/// svoj ključ (vidi [navigatorKeyFor]).
GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final _navigatorKeys = <Object, GlobalKey<NavigatorState>>{};

/// Ključ navigatora za danu izgradnju aplikacije (i postavlja ga kao
/// [rootNavigatorKey]).
GlobalKey<NavigatorState> navigatorKeyFor(Object build) => rootNavigatorKey =
    _navigatorKeys.putIfAbsent(build, GlobalKey<NavigatorState>.new);

/// Live koji se gleda u malom prozoru (null = nema).
final miniLiveProvider = NotifierProvider<MiniLive, String?>(MiniLive.new);

class MiniLive extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String showId) => state = showId;
  void hide() => state = null;
}

/// Mali prozor s liveom (kao na Whatnotu / YouTubeu): nakon izlaska iz
/// sobe live se gleda dalje dok korisnik razgledava i kupuje. Može se
/// povlačiti po ekranu, ✕ ga gasi, a dodir vraća u sobu.
class MiniLiveOverlay extends ConsumerWidget {
  const MiniLiveOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(miniLiveProvider);
    if (id == null) return const SizedBox.shrink();
    return _MiniLive(key: ValueKey(id), showId: id);
  }
}

class _MiniLive extends ConsumerStatefulWidget {
  const _MiniLive({super.key, required this.showId});
  final String showId;

  @override
  ConsumerState<_MiniLive> createState() => _MiniLiveState();
}

class _MiniLiveState extends ConsumerState<_MiniLive> {
  static const _w = 124.0;
  static const _h = 200.0;

  /// Gornji lijevi kut prozora (null = zadano dolje desno).
  Offset? _pos;
  LiveWatcher? _watcher;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final every = ref.read(tickIntervalProvider);
    if (every != null) {
      _timer = Timer.periodic(every, (_) {
        if (mounted) setState(() {});
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _startVideo());
  }

  Future<void> _startVideo() async {
    final signaling = ref.read(liveSignalingProvider);
    final show = ref.read(appProvider).liveShowById(widget.showId);
    if (!mounted || signaling == null || show == null || !show.video) return;
    final w = LiveWatcher(signaling(show.id));
    setState(() => _watcher = w);
    try {
      await w.start();
    } catch (_) {
      // Bez videa ostaje slika predmeta.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _watcher?.stop();
    super.dispose();
  }

  void _close() => ref.read(miniLiveProvider.notifier).hide();

  void _open() {
    final nav = rootNavigatorKey.currentState;
    _close();
    nav?.push(
      MaterialPageRoute<void>(
        builder: (_) => LiveRoomScreen(showId: widget.showId),
      ),
    );
  }

  /// Zadržava prozor na ekranu i "lijepi" ga uz bliži bočni rub.
  Offset _clamp(Offset p, Size screen, EdgeInsets pad, {bool snap = false}) {
    final minX = 8.0;
    final maxX = screen.width - _w - 8;
    final minY = pad.top + 8;
    final maxY = screen.height - _h - pad.bottom - 80;
    var x = p.dx.clamp(minX, maxX < minX ? minX : maxX);
    final y = p.dy.clamp(minY, maxY < minY ? minY : maxY);
    if (snap) x = x + _w / 2 < screen.width / 2 ? minX : maxX;
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final show = s.liveShowById(widget.showId);
    final now = DateTime.now();
    final LiveState? st = show == null ? null : s.liveStateOf(show, now);
    // Live je završio ili ga je korisnik sam vodio — prozor se gasi.
    if (show == null ||
        st == null ||
        st.isOver ||
        s.currentUserId == null ||
        show.hostId == s.currentUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context);
    final screen = media.size;
    final pos = _clamp(
      _pos ?? Offset(screen.width - _w - 12, screen.height - _h - 150),
      screen,
      media.padding,
    );
    final cur = st.current;
    final lot = cur ?? st.lastDone ?? st.next;
    final device = lot == null ? null : s.deviceById(lot.lot.deviceId);
    final Widget fallback = switch ((cur, show.coverPath)) {
      (null, final cover?) => LocalPhoto(
        path: cover,
        fallback: const ColoredBox(color: Colors.black),
      ),
      _ when device != null => FittedBox(
        fit: BoxFit.cover,
        child: ItemThumb(device: device, size: _h),
      ),
      _ => const ColoredBox(color: Colors.black),
    };
    final left = cur?.left(now);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        key: const ValueKey('mini-live'),
        onTap: _open,
        // Pomaci se zbrajaju na zadnji položaj (više pomaka u istom okviru).
        onPanUpdate: (d) => setState(
          () => _pos = _clamp((_pos ?? pos) + d.delta, screen, media.padding),
        ),
        onPanEnd: (_) => setState(
          () => _pos = _clamp(_pos ?? pos, screen, media.padding, snap: true),
        ),
        child: Material(
          elevation: 10,
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: _w,
            height: _h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                LiveVideoStage(
                  broadcaster: null,
                  watcher: _watcher,
                  fallback: fallback,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black45,
                        Colors.transparent,
                        Colors.black87,
                      ],
                      stops: [0, 0.4, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: kLiveRed,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      t('UŽIVO'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  // Bez tooltipa: prozor je iznad navigatora (nema Overlay).
                  child: IconButton(
                    key: const ValueKey('mini-live-close'),
                    visualDensity: VisualDensity.compact,
                    onPressed: _close,
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cur?.lot.deviceName ?? show.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (cur != null)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatCredits(cur.price),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (left != null)
                              Text(
                                '0:${left.inSeconds.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  color: left.inSeconds <= 10
                                      ? kLiveRed
                                      : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                          ],
                        )
                      else
                        Text(
                          t('Čeka se sljedeći predmet'),
                          maxLines: 2,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
