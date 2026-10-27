import 'package:flutter/material.dart';

/// Includes modal sheets as well as full screen routes.
final feedRouteObserver = RouteObserver<ModalRoute<dynamic>>();

/// Only accumulates time while the feed is visible and the app is resumed.
class FeedWatchTime {
  FeedWatchTime({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  DateTime? _started;
  Duration _elapsed = Duration.zero;

  void setVisible(bool visible) {
    if (visible && _started == null) {
      _started = _now();
    } else if (!visible && _started != null) {
      _elapsed += _now().difference(_started!);
      _started = null;
    }
  }

  Duration take() {
    final at = _now();
    final value = _elapsed +
        (_started == null ? Duration.zero : at.difference(_started!));
    _elapsed = Duration.zero;
    if (_started != null) _started = at;
    return value;
  }
}
