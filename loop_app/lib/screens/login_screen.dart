import '../services/app_location/app_location.dart';
import 'package:flutter/material.dart';
import '../widgets/country_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/account_service.dart';
import '../services/seed_data.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_shell.dart';
import '../widgets/trade_actions.dart';
import '../widgets/username_field.dart';
import 'legal_screen.dart';
import '../l10n/tr.dart';
import '../widgets/language_button.dart';

/// Prijava i registracija (e-mail + lozinka, Google na webu s online
/// bazom), gost i admin.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.reason});

  /// Otvoreno preko aplikacije (gost je htio kupiti, prodati…): razlog
  /// se prikaže gore, a "X" vraća na razgledavanje. Nakon prijave ekran
  /// se sam zatvori i korisnik ostaje gdje je bio.
  final String? reason;

  /// Otvara prijavu/registraciju preko trenutnog ekrana.
  static Future<void> open(BuildContext context, {String? reason}) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => LoginScreen(reason: reason ?? ''),
        ),
      );

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _loginKey = GlobalKey<FormState>();
  final _registerKey = GlobalKey<FormState>();
  late final TextEditingController _identifier;
  late final TextEditingController _password;
  final _regEmail = TextEditingController();
  final _regUsername = TextEditingController();
  final _regPassword = TextEditingController();
  // Gost koji je htio nešto napraviti najčešće još nema račun.
  late bool _register = widget.reason != null;

  /// Država novog računa.
  String _regCountry = 'HR';

  bool get _overlay => widget.reason != null;
  bool _loading = false;
  bool _obscure = true;

  bool get _online => ref.read(authBackendProvider).isOnline;

  @override
  void initState() {
    super.initState();
    // Odmah (ne lijeno): inače bi ih dispose stvarao nakon odmontiranja.
    _identifier = TextEditingController(text: _online ? '' : 'demo@loop.com');
    _password = TextEditingController(
      text: _online ? '' : SeedData.demoPassword,
    );
  }

  @override
  void dispose() {
    for (final c in [
      _identifier,
      _password,
      _regEmail,
      _regUsername,
      _regPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } on UsernameTakenException catch (e) {
      showLoopSnackBar(
        e.suggestions.isEmpty
            ? e.message
            : '${e.message} ${t('Probaj: {0}', [e.suggestions.map((s) => '@$s').join(', ')])}',
        error: true,
      );
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } catch (e) {
      showLoopSnackBar(t('Greška: {0}', [e]), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _login() {
    if (!_loginKey.currentState!.validate()) return;
    _run(() async {
      await ref
          .read(appProvider.notifier)
          .login(_identifier.text, _password.text);
    });
  }

  void _doRegister() {
    if (!_registerKey.currentState!.validate()) return;
    _run(() async {
      final result = await ref
          .read(appProvider.notifier)
          .register(
            email: _regEmail.text,
            password: _regPassword.text,
            username: _regUsername.text,
            country: _regCountry,
          );
      if (result is NeedsEmailConfirmation && mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.mark_email_unread_outlined, size: 40),
            title: Text(t('Provjeri e-mail')),
            content: Text(
              t(
                'Poslali smo link za potvrdu na {0}. Otvori ga na ovom uređaju i bit ćeš prijavljen.',
                [result.email],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('U redu')),
              ),
            ],
          ),
        );
        if (mounted) {
          setState(() {
            _register = false;
            _identifier.text = result.email;
            _password.clear();
          });
        }
      }
    });
  }

  Future<void> _google() =>
      _run(() => ref.read(appProvider.notifier).signInWithGoogle());

  Future<void> _forgotPassword() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(
        initialEmail: _identifier.text.contains('@') ? _identifier.text : '',
        online: _online,
      ),
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

  Widget _passwordField(TextEditingController c, {VoidCallback? onSubmit}) =>
      TextFormField(
        controller: c,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: t('Lozinka'),
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            tooltip: _obscure ? t('Prikaži lozinku') : t('Sakrij lozinku'),
            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        validator: (v) => (v == null || v.isEmpty) ? t('Unesi lozinku') : null,
        onFieldSubmitted: (_) => onSubmit?.call(),
      );

  Widget _loadingOr(String label) => _loading
      ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        )
      : Text(label);

  List<Widget> _loginFields() => [
    TextFormField(
      controller: _identifier,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: _online ? t('E-mail') : t('E-mail ili korisničko ime'),
        prefixIcon: const Icon(Icons.alternate_email),
      ),
      validator: (v) => (v == null || v.trim().isEmpty)
          ? t('Upiši e-mail ili korisničko ime.')
          : null,
    ),
    const SizedBox(height: 12),
    _passwordField(_password, onSubmit: _login),
    Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: _loading ? null : _forgotPassword,
        child: Text(t('Zaboravljena lozinka?')),
      ),
    ),
    const SizedBox(height: 4),
    FilledButton(
      onPressed: _loading ? null : _login,
      child: _loadingOr(t('Prijavi se')),
    ),
  ];

  List<Widget> _registerFields() => [
    TextFormField(
      controller: _regEmail,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: t('E-mail'),
        prefixIcon: const Icon(Icons.alternate_email),
      ),
      validator: (v) => AccountService.validateEmail(v ?? ''),
    ),
    const SizedBox(height: 12),
    UsernameField(controller: _regUsername),
    const SizedBox(height: 12),
    CountryField(
      value: _regCountry,
      onChanged: (c) => setState(() => _regCountry = c),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _regPassword,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: t('Lozinka'),
        helperText: t('Barem {0} znakova', [AccountService.minPassword]),
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _obscure ? t('Prikaži lozinku') : t('Sakrij lozinku'),
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator: (v) => AccountService.validatePassword(v ?? ''),
    ),
    const SizedBox(height: 8),
    // Obvezan pristanak: Uvjeti i Pravila privatnosti (bez dobne granice).
    FormField<bool>(
      key: const ValueKey('accept-terms-field'),
      initialValue: false,
      validator: (v) =>
          v == true ? null : t('Za registraciju prihvati Uvjete korištenja.'),
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vlastiti Material: kartica obrasca ima pozadinsku boju.
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              key: const ValueKey('accept-terms'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: field.value ?? false,
              onChanged: (v) => field.didChange(v),
              title: Text(
                t('Prihvaćam Uvjete korištenja i Pravila privatnosti.'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          if (field.hasError)
            Text(
              field.errorText!,
              style: TextStyle(color: LoopColors.error, fontSize: 12),
            ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    FilledButton(
      key: const ValueKey('register-submit'),
      onPressed: _loading ? null : _doRegister,
      child: _loadingOr(t('Napravi račun')),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_overlay) {
      // Prijavljen (ili čeka korisničko ime) → natrag gdje je bio.
      ref.listen(
        appProvider.select(
          (s) =>
              (s.currentUser != null && !s.currentUser!.isGuest) ||
              s.pendingSignup != null ||
              s.isAdmin,
        ),
        (_, done) {
          if (done && mounted) {
            Navigator.of(context).maybePop();
            // Ako je korisnik ostao na istom mjestu, povratak ne treba.
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => AppLocation.clearReturnIfHere(),
            );
          }
        },
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final backend = ref.watch(authBackendProvider);
    final formCard = Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius * 1.6),
        boxShadow: LoopColors.softShadow,
      ),
      child: Form(
        key: _register ? _registerKey : _loginKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(t('Prijava'))),
                ButtonSegment(value: true, label: Text(t('Registracija'))),
              ],
              selected: {_register},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _register = s.first),
            ),
            const SizedBox(height: 18),
            Text(
              _register ? t('Novi račun') : t('Dobro došao natrag!'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              _register
                  ? t('Treba ti samo e-mail i lozinka.')
                  : t('Prijavi se e-mailom i lozinkom.'),
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            const SizedBox(height: 18),
            ...(_register ? _registerFields() : _loginFields()),
            if (backend.supportsGoogle) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      t('ili'),
                      style: TextStyle(color: LoopColors.textSecondary),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _loading ? null : _google,
                icon: const Text(
                  'G',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Color(0xFF4285F4),
                  ),
                ),
                label: Text(t('Nastavi s Googleom')),
              ),
            ],
            if (!backend.isOnline && !_register) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                key: const ValueKey('try-demo'),
                onPressed: _loading
                    ? null
                    : () {
                        _identifier.text = 'demo@loop.com';
                        _password.text = SeedData.demoPassword;
                        _login();
                      },
                icon: const Icon(Icons.rocket_launch_outlined),
                label: Text(t('Isprobaj demo račun')),
              ),
            ],
            const SizedBox(height: 12),
            if (_overlay)
              OutlinedButton.icon(
                key: const ValueKey('login-back'),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
                label: Text(t('Nastavi razgledavati')),
              )
            else
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () => _run(
                        () => ref.read(appProvider.notifier).loginAsGuest(),
                      ),
                icon: const Icon(Icons.person_outline),
                label: Text(t('Samo razgledaj (gost)')),
              ),
            const SizedBox(height: 8),
            // Admin je za tim — neupadljiva poveznica.
            if (!_overlay)
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: LoopColors.textSecondary,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _loading ? null : _adminLogin,
                  child: Text(t('Admin prijava')),
                ),
              ),
            const SizedBox(height: 8),
            const LegalLinks(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: LoopColors.background,
                borderRadius: BorderRadius.circular(kRadius),
              ),
              child: Text(
                backend.isOnline
                    ? t(
                        'Online testna verzija: napravi račun e-mailom ili Googleom. Gost može samo razgledavati.',
                      )
                    : t(
                        'Demo računi: demo@loop.com ili @demo, test@loop.com — lozinka: demo.\nPodaci i lozinke su samo na ovom uređaju.',
                      ),
                style: TextStyle(color: LoopColors.textSecondary, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
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
                            if (_overlay)
                              _ReasonBanner(widget.reason!, register: _register)
                            else
                              const _WelcomeHero(compact: true),
                            const SizedBox(height: 24),
                            formCard,
                          ],
                        ),
                ),
              ),
            ),
            const Positioned(top: 12, right: 12, child: LanguageButton()),
            if (_overlay)
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  key: const ValueKey('login-close'),
                  tooltip: t('Nastavi razgledavati'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ),
          ],
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
          Text(t('Admin prijava')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _email,
              decoration: InputDecoration(labelText: t('Admin e-mail')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: t('Lozinka'),
                helperText: t('Demo: admin123'),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Odustani')),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: LoopColors.admin,
            minimumSize: const Size(0, 44),
          ),
          child: Text(t('Prijava')),
        ),
      ],
    );
  }
}

/// Prijateljski uvod: logo, poruka i "oblak" kategorija.
class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({this.compact = false});
  final bool compact;

  static List<(String, String)> get _bubbles => [
    ('🔴', t('Uživo')),
    ('🃏', t('Kartice')),
    ('👟', t('Tenisice')),
    ('📱', t('Mobiteli')),
    ('📚', t('Knjige')),
    ('🎮', t('Konzole')),
    ('🏺', t('Keramika')),
    ('🎟️', t('Doživljaji')),
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
          t('Licitiraj uživo.\nKupi odmah.'),
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 30 : 48,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          t(
            'Live aukcije, aukcije i Kupi odmah na jednom mjestu — od kartica i tenisica do mobitela i vintage stvari.',
          ),
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

/// Zaboravljena lozinka: online šalje link na e-mail, lokalno odmah
/// postavlja novu lozinku (podaci su samo na ovom uređaju).
class _ForgotPasswordDialog extends ConsumerStatefulWidget {
  const _ForgotPasswordDialog({
    required this.initialEmail,
    required this.online,
  });
  final String initialEmail;
  final bool online;

  @override
  ConsumerState<_ForgotPasswordDialog> createState() =>
      _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends ConsumerState<_ForgotPasswordDialog> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final c = ref.read(appProvider.notifier);
    try {
      if (widget.online) {
        await c.requestPasswordReset(_email.text);
        setState(() => _sent = true);
      } else {
        await c.resetPasswordLocally(_email.text, _password.text);
        if (mounted) Navigator.pop(context);
        showLoopSnackBar(t('Nova lozinka je postavljena. Prijavi se.'));
      }
    } on TradeException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = t('Greška: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Zaboravljena lozinka')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: _sent
            ? Text(
                t(
                  'Ako postoji račun za {0}, poslali smo link za novu lozinku. Otvori ga na ovom uređaju.',
                  [_email.text.trim()],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.online
                        ? t(
                            'Upiši e-mail računa i poslat ćemo ti link za novu lozinku.',
                          )
                        : t(
                            'Lokalni način: računi su samo na ovom uređaju, pa novu lozinku možeš postaviti odmah.',
                          ),
                    style: TextStyle(color: LoopColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: t('E-mail'),
                      prefixIcon: const Icon(Icons.alternate_email),
                    ),
                  ),
                  if (!widget.online) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: t('Nova lozinka'),
                        prefixIcon: const Icon(Icons.lock_reset),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: TextStyle(color: LoopColors.error)),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_sent ? t('Zatvori') : t('Odustani')),
        ),
        if (!_sent)
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              widget.online ? t('Pošalji link') : t('Postavi lozinku'),
            ),
          ),
      ],
    );
  }
}

/// Zašto se traži prijava (gost je htio kupiti, licitirati, prodati…).
class _ReasonBanner extends StatelessWidget {
  const _ReasonBanner(this.reason, {required this.register});
  final String reason;

  /// Naslov prati odabrani način (Prijava / Registracija).
  final bool register;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 28),
        const LoopLogo(size: 30),
        const SizedBox(height: 14),
        Text(
          register ? t('Napravi besplatan račun') : t('Prijavi se na Subhasto'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          reason.isEmpty
              ? t(
                  'Za kupnju, licitiranje i prodaju treba račun — traje 30 sekundi.',
                )
              : reason,
          textAlign: TextAlign.center,
          style: TextStyle(color: LoopColors.textSecondary),
        ),
      ],
    );
  }
}
