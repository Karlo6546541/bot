import 'package:flutter/material.dart';

import '../models/user_status.dart';
import '../theme/app_theme.dart';

/// Mali badge sa statusom korisnika (Bronze / Silver / Gold).
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final UserStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, size: 16, color: status.color),
          const SizedBox(width: 6),
          Text(
            status.label.toUpperCase(),
            // Tekst u neutralnoj boji; boja statusa je na ikoni i obrubu.
            style: TextStyle(
              color: LoopColors.textPrimary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
