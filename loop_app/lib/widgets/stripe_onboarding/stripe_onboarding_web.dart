import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../l10n/tr.dart';

/// Potvrda prodavača (identitet i IBAN) u ugrađenoj Stripe komponenti —
/// unutar aplikacije, bez odlaska na Stripeovu stranicu. Vraća `true` kad
/// korisnik završi ili zatvori obrazac (stanje se zatim provjerava na
/// poslužitelju).
Future<bool> showStripeOnboarding(
  BuildContext context,
  Map<String, dynamic> settings,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .92,
        child: _StripeOnboarding(settings: settings),
      ),
    ) ??
    false;

class _StripeOnboarding extends StatefulWidget {
  const _StripeOnboarding({required this.settings});
  final Map<String, dynamic> settings;

  @override
  State<_StripeOnboarding> createState() => _StripeOnboardingState();
}

class _StripeOnboardingState extends State<_StripeOnboarding> {
  static int _counter = 0;
  late final String _view = 'subhasto-onboarding-${_counter++}';
  late final web.HTMLIFrameElement _frame;
  late final JSFunction _listener;

  @override
  void initState() {
    super.initState();
    _frame = web.HTMLIFrameElement()
      ..src = Uri.base.resolve('stripe-connect.html').toString()
      ..allow = 'camera; clipboard-write'
      ..title = 'Potvrda prodavača';
    _frame.style.border = '0';
    _frame.style.width = '100%';
    _frame.style.height = '100%';
    _listener = ((web.MessageEvent event) {
      if (event.origin != web.window.location.origin ||
          event.source != _frame.contentWindow) {
        return;
      }
      final raw = event.data.dartify();
      if (raw is! String) return;
      try {
        final data = jsonDecode(raw);
        if (data is! Map) return;
        if (data['type'] == 'subhasto-connect-ready') {
          _frame.contentWindow?.postMessage(
            jsonEncode(widget.settings).toJS,
            web.window.location.origin.toJS,
          );
        } else if (data['type'] == 'subhasto-connect-exit' && mounted) {
          Navigator.pop(context, true);
        }
      } on FormatException {
        /* Nevezane poruke preglednika. */
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
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                t('Potvrda za isplate'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('Gotovo')),
            ),
          ],
        ),
      ),
      Expanded(child: HtmlElementView(viewType: _view)),
    ],
  );
}
