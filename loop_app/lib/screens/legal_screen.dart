import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../theme/app_theme.dart';
import 'legal_texts.dart';

/// Pravni dokumenti platforme.
enum LegalDoc {
  terms('Uvjeti korištenja', Icons.gavel_outlined),
  privacy('Pravila privatnosti', Icons.privacy_tip_outlined),
  cookies('Kolačići i pohrana', Icons.cookie_outlined),
  sellerRules('Pravila za prodavatelje', Icons.storefront_outlined),
  ranking('Rangiranje i oglašavanje', Icons.sort),
  reporting('Prijave, odluke i žalbe', Icons.flag_outlined),
  imprint('Impresum', Icons.business_outlined);

  const LegalDoc(this._title, this.icon);
  final String _title;
  final IconData icon;
  String get title => t(_title);

  String get body =>
      (Tr.lang == AppLang.en ? legalEn : legalHr)[name] ?? legalHr[name]!;
}

/// Jedan dokument: naslovi ("## …"), odlomci i natuknice ("- …").
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});
  final LegalDoc doc;

  static Future<void> open(BuildContext context, LegalDoc doc) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(doc: doc)));

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    for (final raw in doc.body.trim().split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        blocks.add(const SizedBox(height: 8));
      } else if (line.startsWith('## ')) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              line.substring(3),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        );
      } else if (line.startsWith('- ')) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: SelectableText(line.substring(2))),
              ],
            ),
          ),
        );
      } else {
        blocks.add(SelectableText(line, style: const TextStyle(height: 1.4)));
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            key: ValueKey('legal-${doc.name}'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: LoopColors.sunny,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  t(
                    'Predložak: prije pokretanja zamijeni podatke u [zagradama] i daj tekst na pregled odvjetniku.',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              ...blocks,
            ],
          ),
        ),
      ),
    );
  }
}

/// Popis svih dokumenata (Profil → Pravno).
class LegalListScreen extends StatelessWidget {
  const LegalListScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const LegalListScreen()));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Pravno'))),
    body: ListView(
      children: [
        for (final d in LegalDoc.values)
          ListTile(
            key: ValueKey('legal-open-${d.name}'),
            leading: Icon(d.icon, color: LoopColors.textSecondary),
            title: Text(d.title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => LegalScreen.open(context, d),
          ),
      ],
    ),
  );
}

/// Kratke poveznice na dokumente (ispod prijave/registracije).
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        t(
          'Koristimo samo nužnu pohranu (prijava, postavke) — bez kolačića za praćenje.',
        ),
        textAlign: TextAlign.center,
        style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (final d in [
            LegalDoc.terms,
            LegalDoc.privacy,
            LegalDoc.cookies,
            LegalDoc.imprint,
          ])
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: () => LegalScreen.open(context, d),
              child: Text(d.title),
            ),
        ],
      ),
    ],
  );
}
