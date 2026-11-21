import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Future<bool> showStripePayment(BuildContext context, Map<String, dynamic> settings) async =>
    await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => SizedBox(height: MediaQuery.sizeOf(context).height * .8,
        child: _StripePayment(settings: settings)),
    ) ?? false;

class _StripePayment extends StatefulWidget {
  const _StripePayment({required this.settings});
  final Map<String, dynamic> settings;
  @override
  State<_StripePayment> createState() => _StripePaymentState();
}
class _StripePaymentState extends State<_StripePayment> {
  static int _counter = 0;
  late final String _view = 'subhasto-payment-${_counter++}';
  late final web.HTMLIFrameElement _frame;
  late final JSFunction _listener;
  @override
  void initState() {
    super.initState();
    _frame = web.HTMLIFrameElement()
      ..src = Uri.base.resolve('stripe-payment.html').toString()
      ..allow = 'payment' ..title = 'Sigurno spremanje kartice';
    _frame.style.border = '0'; _frame.style.width = '100%'; _frame.style.height = '100%';
    _listener = ((web.MessageEvent event) {
      if (event.origin != web.window.location.origin || event.source != _frame.contentWindow) return;
      final raw = event.data.dartify();
      if (raw is! String) return;
      try {
        final data = jsonDecode(raw);
        if (data is! Map) return;
        if (data['type'] == 'subhasto-payment-ready') {
          _frame.contentWindow?.postMessage(jsonEncode(widget.settings).toJS, web.window.location.origin.toJS);
        } else if (data['type'] == 'subhasto-payment-complete' && mounted) {
          Navigator.pop(context, true);
        }
      } on FormatException { /* Ignore unrelated browser messages. */ }
    }).toJS;
    web.window.addEventListener('message', _listener);
    ui_web.platformViewRegistry.registerViewFactory(_view, (_) => _frame);
  }
  @override
  void dispose() {
    web.window.removeEventListener('message', _listener); _frame.src = 'about:blank';
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _view);
}
