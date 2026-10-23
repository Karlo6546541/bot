import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Video uživo za live aukcije: kamera domaćina ide izravno gledateljima
/// (WebRTC, peer-to-peer), a uređaji se "upoznaju" porukama preko
/// Supabase Realtime kanala emisije (signalizacija) — bez dodatnog servera.
///
/// Svaki gledatelj dobiva svoju vezu od domaćina, pa je ovo za manji broj
/// gledatelja (desetak, ovisno o uploadu domaćina). Za stotine gledatelja
/// treba media server (npr. LiveKit, Mux ili Agora).
class LiveVideoConfig {
  /// STUN pronalazi javnu adresu uređaja. TURN (neobavezno, preko
  /// --dart-define) prenosi video kad izravna veza nije moguća (neke
  /// mobilne mreže i firme).
  static const _turnUrl = String.fromEnvironment('LIVE_TURN_URL');
  static const _turnUser = String.fromEnvironment('LIVE_TURN_USER');
  static const _turnPass = String.fromEnvironment('LIVE_TURN_PASS');

  static Map<String, dynamic> get rtc => {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
      if (_turnUrl.isNotEmpty)
        {'urls': _turnUrl, 'username': _turnUser, 'credential': _turnPass},
    ],
    'sdpSemantics': 'unified-plan',
  };
}

/// Kanal poruka između domaćina i gledatelja jednog livea.
abstract class LiveSignaling {
  Future<void> join(void Function(Map<String, dynamic> message) onMessage);
  Future<void> send(Map<String, dynamic> message);
  Future<void> leave();
}

/// Signalizacija preko Supabase Realtime "broadcast" kanala (poruke se ne
/// spremaju u bazu).
class SupabaseLiveSignaling implements LiveSignaling {
  SupabaseLiveSignaling(this._client, this.showId);

  final SupabaseClient _client;
  final String showId;
  RealtimeChannel? _channel;

  @override
  Future<void> join(void Function(Map<String, dynamic>) onMessage) async {
    final ready = Completer<void>();
    _channel = _client
        .channel(
          'live-video-$showId',
          opts: const RealtimeChannelConfig(self: false),
        )
        .onBroadcast(event: 'signal', callback: onMessage)
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed &&
              !ready.isCompleted) {
            ready.complete();
          }
        });
    await ready.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    await _channel?.sendBroadcastMessage(event: 'signal', payload: message);
  }

  @override
  Future<void> leave() async {
    final c = _channel;
    _channel = null;
    if (c != null) await _client.removeChannel(c);
  }
}

/// Stvara signalizaciju za live (null = video nije dostupan, npr. bez
/// online baze ili u testovima).
typedef LiveSignalingFactory = LiveSignaling Function(String showId);

/// Čeka da uređaj skupi svoje mrežne adrese (ICE), pa se cijeli opis veze
/// šalje jednom porukom.
Future<RTCSessionDescription?> _gatheredDescription(
  RTCPeerConnection pc,
) async {
  final done = Completer<void>();
  pc.onIceGatheringState = (s) {
    if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
        !done.isCompleted) {
      done.complete();
    }
  };
  if (pc.iceGatheringState ==
      RTCIceGatheringState.RTCIceGatheringStateComplete) {
    return pc.getLocalDescription();
  }
  await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
  return pc.getLocalDescription();
}

/// Najveći protok videa po gledatelju (bit/s): domaćin šalje zasebnu vezu
/// svakom gledatelju, pa se protok smanjuje kako gledatelja ima više (da
/// upload mobitela izdrži).
int videoBitrateFor(int viewers) => switch (viewers) {
  <= 2 => 2500000,
  <= 4 => 1800000,
  <= 7 => 1200000,
  _ => 800000,
};

/// Opis veze s višim početnim protokom: Chrome inače kreće s ~300 kbit/s i
/// prvih desetak sekundi šalje mutnu sliku. Dodaje `x-google-*-bitrate` u
/// parametre video kodeka (VP8/VP9/H264/AV1).
String boostVideoSdp(String sdp, {int startKbps = 1500, int maxKbps = 2500}) {
  final nl = sdp.contains('\r\n') ? '\r\n' : '\n';
  final lines = sdp.split(nl);
  final codec = RegExp(r'^a=rtpmap:(\d+) (VP8|VP9|H264|AV1)/90000');
  final payloads = <String>{
    for (final l in lines)
      if (codec.firstMatch(l) case final m?) m.group(1)!,
  };
  if (payloads.isEmpty) return sdp;
  final extra =
      'x-google-start-bitrate=$startKbps;x-google-max-bitrate=$maxKbps';
  final out = <String>[];
  final withFmtp = <String>{};
  for (final l in lines) {
    final fmtp = RegExp(r'^a=fmtp:(\d+) (.*)$').firstMatch(l);
    if (fmtp != null &&
        payloads.contains(fmtp.group(1)) &&
        !l.contains('x-google-start-bitrate')) {
      out.add('$l;$extra');
      withFmtp.add(fmtp.group(1)!);
    } else {
      out.add(l);
    }
  }
  // Kodeci bez fmtp retka (npr. VP8) dobivaju novi redak iza rtpmap.
  final result = <String>[];
  for (final l in out) {
    result.add(l);
    final m = codec.firstMatch(l);
    if (m != null && !withFmtp.contains(m.group(1))) {
      result.add('a=fmtp:${m.group(1)} $extra');
    }
  }
  return result.join(nl);
}

/// Domaćin: kamera + mikrofon, po jedna veza za svakog gledatelja.
class LiveBroadcaster {
  LiveBroadcaster(this._signaling);

  final LiveSignaling _signaling;
  final _id = const Uuid().v4();
  final _peers = <String, RTCPeerConnection>{};
  Timer? _ready;

  /// Lokalna slika s kamere (za pregled kod domaćina).
  final stream = ValueNotifier<MediaStream?>(null);

  /// Veze s gledateljima (za mjerenje kvalitete u testovima).
  @visibleForTesting
  Iterable<RTCPeerConnection> get peers => _peers.values;

  /// Koliko gledatelja trenutno prima video.
  final watching = ValueNotifier<int>(0);
  final micOn = ValueNotifier<bool>(true);
  final cameraOn = ValueNotifier<bool>(true);

  /// Prednja kamera (pregled je tada zrcaljen, kao u ogledalu).
  final front = ValueNotifier<bool>(true);

  /// Raste kad se video zapis zamijeni (okretanje kamere) — pregled kod
  /// domaćina tada dobiva novi prikaz.
  final revision = ValueNotifier<int>(0);
  bool _stopped = false;

  /// Kamera u punoj kvaliteti (Full HD, 30 sl/s) i u omjeru kakav senzor
  /// stvarno snima (16:9). Mobitel u uspravnom položaju sam okrene sliku.
  /// Uspravni zahtjev (720×1280) tjerao je preglednik da izreže sredinu
  /// senzora — slika je bila zumirana i mutna. `resizeMode: none` zabranjuje
  /// pregledniku rezanje i umjetno smanjivanje slike.
  static Map<String, dynamic> _video(bool front) => {
    'facingMode': front ? 'user' : 'environment',
    'width': {'ideal': 1920},
    'height': {'ideal': 1080},
    'frameRate': {'ideal': 30, 'max': 30},
    'resizeMode': 'none',
  };

  /// Uključuje kameru i počinje slati. Baca grešku ako korisnik ne
  /// dopusti kameru.
  Future<void> start() async {
    final local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': _video(true),
    });
    if (_stopped) {
      for (final t in local.getTracks()) {
        await t.stop();
      }
      return;
    }
    stream.value = local;
    await _signaling.join(_onMessage);
    await _announce();
    _ready = Timer.periodic(const Duration(seconds: 8), (_) => _announce());
  }

  Future<void> _announce() =>
      _signaling.send({'type': 'ready', 'from': _id, 'role': 'host'});

  Future<void> _onMessage(Map<String, dynamic> m) async {
    final from = m['from'] as String?;
    if (from == null || _stopped) return;
    switch (m['type']) {
      case 'hello':
        await _connect(from);
      case 'answer' when m['to'] == _id:
        final pc = _peers[from];
        final sdp = m['sdp'] as String?;
        if (pc == null || sdp == null) return;
        await pc.setRemoteDescription(
          RTCSessionDescription(
            boostVideoSdp(sdp, maxKbps: videoBitrateFor(_peers.length) ~/ 1000),
            m['sdpType'] as String?,
          ),
        );
        await _tuneSenders();
      case 'bye':
        await _drop(from);
    }
  }

  Future<void> _connect(String viewer) async {
    final local = stream.value;
    if (local == null) return;
    await _drop(viewer);
    final pc = await createPeerConnection(LiveVideoConfig.rtc);
    _peers[viewer] = pc;
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _drop(viewer);
      }
      _count();
    };
    for (final t in local.getTracks()) {
      await pc.addTrack(t, local);
    }
    await pc.setLocalDescription(await pc.createOffer());
    final desc = await _gatheredDescription(pc);
    if (desc == null || _peers[viewer] != pc) return;
    await _signaling.send({
      'type': 'offer',
      'from': _id,
      'to': viewer,
      'sdp': desc.sdp,
      'sdpType': desc.type,
    });
  }

  Future<void> _drop(String viewer) async {
    final pc = _peers.remove(viewer);
    _count();
    await pc?.close();
    if (pc != null) await _tuneSenders();
  }

  /// Protok i broj sličica za svaku vezu prema broju gledatelja; slika
  /// ostaje u punoj rezoluciji (bez umjetnog smanjivanja).
  Future<void> _tuneSenders() async {
    final bitrate = videoBitrateFor(_peers.length);
    for (final pc in [..._peers.values]) {
      try {
        for (final sender in await pc.getSenders()) {
          if (sender.track?.kind != 'video') continue;
          final params = sender.parameters;
          final encodings = params.encodings;
          if (encodings == null || encodings.isEmpty) continue;
          for (final e in encodings) {
            e.maxBitrate = bitrate;
            e.maxFramerate = 30;
            e.scaleResolutionDownBy = 1.0;
          }
          params.degradationPreference =
              RTCDegradationPreference.MAINTAIN_RESOLUTION;
          await sender.setParameters(params);
        }
      } catch (_) {
        // Stariji preglednici ne dopuštaju promjenu — ostaje zadano.
      }
    }
  }

  void _count() => watching.value = _peers.values
      .where(
        (p) =>
            p.connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      )
      .length;

  bool _switching = false;

  /// Prednja ↔ stražnja kamera, bez prekida veze s gledateljima.
  /// Baca [LiveCameraException] ako uređaj ima samo jednu kameru.
  Future<void> switchCamera() async {
    final local = stream.value;
    final old = local?.getVideoTracks().firstOrNull;
    if (local == null || old == null || _switching) return;
    if (!kIsWeb) {
      await Helper.switchCamera(old);
      front.value = !front.value;
      return;
    }
    _switching = true;
    try {
      await _switchWeb(local, old);
    } finally {
      _switching = false;
    }
  }

  Future<void> _switchWeb(MediaStream local, MediaStreamTrack old) async {
    final cams = [
      for (final d in await navigator.mediaDevices.enumerateDevices())
        if (d.kind == 'videoinput') d,
    ];
    if (cams.length < 2) throw const LiveCameraException();
    final currentId = old.getSettings()['deviceId'] as String?;
    final wantFront = !front.value;
    // Mobiteli ne daju otvoriti drugu kameru dok je prva uključena.
    await old.stop();

    Future<MediaStreamTrack?> open(Map<String, dynamic> video) async {
      try {
        final s = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': video,
        });
        return s.getVideoTracks().firstOrNull;
      } catch (_) {
        return null;
      }
    }

    String? idOf(MediaStreamTrack t) => t.getSettings()['deviceId'] as String?;

    // 1) Točno prednja/stražnja kamera (mobiteli).
    var track = await open({
      ..._video(wantFront),
      'facingMode': {'exact': wantFront ? 'user' : 'environment'},
    });
    // 2) Inače sljedeća kamera s popisa (računala, neki mobiteli).
    if (track == null || (currentId != null && idOf(track) == currentId)) {
      await track?.stop();
      final i = cams.indexWhere((c) => c.deviceId == currentId);
      final next = cams[(i + 1) % cams.length];
      track = await open({
        ..._video(wantFront)..remove('facingMode'),
        'deviceId': {'exact': next.deviceId},
      });
    }
    if (track == null) {
      // Vrati staru kameru da domaćin ne ostane bez slike.
      track = await open({
        ..._video(front.value)..remove('facingMode'),
        if (currentId != null) 'deviceId': {'exact': currentId},
      });
      if (track != null) await _useTrack(local, old, track, front.value);
      throw const LiveCameraException(failed: true);
    }
    final facing = track.getSettings()['facingMode'];
    final label = cams
        .where((c) => c.deviceId == idOf(track!))
        .map((c) => c.label.toLowerCase())
        .firstOrNull;
    final isFront = facing is String
        ? facing == 'user'
        : label != null && (label.contains('front') || label.contains('user'))
        ? true
        : label != null && (label.contains('back') || label.contains('rear'))
        ? false
        : wantFront;
    await _useTrack(local, old, track, isFront);
  }

  /// Nova kamera u svim vezama (gledateljima se slika samo promijeni) i u
  /// pregledu kod domaćina.
  Future<void> _useTrack(
    MediaStream local,
    MediaStreamTrack old,
    MediaStreamTrack track,
    bool isFront,
  ) async {
    track.enabled = cameraOn.value;
    for (final pc in _peers.values) {
      for (final sender in await pc.getSenders()) {
        if (sender.track?.kind == 'video') await sender.replaceTrack(track);
      }
    }
    await local.removeTrack(old);
    await local.addTrack(track);
    front.value = isFront;
    revision.value++;
  }

  void toggleMic() {
    final on = !micOn.value;
    for (final t in stream.value?.getAudioTracks() ?? const []) {
      t.enabled = on;
    }
    micOn.value = on;
  }

  void toggleCamera() {
    final on = !cameraOn.value;
    for (final t in stream.value?.getVideoTracks() ?? const []) {
      t.enabled = on;
    }
    cameraOn.value = on;
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _ready?.cancel();
    try {
      await _signaling.send({'type': 'bye', 'from': _id, 'role': 'host'});
    } catch (_) {}
    for (final id in [..._peers.keys]) {
      await _drop(id);
    }
    final local = stream.value;
    stream.value = null;
    for (final t in local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await local?.dispose();
    await _signaling.leave();
  }
}

/// Stanje videa kod gledatelja.
enum LiveVideoStatus { connecting, playing, offline }

/// Gledatelj: traži video od domaćina i prikazuje ga.
class LiveWatcher {
  LiveWatcher(this._signaling);

  final LiveSignaling _signaling;
  final _id = const Uuid().v4();
  RTCPeerConnection? _pc;
  Timer? _retry;
  Timer? _noHost;
  bool _stopped = false;

  /// Kad je stigla zadnja ponuda veze — dok se veza uspostavlja, ne traži
  /// novu (inače bi se veza stalno prekidala).
  DateTime? _negotiating;

  final stream = ValueNotifier<MediaStream?>(null);
  final status = ValueNotifier<LiveVideoStatus>(LiveVideoStatus.connecting);

  /// Veza s domaćinom (za mjerenje kvalitete u testovima).
  @visibleForTesting
  RTCPeerConnection? get peer => _pc;

  Future<void> start() async {
    await _signaling.join(_onMessage);
    await _hello();
    // Dok video ne krene, ponovno se javi (domaćin je možda tek ušao).
    _retry = Timer.periodic(const Duration(seconds: 6), (_) => _maybeHello());
    // Domaćin se ne javlja → video trenutno nije uključen.
    _noHost = Timer(const Duration(seconds: 12), () {
      if (status.value == LiveVideoStatus.connecting && _negotiating == null) {
        status.value = LiveVideoStatus.offline;
      }
    });
  }

  Future<void> _hello() =>
      _signaling.send({'type': 'hello', 'from': _id, 'role': 'viewer'});

  Future<void> _maybeHello() async {
    if (_stopped || status.value == LiveVideoStatus.playing) return;
    final since = _negotiating;
    if (since != null &&
        DateTime.now().difference(since) < const Duration(seconds: 15)) {
      return;
    }
    await _hello();
  }

  Future<void> _onMessage(Map<String, dynamic> m) async {
    if (_stopped) return;
    switch (m['type']) {
      case 'ready':
        await _maybeHello();
      case 'offer' when m['to'] == _id:
        await _answer(m);
      case 'bye' when m['role'] == 'host':
        await _close();
        _negotiating = null;
        status.value = LiveVideoStatus.offline;
    }
  }

  Future<void> _answer(Map<String, dynamic> m) async {
    await _close();
    _negotiating = DateTime.now();
    status.value = LiveVideoStatus.connecting;
    final pc = await createPeerConnection(LiveVideoConfig.rtc);
    _pc = pc;
    pc.onTrack = (e) {
      if (e.streams.isEmpty) return;
      final remote = e.streams.first;
      // Slika se prikazuje kad stigne video (zvuk je u istom toku); ako
      // zvuk stigne poslije, tok se ponovno postavlja da ga preglednik
      // pusti.
      if (remote.getVideoTracks().isEmpty) return;
      if (stream.value == remote) stream.value = null;
      stream.value = remote;
      status.value = LiveVideoStatus.playing;
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _negotiating = null;
        status.value = LiveVideoStatus.connecting;
      }
    };
    await pc.setRemoteDescription(
      RTCSessionDescription(m['sdp'] as String?, m['sdpType'] as String?),
    );
    await pc.setLocalDescription(await pc.createAnswer());
    final desc = await _gatheredDescription(pc);
    if (desc == null || _pc != pc) return;
    await _signaling.send({
      'type': 'answer',
      'from': _id,
      'to': m['from'],
      'sdp': desc.sdp,
      'sdpType': desc.type,
    });
  }

  Future<void> _close() async {
    final pc = _pc;
    _pc = null;
    stream.value = null;
    await pc?.close();
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _retry?.cancel();
    _noHost?.cancel();
    try {
      await _signaling.send({'type': 'bye', 'from': _id, 'role': 'viewer'});
    } catch (_) {}
    await _close();
    await _signaling.leave();
  }
}

/// Kamera se ne može okrenuti: uređaj ima samo jednu kameru ([failed] =
/// druga kamera se nije uspjela uključiti).
class LiveCameraException implements Exception {
  const LiveCameraException({this.failed = false});
  final bool failed;
}
