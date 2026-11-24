import 'package:dart_webrtc/dart_webrtc.dart' as web_rtc;
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// "detail": preglednik pri slaboj vezi ili zauzetom procesoru radije
/// smanji broj sličica nego oštrinu — kartice, natpisi i sitni detalji
/// predmeta ostaju čitljivi (zadano je mutnija slika).
void preferDetail(MediaStreamTrack track) {
  if (track is web_rtc.MediaStreamTrackWeb && track.kind == 'video') {
    track.jsTrack.contentHint = 'detail';
  }
}
