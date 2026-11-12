import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../services/account_service.dart';
import '../services/username_rules.dart';
import '../theme/app_theme.dart';

/// Polje za korisničko ime: dok korisnik tipka provjerava format i je li
/// ime slobodno, a ako je zauzeto nudi slobodne alternative.
class UsernameField extends ConsumerStatefulWidget {
  const UsernameField({
    super.key,
    required this.controller,
    this.exceptUserId,
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController controller;

  /// Vlastito trenutno ime se ne računa kao zauzeto.
  final String? exceptUserId;
  final bool enabled;
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<UsernameField> createState() => _UsernameFieldState();
}

class _UsernameFieldState extends ConsumerState<UsernameField> {
  Timer? _debounce;
  UsernameCheck? _check;
  bool _checking = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    if (widget.controller.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onChanged();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  String _lastText = '';

  void _onChanged() {
    final text = widget.controller.text;
    if (text == _lastText) return;
    _lastText = text;
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      setState(() => _check = null);
      return;
    }
    setState(() => _checking = true);
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  Future<void> _run() async {
    final seq = ++_seq;
    final check = await ref
        .read(accountServiceProvider)
        .checkUsername(
          widget.controller.text,
          exceptUserId: widget.exceptUserId,
        );
    if (!mounted || seq != _seq) return;
    setState(() {
      _check = check;
      _checking = false;
    });
  }

  void _use(String name) {
    widget.controller.text = name;
    widget.controller.selection = TextSelection.collapsed(offset: name.length);
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    final Widget? suffix = _checking
        ? const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : check == null
        ? null
        : Icon(
            check.free ? Icons.check_circle : Icons.cancel,
            color: check.free ? LoopColors.success : LoopColors.error,
          );
    String? helper;
    String? error;
    if (!_checking && check != null) {
      if (check.error != null) {
        error = check.error;
      } else if (check.free) {
        helper = t('@{0} je slobodno ✓', [check.name!]);
      } else {
        error = t('@{0} je zauzeto.', [check.name!]);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('username-field'),
          controller: widget.controller,
          enabled: widget.enabled,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => widget.onSubmitted?.call(),
          decoration: InputDecoration(
            labelText: t('Korisničko ime'),
            prefixText: '@',
            prefixIcon: const Icon(Icons.badge_outlined),
            suffixIcon: suffix,
            helperText:
                helper ??
                t('{0}–{1} znakova: slova, brojevi, _ i točka', [
                  UsernameRules.minLength,
                  UsernameRules.maxLength,
                ]),
            helperStyle: helper != null
                ? TextStyle(color: LoopColors.success)
                : null,
            errorText: error,
            errorMaxLines: 2,
          ),
          validator: (v) => UsernameRules.validate(v ?? ''),
        ),
        if (check != null && !_checking && check.suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                t('Slobodno:'),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
              ),
              for (final s in check.suggestions)
                ActionChip(
                  label: Text('@$s'),
                  onPressed: () => _use(s),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
