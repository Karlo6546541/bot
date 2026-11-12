import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

/// Mali gumb u gornjoj traci: prikazuje aktivni jezik (🇭🇷 HR / 🇬🇧 EN)
/// i jednim dodirom prebacuje na drugi.
class LanguageButton extends ConsumerWidget {
  const LanguageButton({super.key, this.compact = false});

  /// Samo zastavica (za uske ekrane).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appProvider.select((s) => s.lang));
    final next = lang == AppLang.hr ? AppLang.en : AppLang.hr;
    return Tooltip(
      message: '${next.flag} ${next.nativeName}',
      child: Material(
        color: LoopColors.surface,
        shape: StadiumBorder(
          side: BorderSide(color: LoopColors.surfaceHover, width: 1.5),
        ),
        child: InkWell(
          key: const ValueKey('language-button'),
          customBorder: const StadiumBorder(),
          onTap: () => ref.read(appProvider.notifier).setLang(next),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: 7,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(lang.flag, style: const TextStyle(fontSize: 15)),
                if (!compact) ...[
                  const SizedBox(width: 5),
                  Text(
                    lang.code,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Odabir jezika za Profil / postavke.
class LanguageSelector extends ConsumerWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appProvider.select((s) => s.lang));
    return SegmentedButton<AppLang>(
      segments: [
        for (final l in AppLang.values)
          ButtonSegment(value: l, label: Text('${l.flag} ${l.nativeName}')),
      ],
      selected: {lang},
      showSelectedIcon: false,
      onSelectionChanged: (s) =>
          ref.read(appProvider.notifier).setLang(s.first),
    );
  }
}
