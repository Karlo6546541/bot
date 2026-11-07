import 'package:flutter/material.dart';
import '../l10n/tr.dart';

/// A visual representation of the saved payment method. Never receives PAN/CVC.
class DigitalPaymentCard extends StatelessWidget {
  const DigitalPaymentCard({super.key, this.label, required this.onTap});
  final String? label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final brand = label?.toLowerCase().contains('visa') == true
        ? 'VISA'
        : label?.toLowerCase().contains('mastercard') == true
        ? 'Mastercard'
        : 'Subhasto';
    return Semantics(
      button: true,
      label: label ?? t('Dodaj karticu'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, .001)
            ..rotateX(.025)
            ..rotateY(-.025),
          alignment: Alignment.center,
          child: AspectRatio(
            aspectRatio: 1.65,
            child: Material(
              borderRadius: BorderRadius.circular(26),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: [0, .45, 1],
                      colors: [
                        Color(0xFF606168),
                        Color(0xFF25262B),
                        Color(0xFF494A50),
                      ],
                    ),
                    border: Border.all(color: const Color(0xFF8E9098)),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.contactless_outlined,
                              color: Colors.white70,
                            ),
                            const Spacer(),
                            Text(
                              brand,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          label ?? t('Dodaj karticu'),
                          maxLines: 2,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('Dodirni za promjenu'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
