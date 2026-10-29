import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class CloudLiveMedia extends StatefulWidget {
  const CloudLiveMedia({super.key, required this.connection});
  final Map<String, dynamic> connection;
  @override
  State<CloudLiveMedia> createState() => _CloudLiveMediaState();
}
class _CloudLiveMediaState extends State<CloudLiveMedia> {
  static int _counter = 0;
  late final String _view = 'cloud-live-${_counter++}';
  late final web.HTMLIFrameElement _frame;
  late final JSFunction _listener;
  @override
  void initState() {
    super.initState();
    _frame = web.HTMLIFrameElement()
      ..src = Uri.base.resolve('live-player.html').toString()
      ..allow = 'camera; microphone; autoplay; fullscreen'
      ..title = 'Prijenos uživo';
    _frame.style.border = '0';
    _frame.style.width = '100%';
    _frame.style.height = '100%';
    _listener = ((web.MessageEvent event) {
      if (event.origin != web.window.location.origin ||
          event.source != _frame.contentWindow) return;
      if (event.data.dartify() == 'subhasto-player-ready') {
        _frame.contentWindow?.postMessage(
          jsonEncode(widget.connection).toJS, web.window.location.origin.toJS,
        );
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
    ui_web.platformViewRegistry.registerViewFactory(_view, (_) => _frame);
  }
  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    _frame.src = 'about:blank';
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _view);
}
