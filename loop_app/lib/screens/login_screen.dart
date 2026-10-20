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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: LoopLogo(size: 40)),
                    const SizedBox(height: 8),
                    const Text(
                      "Trade. Don't sell.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 40),
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('Prijavi se'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _run(
                              () =>
                                  ref.read(appProvider.notifier).loginAsGuest(),
                            ),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Nastavi kao gost'),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _loading ? null : _adminLogin,
                      icon: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: LoopColors.admin,
                      ),
                      label: const Text(
                        'Admin prijava',
                        style: TextStyle(color: LoopColors.admin),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: LoopColors.surface,
                        borderRadius: BorderRadius.circular(kRadius),
                      ),
                      child: const Text(
                        'Demo verzija — bilo koji e-mail i lozinka rade.\n'
                        'Demo računi: demo@loop.com · test@loop.com\n'
                        'Novi računi dobivaju ${TradeService.welcomeCredits} '
                        'LOOP kredita.',
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
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
      title: const Row(
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
