import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../theme/app_theme.dart';
import 'item_image.dart';

/// Okrugla profilna slika; bez fotografije prikazuje inicijal.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 44});

  final AppUser? user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final source = u == null
        ? '?'
        : (u.name.isNotEmpty
              ? u.name
              : u.username.isNotEmpty
              ? u.username
              : '?');
    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: LoopColors.accent.withValues(alpha: 0.18),
      child: Text(
        source.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w900,
          color: LoopColors.accent,
        ),
      ),
    );
    final path = u?.avatarPath;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: path == null
            ? initials
            : LocalPhoto(
                path: path,
                fallback: initials,
                cacheWidth: (size * 3).round(),
              ),
      ),
    );
  }
}

/// Kvačica za korisnike s potvrđenim e-mailom (ili Google prijavom).
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: t('Provjeren korisnik'),
    child: Icon(Icons.verified, size: size, color: LoopColors.info),
  );
}

/// "@ana.kolekcija ✓" — korisničko ime s bedžom, opcionalno klikabilno.
class UserHandle extends StatelessWidget {
  const UserHandle({super.key, required this.user, this.onTap, this.style});

  final AppUser user;
  final VoidCallback? onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            user.handle,
            overflow: TextOverflow.ellipsis,
            style:
                style ??
                TextStyle(
                  fontWeight: FontWeight.w800,
                  color: onTap != null ? LoopColors.accent : null,
                ),
          ),
        ),
        if (user.emailVerified) ...[
          const SizedBox(width: 4),
          const VerifiedBadge(size: 15),
        ],
      ],
    );
    return onTap == null
        ? row
        : InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: row,
            ),
          );
  }
}

/// "✓ Provjeren" — oznaka uz e-mail u profilu.
class VerifiedBadgeLabel extends StatelessWidget {
  const VerifiedBadgeLabel({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const VerifiedBadge(),
      const SizedBox(width: 4),
      Text(
        t('Provjeren'),
        style: TextStyle(color: LoopColors.info, fontWeight: FontWeight.w800),
      ),
    ],
  );
}
