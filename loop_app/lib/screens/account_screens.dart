import 'package:flutter/material.dart';
import '../widgets/country_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../providers/app_providers.dart';
import '../services/account_service.dart';
import '../services/file_saver/file_saver.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_shell.dart';
import '../widgets/formatters.dart';
import '../widgets/language_button.dart';
import '../widgets/trade_actions.dart';
import '../widgets/user_avatar.dart';
import '../widgets/username_field.dart';

/// Okvir za jednostavne ekrane računa (centrirana kartica).
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: LoopColors.surface,
                    borderRadius: BorderRadius.circular(kRadius * 1.6),
                    boxShadow: LoopColors.softShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
            const Positioned(top: 12, right: 12, child: LanguageButton()),
          ],
        ),
      ),
    );
  }
}

/// Prva prijava (npr. Googleom) — korisnik bira jedinstveno korisničko ime.
class UsernameSetupScreen extends ConsumerStatefulWidget {
  const UsernameSetupScreen({super.key});

  @override
  ConsumerState<UsernameSetupScreen> createState() =>
      _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends ConsumerState<UsernameSetupScreen> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(
    text: () {
      final id = ref.read(appProvider).pendingSignup;
      return id?.username ?? '';
    }(),
  );
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(appProvider.notifier).chooseUsername(_username.text);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(appProvider.select((s) => s.pendingSignup));
    return _AccountCard(
      children: [
        const Center(child: LoopLogo(size: 26)),
        const SizedBox(height: 20),
        Text(
          t('Odaberi korisničko ime'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          t(
            'Prikazuje se drugima umjesto e-maila, npr. kod aukcija. Mora biti jedinstveno.',
          ),
          style: TextStyle(color: LoopColors.textSecondary),
        ),
        if (identity != null && identity.email.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            t('Prijavljen kao {0}', [identity.email]),
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
          ),
        ],
        const SizedBox(height: 18),
        Form(
          key: _form,
          child: UsernameField(
            controller: _username,
            onSubmitted: _submit,
            // Ime koje je ovaj račun već rezervirao računa se kao slobodno.
            exceptUserId: identity?.uid,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(t('Nastavi')),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => ref.read(appProvider.notifier).cancelPendingSignup(),
          child: Text(t('Odustani')),
        ),
      ],
    );
  }
}

/// Nakon linka "nova lozinka" iz e-maila (online).
class PasswordRecoveryScreen extends ConsumerStatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  ConsumerState<PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState
    extends ConsumerState<PasswordRecoveryScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_p1.text != _p2.text) {
      setState(() => _error = t('Lozinke se ne podudaraju.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(appProvider.notifier).setRecoveredPassword(_p1.text);
      showLoopSnackBar(t('Nova lozinka je spremljena.'));
    } on TradeException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AccountCard(
      children: [
        Text(
          t('Nova lozinka'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _p1,
          obscureText: true,
          decoration: InputDecoration(
            labelText: t('Nova lozinka'),
            helperText: t('Barem {0} znakova', [AccountService.minPassword]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _p2,
          obscureText: true,
          decoration: InputDecoration(labelText: t('Ponovi lozinku')),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: LoopColors.error)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(t('Spremi lozinku')),
        ),
        TextButton(
          onPressed: () =>
              ref.read(passwordRecoveryProvider.notifier).set(false),
          child: Text(t('Odustani')),
        ),
      ],
    );
  }
}

/// Uređivanje profila: fotografija, ime, korisničko ime, opis, grad.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const EditProfileScreen()));

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final AppUser _user = ref.read(appProvider).currentUser!;
  late final _name = TextEditingController(text: _user.name);
  late final _username = TextEditingController(text: _user.username);
  late final _bio = TextEditingController(text: _user.bio);
  late final _city = TextEditingController(text: _user.city ?? '');
  late String _country = _user.country;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _username, _bio, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final c = ref.read(appProvider.notifier);
    try {
      await c.updateProfile(name: _name.text, bio: _bio.text, city: _city.text);
      await c.setCountry(_country);
      await c.changeUsername(_username.text);
      if (mounted) Navigator.pop(context);
      showLoopSnackBar(t('Profil je spremljen'));
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo() async {
    final camera = ref.read(imageStoreProvider).canUseCamera;
    final user = ref.read(appProvider).currentUser;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t('Galerija')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (camera)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(t('Uslikaj')),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            if (user?.avatarPath != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: LoopColors.error),
                title: Text(t('Ukloni fotografiju')),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final c = ref.read(appProvider.notifier);
    try {
      if (choice == 'remove') {
        await c.removeAvatar();
      } else {
        await c.pickAvatar(camera: choice == 'camera');
      }
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } catch (e) {
      showLoopSnackBar(
        t('Fotografiju nije moguće učitati: {0}', [e]),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appProvider.select((s) => s.currentUser)) ?? _user;
    final next = user.nextUsernameChange;
    final locked = next != null && DateTime.now().isBefore(next);
    return Scaffold(
      appBar: AppBar(title: Text(t('Uredi profil'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Center(
                  child: Stack(
                    children: [
                      UserAvatar(user: user, size: 96),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: LoopColors.accent,
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: t('Promijeni fotografiju'),
                            icon: Icon(
                              Icons.photo_camera,
                              color: LoopColors.onAccent,
                              size: 20,
                            ),
                            onPressed: _photo,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  maxLength: AccountService.maxName,
                  decoration: InputDecoration(
                    labelText: t('Ime (neobavezno)'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 4),
                UsernameField(
                  controller: _username,
                  exceptUserId: user.id,
                  enabled: !locked,
                ),
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      t('Korisničko ime možeš ponovno promijeniti {0}.', [
                        formatDateTime(next),
                      ]),
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      t(
                        'Ime možeš mijenjati jednom u {0} dana; staro ostaje zaključano isto toliko.',
                        [AppUser.usernameLockDays],
                      ),
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bio,
                  maxLength: AppUser.maxBio,
                  maxLines: 3,
                  minLines: 2,
                  decoration: InputDecoration(
                    labelText: t('O meni'),
                    hintText: t('npr. Skupljam LEGO i stare ploče 🎶'),
                    prefixIcon: const Icon(Icons.notes),
                  ),
                ),
                const SizedBox(height: 4),
                CountryField(
                  value: _country,
                  onChanged: (v) => setState(() => _country = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _city,
                  decoration: InputDecoration(
                    labelText: t('Grad (za osobno preuzimanje)'),
                    prefixIcon: const Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(t('Spremi')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Promjena lozinke (traži trenutnu lozinku).
Future<void> showChangePasswordDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ChangePassword());

class _ChangePassword extends ConsumerStatefulWidget {
  const _ChangePassword();

  @override
  ConsumerState<_ChangePassword> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends ConsumerState<_ChangePassword> {
  final _old = TextEditingController();
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _old.dispose();
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_p1.text != _p2.text) {
      setState(() => _error = t('Lozinke se ne podudaraju.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(appProvider.notifier).changePassword(_old.text, _p1.text);
      if (mounted) Navigator.pop(context);
      showLoopSnackBar(t('Lozinka je promijenjena'));
    } on TradeException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Promijeni lozinku')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _old,
              obscureText: true,
              decoration: InputDecoration(labelText: t('Trenutna lozinka')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _p1,
              obscureText: true,
              decoration: InputDecoration(
                labelText: t('Nova lozinka'),
                helperText: t('Barem {0} znakova', [
                  AccountService.minPassword,
                ]),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _p2,
              obscureText: true,
              decoration: InputDecoration(labelText: t('Ponovi lozinku')),
              onSubmitted: (_) => _submit(),
            ),
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
          child: Text(t('Odustani')),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(t('Spremi')),
        ),
      ],
    );
  }
}

/// Brisanje računa: pravila, posljedice i potvrda korisničkim imenom.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const DeleteAccountScreen()));

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    try {
      await action();
      navigator.popUntil((r) => r.isFirst);
      showLoopSnackBar(done);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } catch (e) {
      showLoopSnackBar(t('Greška: {0}', [e]), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final user = state.currentUser;
    if (user == null) return const SizedBox.shrink();
    final controller = ref.read(appProvider.notifier);
    final blockers = controller.deletionBlockers;
    final matches =
        _confirm.text.trim().replaceFirst('@', '').toLowerCase() ==
        user.username;
    final canDelete = blockers.isEmpty && matches && !_busy;
    final items = state.myDevices.length;
    final bullet = TextStyle(height: 1.5, color: LoopColors.textPrimary);

    return Scaffold(
      appBar: AppBar(title: Text(t('Obriši račun'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('Što se događa'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t(
                          '• Prije brisanja isplati zaradu ({0}) na svoj IBAN — poslije to više nije moguće.',
                          [formatCredits(user.credits)],
                        ),
                        style: bullet.copyWith(
                          fontWeight: FontWeight.w800,
                          color: LoopColors.error,
                        ),
                      ),
                      Text(
                        t(
                          '• Briše se {0} tvojih predmeta i njihove objave na prodaji.',
                          [items],
                        ),
                        style: bullet,
                      ),
                      Text(
                        t(
                          '• Drugima povijest kupnji ostaje, ali umjesto tvog imena piše @obrisani.',
                        ),
                        style: bullet,
                      ),
                      Text(
                        t(
                          '• Aukcije bez ponuda se otkazuju, a korisničko ime se oslobađa.',
                        ),
                        style: bullet,
                      ),
                      Text(
                        t(
                          '• Imaš {0} dana za predomišljanje: prijavi se i račun se vraća.',
                          [AppUser.deletionGraceDays],
                        ),
                        style: bullet,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => exportMyData(context, ref),
                icon: const Icon(Icons.download_outlined),
                label: Text(t('Prvo preuzmi moje podatke')),
              ),
              if (blockers.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: LoopColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(kRadius),
                    border: Border.all(
                      color: LoopColors.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('Račun se još ne može obrisati:'),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: LoopColors.error,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final b in blockers)
                        Text('• $b', style: const TextStyle(height: 1.5)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('delete-confirm'),
                controller: _confirm,
                enabled: blockers.isEmpty,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: t('Za potvrdu upiši {0}', [user.handle]),
                  prefixIcon: const Icon(Icons.warning_amber_outlined),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('delete-schedule'),
                style: FilledButton.styleFrom(
                  backgroundColor: LoopColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: canDelete
                    ? () => _run(
                        () => controller.requestAccountDeletion(_confirm.text),
                        t(
                          'Račun će biti obrisan za {0} dana. Prijavi se u tom roku ako se predomisliš.',
                          [AppUser.deletionGraceDays],
                        ),
                      )
                    : null,
                icon: const Icon(Icons.schedule),
                label: Text(
                  t('Obriši račun (za {0} dana)', [AppUser.deletionGraceDays]),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: LoopColors.error),
                onPressed: canDelete
                    ? () => _run(
                        () => controller.deleteAccountNow(_confirm.text),
                        t('Račun je trajno obrisan.'),
                      )
                    : null,
                child: Text(t('Obriši odmah, bez povratka')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Preuzimanje svih vlastitih podataka (JSON).
Future<void> exportMyData(BuildContext context, WidgetRef ref) async {
  try {
    final json = ref.read(appProvider.notifier).exportMyData();
    final user = ref.read(appProvider).currentUser!;
    final name =
        'loop-${user.username}-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    final where = await saveTextFile(name, json);
    showLoopSnackBar(t('Podaci spremljeni: {0}', [where]));
  } on TradeException catch (e) {
    showLoopSnackBar(e.message, error: true);
  } catch (e) {
    showLoopSnackBar(t('Greška: {0}', [e]), error: true);
  }
}

/// Blokirani korisnici — njihovi oglasi i aukcije su skriveni.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const BlockedUsersScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final ids = state.currentUser?.blockedIds ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(t('Blokirani korisnici'))),
      body: ids.isEmpty
          ? Center(child: Text(t('Nikoga nisi blokirao.')))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final id in ids)
                  Card(
                    child: ListTile(
                      leading: UserAvatar(user: state.userById(id), size: 36),
                      title: Text(state.userLabel(id)),
                      trailing: TextButton(
                        onPressed: () =>
                            ref.read(appProvider.notifier).toggleBlock(id),
                        child: Text(t('Odblokiraj')),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
