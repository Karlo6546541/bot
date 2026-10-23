import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/live_video.dart';

/// Pozornica: video uživo (kamera domaćina) ili, dok videa nema,
/// [fallback] (fotografija predmeta).
class LiveVideoStage extends StatelessWidget {
  const LiveVideoStage({
    super.key,
    required this.broadcaster,
    required this.watcher,
    required this.fallback,
  });

  final LiveBroadcaster? broadcaster;
  final LiveWatcher? watcher;
  final Widget fallback;

  /// Svaki video zapis dobiva svoj prikaz (nakon okretanja kamere stari
  /// prikaz bi i dalje držao ugašenu kameru).
  static Widget _surface(MediaStream stream, bool mirror) {
    final track = stream.getVideoTracks().firstOrNull;
    return LiveVideoSurface(
      key: ValueKey('${stream.id}/${track?.id}'),
      stream: stream,
      mirror: mirror,
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = broadcaster;
    final w = watcher;
    if (b != null) {
      return ListenableBuilder(
        listenable: Listenable.merge([
          b.stream,
          b.revision,
          b.cameraOn,
          b.front,
        ]),
        builder: (_, _) {
          final stream = b.stream.value;
          return stream == null || !b.cameraOn.value
              ? fallback
              : _surface(stream, b.front.value);
        },
      );
    }
    if (w != null) {
      return ValueListenableBuilder<MediaStream?>(
        valueListenable: w.stream,
        builder: (_, stream, _) =>
            stream == null ? fallback : _surface(stream, false),
      );
    }
    return fallback;
  }
}

/// Prikaz jednog video toka (vlastiti renderer koji se gasi s widgetom).
class LiveVideoSurface extends StatefulWidget {
  const LiveVideoSurface({
    super.key,
    required this.stream,
    required this.mirror,
  });
  final MediaStream stream;
  final bool mirror;

  @override
  State<LiveVideoSurface> createState() => _LiveVideoSurfaceState();
}

class _LiveVideoSurfaceState extends State<LiveVideoSurface> {
  final _renderer = RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _renderer.initialize();
    _renderer.srcObject = widget.stream;
    if (mounted) setState(() => _ready = true);
  }

  @override
  void didUpdateWidget(LiveVideoSurface old) {
    super.didUpdateWidget(old);
    if (_ready && old.stream != widget.stream) {
      _renderer.srcObject = widget.stream;
    }
  }

  @override
  void dispose() {
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_ready
      ? const ColoredBox(color: Colors.black)
      : RTCVideoView(
          _renderer,
          key: const ValueKey('live-video'),
          mirror: widget.mirror,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        );
}
