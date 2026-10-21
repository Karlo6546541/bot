import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_shell.dart';
import '../widgets/trade_actions.dart';

/// Demo prijava: bilo koji e-mail i lozinka rade.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController(text: 'demo@loop.com');
  final _password = TextEditingController(text: 'demo');
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _login() {
    if (!_formKey.currentState!.validate()) return;
    _run(
      () => ref.read(appProvider.notifier).login(_email.text, _password.text),
    );
  }

  Future<void> _adminLogin() async {
    final creds = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _AdminLoginDialog(),
    );
    if (creds == null) return;
    await _run(
      () => ref.read(appProvider.notifier).adminLogin(creds.$1, creds.$2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final formCard = Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius * 1.6),
        boxShadow: LoopColors.softShadow,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Prijava',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Dobro došao natrag! Demo: bilo koja lozinka radi.',
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.alternate_email),
              ),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Unesi ispravan e-mail'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Lozinka',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Unesi lozinku' : null,
              onFieldSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Prijavi se'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () => _run(
                      () => ref.read(appProvider.notifier).loginAsGuest(),
                    ),
              icon: const Icon(Icons.person_outline),
              label: const Text('Nastavi kao gost'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _loading ? null : _adminLogin,
              icon: Icon(
                Icons.admin_panel_settings_outlined,
                color: LoopColors.admin,
              ),
              label: Text(
                'Admin prijava',
                style: TextStyle(color: LoopColors.admin),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: LoopColors.background,
                borderRadius: BorderRadius.circular(kRadius),
              ),
              child: Text(
                'Demo verzija — bilo koji e-mail i lozinka rade.\n'
                'Demo računi: demo@loop.com · test@loop.com\n'
                'Novi računi dobivaju ${TradeService.welcomeCredits} '
                'LOOP kredita.',
                style: TextStyle(color: LoopColors.textSecondary, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: wide
                  ? Row(
                      children: [
                        const Expanded(child: _WelcomeHero()),
                        const SizedBox(width: 40),
                        Expanded(child: Center(child: formCard)),
                      ],
                    )
                  : Column(
                      children: [
                        const _WelcomeHero(compact: true),
                        const SizedBox(height: 24),
                        formCard,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminLoginDialog extends StatefulWidget {
  const _AdminLoginDialog();

  @override
  State<_AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<_AdminLoginDialog> {
  final _email = TextEditingController(text: TradeService.adminEmail);
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, (_email.text, _password.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.admin_panel_settings, color: LoopColors.admin),
          SizedBox(width: 8),
          Text('Admin prijava'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Admin e-mail'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Lozinka',
                helperText: 'Demo: admin123',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: LoopColors.admin,
            minimumSize: const Size(0, 44),
          ),
          child: const Text('Prijava'),
        ),
      ],
    );
  }
}

/// Prijateljski uvod: logo, poruka i "oblak" kategorija.
class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({this.compact = false});
  final bool compact;

  static const _bubbles = [
    ('📱', 'Mobiteli'),
    ('🎸', 'Instrumenti'),
    ('🧶', 'Rukotvorine'),
    ('🃏', 'Kartice'),
    ('📚', 'Knjige'),
    ('🎮', 'Konzole'),
    ('🏺', 'Keramika'),
    ('🎟️', 'Doživljaji'),
  ];

  @override
  Widget build(BuildContext context) {
    final pastel = [
      LoopColors.peach,
      LoopColors.sunny,
      LoopColors.mint,
      LoopColors.lilac,
      LoopColors.sky,
    ];
    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        LoopLogo(size: compact ? 34 : 40),
        const SizedBox(height: 18),
        Text(
          'Mijenjaj stvari,\nne novac.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 30 : 48,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Trade. Don't sell. Prodaj ono što ne koristiš, dobij LOOP kredite "
          'i uzmi nešto novo — od mobitela do ručno rađene keramike.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: LoopColors.textSecondary,
            fontSize: compact ? 15 : 17,
            height: 1.4,
          ),
        ),
        SizedBox(height: compact ? 14 : 22),
        // Mobitel: jedan vodoravno pomični red, da obrazac stane na ekran.
        if (compact)
          SizedBox(
            height: 40,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _bubbles.length; i++)
                    // Lagano "plutanje" mjehurića pri otvaranju.
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 400 + i * 70),
                        curve: Curves.easeOutBack,
                        builder: (_, t, child) => Transform.scale(
                          scale: 0.6 + 0.4 * t,
                          child: Opacity(opacity: t.clamp(0, 1), child: child),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: pastel[i % pastel.length],
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${_bubbles[i].$1}  ${_bubbles[i].$2}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          )
        else
          Wrap(
            alignment: compact ? WrapAlignment.center : WrapAlignment.start,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _bubbles.length; i++)
                // Lagano "plutanje" mjehurića pri otvaranju.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 400 + i * 70),
                  curve: Curves.easeOutBack,
                  builder: (_, t, child) => Transform.scale(
                    scale: 0.6 + 0.4 * t,
                    child: Opacity(opacity: t.clamp(0, 1), child: child),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: pastel[i % pastel.length],
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_bubbles[i].$1}  ${_bubbles[i].$2}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
