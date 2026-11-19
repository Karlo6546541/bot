import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../theme/app_theme.dart';

/// Mala oznaka ocjene na kartici oglasa (npr. "PSA 10").
class CertificateBadge extends StatelessWidget {
  const CertificateBadge({super.key, required this.certificate});
  final GradingCertificate certificate;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('certificate-badge'),
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFE9C46A),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.verified, size: 14, color: Color(0xFF3B2F0B)),
        const SizedBox(width: 4),
        Text(
          certificate.badge,
          style: const TextStyle(
            color: Color(0xFF3B2F0B),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

/// Na stranici oglasa: kuća, ocjena, broj i poveznica za provjeru.
class CertificateCard extends StatelessWidget {
  const CertificateCard({super.key, required this.certificate});
  final GradingCertificate certificate;

  @override
  Widget build(BuildContext context) {
    final c = certificate;
    final url = c.verifyUrl;
    return Container(
      key: const ValueKey('certificate-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LoopColors.glassBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified, color: Color(0xFFE9C46A), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Ocijenjeno: {0}', [c.badge]),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (c.number.isNotEmpty)
                  Text(
                    t('Certifikat #{0}', [c.number]),
                    style: TextStyle(
                      color: LoopColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
          if (url != null)
            TextButton(
              key: const ValueKey('certificate-verify'),
              onPressed: () => launchUrl(url, webOnlyWindowName: '_blank'),
              child: Text(t('Provjeri')),
            ),
        ],
      ),
    );
  }
}
