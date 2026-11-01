import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../theme/app_theme.dart';
import 'add_device_screen.dart';
import 'my_shows_screen.dart';
import 'seller_finance_screens.dart';
import 'seller_verification_screen.dart';

/// "Alati prodavača": sve seller radnje grupirane u kartice
/// (Upravljanje, Prodaja, Učinak), kao jedan pregledan izbornik.
class SellerToolsScreen extends StatelessWidget {
  const SellerToolsScreen({super.key, this.onShipping, this.onHealth});

  /// Otvara popis pošiljki za slanje.
  final VoidCallback? onShipping;

  /// Vraća na pregled zdravlja računa.
  final VoidCallback? onHealth;

  static Future<void> open(
    BuildContext context, {
    VoidCallback? onShipping,
    VoidCallback? onHealth,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          SellerToolsScreen(onShipping: onShipping, onHealth: onHealth),
    ),
  );

  @override
  Widget build(BuildContext context) {
    void closeThen(VoidCallback? f) {
      Navigator.of(context).pop();
      f?.call();
    }

    Widget group(String title, List<Widget> rows) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: LoopColors.surface,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            ...rows,
            const SizedBox(height: 6),
          ],
        ),
      ),
    );

    Widget row(String key, IconData icon, String label, VoidCallback onTap) =>
        InkWell(
          key: ValueKey(key),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: LoopColors.surfaceHover,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: LoopColors.textSecondary),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(t('Alati prodavača'))),
      body: ListView(
        key: const ValueKey('seller-tools'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          group(t('Upravljanje'), [
            row(
              'tool-add-item',
              Icons.add_box_outlined,
              t('Dodaj predmet'),
              () => AddDeviceScreen.open(context),
            ),
            row(
              'tool-shows',
              Icons.live_tv_outlined,
              t('Showovi'),
              () => MyShowsScreen.open(context),
            ),
          ]),
          group(t('Prodaja'), [
            row(
              'tool-payouts',
              Icons.account_balance_wallet_outlined,
              t('Isplate i financije'),
              () => FinancialsScreen.open(context),
            ),
            row(
              'tool-fulfillment',
              Icons.local_shipping_outlined,
              t('Otprema'),
              () => closeThen(onShipping),
            ),
          ]),
          group(t('Promocije'), [
            row(
              'tool-promote',
              Icons.trending_up,
              t('Promoviraj show'),
              () => MyShowsScreen.open(context),
            ),
          ]),
          group(t('Učinak'), [
            row(
              'tool-health',
              Icons.verified_user_outlined,
              t('Zdravlje računa'),
              () => closeThen(onHealth),
            ),
            row(
              'tool-analytics',
              Icons.insights_outlined,
              t('Analitika showova'),
              () => MyShowsScreen.open(context),
            ),
          ]),
          group(t('Postavke'), [
            row(
              'tool-verification',
              Icons.verified_user_outlined,
              t('Verifikacija prodavača'),
              () => SellerVerificationScreen.open(context),
            ),
          ]),
        ],
      ),
    );
  }
}
