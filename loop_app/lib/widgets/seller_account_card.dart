import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/backend_config.dart';
import '../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../providers/seller_account_provider.dart';
import '../screens/seller_screens.dart';
import '../services/stripe_backend.dart';
import '../theme/app_theme.dart';
import 'loop_snackbar.dart';
import 'quiet_ui.dart';

class SellerAccountCard extends ConsumerStatefulWidget {
  const SellerAccountCard({super.key});
  @override
  ConsumerState<SellerAccountCard> createState() => _SellerAccountCardState();
}

class _SellerAccountCardState extends ConsumerState<SellerAccountCard> {
  bool _busy = false;
  Future<void> _connect() async {
    if (_busy) return;
    final user = ref.read(appProvider).currentUser;
    if (user?.seller == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(sellerOnboardingProvider)(user!.seller!, user.country);
      if (mounted) ref.invalidate(sellerAccountStatusProvider(user.id));
    } catch (error) {
      if (mounted) {
        showLoopSnackBar(paymentActionErrorMessage(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      appProvider.select(
        (s) => (s.currentUser?.id, s.currentUser?.seller?.updatedAt),
      ),
    );
    final user = ref.read(appProvider).currentUser;
    if (user == null || user.isGuest) return const SizedBox.shrink();
    if (user.seller == null) {
      return AppStatusCard(
        key: const ValueKey('seller-account-missing'),
        icon: Icons.person_outline,
        title: t('Tvoj račun prodavatelja'),
        message: t('Spremi osnovne podatke i pripremi račun za prodaju.'),
        action: TextButton(
          onPressed: () => SellerInfoScreen.open(context),
          child: Text(t('Postavi račun')),
        ),
      );
    }
    final sync = ref.watch(syncProvider);
    Widget status() => Consumer(
      builder: (context, ref, _) {
        if (sync != null && sync.hasPendingRecord('sellers', user.id)) {
          return AppStatusCard(
            key: const ValueKey('seller-account-pending'),
            icon: Icons.cloud_upload_outlined,
            title: t('Spremljeno na uređaju'),
            message: t('Podaci će se poslati kad se veza vrati.'),
            action: TextButton(
              onPressed: () async {
                await sync.flushRecord('sellers', user.id);
                if (mounted) {
                  ref.invalidate(sellerAccountStatusProvider(user.id));
                }
              },
              child: Text(t('Pokušaj ponovno')),
            ),
          );
        }
        if (!BackendConfig.cloudCommerceEnabled || !BackendConfig.isOnline) {
          return AppStatusCard(
            key: const ValueKey('seller-account-saved'),
            icon: Icons.check_circle_outline,
            color: LoopColors.success,
            title: t('Podaci su spremljeni'),
            message: t('Svoje podatke možeš urediti u bilo kojem trenutku.'),
            action: TextButton(
              onPressed: () => SellerInfoScreen.open(context),
              child: Text(t('Uredi podatke')),
            ),
          );
        }
        final readiness = ref.watch(sellerAccountStatusProvider(user.id));
        return readiness.when(
          loading: () => AppStatusCard(
            title: t('Pripremamo račun'),
            message: t('Tvoji podaci su spremljeni.'),
            icon: Icons.hourglass_empty,
          ),
          error: (_, _) => AppStatusCard(
            key: const ValueKey('seller-account-unavailable'),
            title: t('Podaci su spremljeni'),
            message: t(
              'Povezivanje isplata trenutačno nije dostupno. Pokušaj ponovno.',
            ),
            icon: Icons.info_outline,
            action: TextButton(
              onPressed: () =>
                  ref.invalidate(sellerAccountStatusProvider(user.id)),
              child: Text(t('Pokušaj ponovno')),
            ),
          ),
          data: (ready) => AppStatusCard(
            key: ValueKey(
              ready ? 'seller-account-ready' : 'seller-account-needs-info',
            ),
            icon: ready
                ? Icons.check_circle_outline
                : Icons.account_balance_outlined,
            color: ready ? LoopColors.success : LoopColors.textSecondary,
            title: ready
                ? t('Spremno za primanje uplata')
                : t('Još jedan korak do isplata'),
            message: ready
                ? t('Stripe račun je povezan.')
                : t('Podaci su spremljeni. Dovrši potvrdu u Stripeu.'),
            action: ready
                ? null
                : OutlinedButton(
                    onPressed: _busy ? null : _connect,
                    child: Text(
                      _busy ? t('Povezivanje…') : t('Dovrši povezivanje'),
                    ),
                  ),
          ),
        );
      },
    );
    return sync == null
        ? status()
        : ValueListenableBuilder<int>(
            valueListenable: sync.pendingListenable,
            builder: (_, _, _) => status(),
          );
  }
}
