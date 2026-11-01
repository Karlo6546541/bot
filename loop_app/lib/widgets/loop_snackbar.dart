import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Globalni messenger — SnackBar ostaje vidljiv i kad se ekran zamijeni
/// (npr. nakon odjave ili resetiranja podataka).
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Koliko otvorenih ekrana traži da obavijest bude iznad donjeg dijela
/// (soba uživo: gumb za licitiranje je na dnu i ne smije biti prekriven).
int _liftHolders = 0;

/// Obavijesti se prikazuju iznad donjeg panela dok je soba uživo otvorena.
void pushSnackBarLift() => _liftHolders++;
void popSnackBarLift() =>
    _liftHolders = _liftHolders > 0 ? _liftHolders - 1 : 0;

void showLoopSnackBar(
  String message, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  rootMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: _liftHolders > 0 ? SnackBarBehavior.floating : null,
        margin: _liftHolders > 0
            ? const EdgeInsets.fromLTRB(16, 0, 16, 240)
            : null,
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle,
              color: error ? LoopColors.error : LoopColors.success,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}
