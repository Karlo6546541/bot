import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Globalni messenger — SnackBar ostaje vidljiv i kad se ekran zamijeni
/// (npr. nakon odjave ili resetiranja podataka).
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

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
