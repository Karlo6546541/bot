import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 68px receipt row from the artboard: artwork, two lines, amount and date.
class ReferenceOrderRow extends StatelessWidget {
  const ReferenceOrderRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.artwork,
    required this.onTap,
    this.amount,
    this.date,
    this.statusKey,
    this.color,
  });
  final String title, subtitle;
  final Widget artwork;
  final VoidCallback onTap;
  final String? amount, date;
  final Key? statusKey;
  final Color? color;
  @override
  Widget build(BuildContext context) => Material(
    color: LoopColors.textPrimary.withValues(alpha: .065),
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: SizedBox(width: 52, height: 52, child: artwork),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    key: statusKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: color ?? const Color(0xFF86F6D3),
                    ),
                  ),
                ],
              ),
            ),
            if (amount != null || date != null) ...[
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (amount != null)
                    Text(
                      amount!,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (date != null)
                    Text(
                      date!,
                      style: TextStyle(
                        fontSize: 12,
                        color: LoopColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right,
              size: 19,
              color: LoopColors.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}
