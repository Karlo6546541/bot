import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/trade_actions.dart';
import 'seller_screens.dart' show SellerInfoScreen;

/// Status koraka verifikacije prodavača.
enum VerificationStatus { complete, incomplete, locked }

/// Jedan korak verifikacije (kartica s oznakom statusa).
class VerificationStep {
  const VerificationStep({
    required this.id,
    required this.title,
    required this.text,
    required this.icon,
    required this.status,
  });

  final String id;
  final String title;
  final String text;
  final IconData icon;
  final VerificationStatus status;
}

/// Koraci verifikacije prodavača, izračunati iz podataka računa:
/// e-pošta, način plaćanja, podaci prodavatelja (DAC7), IBAN za isplate i
/// adresa za povrat. Zadnji korak (puni pristup prodaji) otključava se kad
/// su svi prethodni gotovi.
List<VerificationStep> sellerVerificationSteps(AppUser user) {
  VerificationStatus of(bool done) =>
      done ? VerificationStatus.complete : VerificationStatus.incomplete;
  final seller = user.seller;
  final steps = [
    VerificationStep(
      id: 'email',
      title: t('Potvrdi e-poštu'),
      text: user.authProvider == 'google'
          ? t('Prijavljen si Google računom.')
          : t('Potvrdi adresu iz poruke koju smo ti poslali.'),
      icon: Icons.mail_outline,
      status: of(user.emailVerified || user.authProvider == 'google'),
    ),
    VerificationStep(
      id: 'payment',
      title: t('Način plaćanja'),
      text: t('Kartica za kupnje, promocije i naknade.'),
      icon: Icons.credit_card,
      status: of(user.paymentCard != null),
    ),
    VerificationStep(
      id: 'seller',
      title: t('Podaci prodavatelja'),
      text: t('Ime, OIB i adresa (EU pravila DAC7 i DSA).'),
      icon: Icons.badge_outlined,
      status: of(seller != null),
    ),
    VerificationStep(
      id: 'iban',
      title: t('Račun za isplatu'),
      text: seller == null
          ? t('IBAN na koji stiže zarada.')
          : seller.maskedIban,
      icon: Icons.account_balance_outlined,
      status: of(seller != null && seller.iban.isNotEmpty),
    ),
    VerificationStep(
      id: 'address',
      title: t('Adresa za povrat'),
      text: user.address?.isNotEmpty ?? false
          ? user.address!
          : t('Kamo kupci vraćaju pakete.'),
      icon: Icons.location_on_outlined,
      status: of(user.address?.isNotEmpty ?? false),
    ),
  ];
  final allDone = steps.every((s) => s.status == VerificationStatus.complete);
  return [
    ...steps,
    VerificationStep(
      id: 'access',
      title: t('Puni pristup prodaji'),
      text: allDone
          ? t('Isplate, liveovi i promocije su otključani.')
          : t('Zahtijeva prethodne korake.'),
      icon: Icons.verified_outlined,
      status: allDone ? VerificationStatus.complete : VerificationStatus.locked,
    ),
  ];
}

/// Prodavač je prošao sve korake verifikacije.
bool isVerifiedSeller(AppUser user) => sellerVerificationSteps(
  user,
).every((s) => s.status == VerificationStatus.complete);

/// "Verifikacija prodavača": koraci kao kartice s oznakom statusa.
class SellerVerificationScreen extends ConsumerWidget {
  const SellerVerificationScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const SellerVerificationScreen()),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appProvider).currentUser;
    if (user == null || user.isGuest) return const SizedBox.shrink();
    final steps = sellerVerificationSteps(user);
    final done = steps
        .where((s) => s.status == VerificationStatus.complete)
        .length;

    Future<void> act(VerificationStep step) async {
      switch (step.id) {
        case 'payment':
        case 'address':
          await ensureCheckout(context, ref, force: true);
        case 'seller':
        case 'iban':
          await SellerInfoScreen.open(context);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('Verifikacija prodavača'))),
      body: ListView(
        key: const ValueKey('verification'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            done == steps.length
                ? t('Verificiran si!')
                : t('Završi korake za isplate i puni pristup prodaji.'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            t('{0} od {1} koraka', ['$done', '${steps.length}']),
            style: TextStyle(color: LoopColors.textSecondary),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: done / steps.length,
              minHeight: 6,
              color: LoopColors.accent,
              backgroundColor: LoopColors.surfaceHover,
            ),
          ),
          const SizedBox(height: 18),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _StepCard(
                step: step,
                onTap:
                    step.status == VerificationStatus.locked ||
                        step.id == 'email' ||
                        step.id == 'access'
                    ? null
                    : () => act(step),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, this.onTap});
  final VerificationStep step;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locked = step.status == VerificationStatus.locked;
    final (label, color) = switch (step.status) {
      VerificationStatus.complete => (t('Gotovo'), LoopColors.success),
      VerificationStatus.incomplete => (t('Nije gotovo'), LoopColors.accent),
      VerificationStatus.locked => (
        t('Zahtijeva prethodne korake'),
        LoopColors.textSecondary,
      ),
    };
    return Material(
      color: LoopColors.surface,
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        key: ValueKey('verify-${step.id}'),
        borderRadius: BorderRadius.circular(kRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: LoopColors.surfaceHover,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  locked ? Icons.lock_outline : step.icon,
                  size: 20,
                  color: locked ? LoopColors.textSecondary : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: locked ? LoopColors.textSecondary : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      key: ValueKey('verify-${step.id}-${step.status.name}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: LoopColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
