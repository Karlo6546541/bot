import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/admin_shell.dart';
import 'l10n/tr.dart';
import 'providers/app_providers.dart';
import 'screens/account_screens.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/countdown.dart';
import 'widgets/mini_live.dart';
import 'widgets/trade_actions.dart';

/// Korijen aplikacije: ovisno o sesiji prikazuje login, korisnički dio
/// ili admin panel (s vlastitim akcentom).
class LoopApp extends ConsumerWidget {
  const LoopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(appProvider.select((s) => s.isAdmin));
    final loggedIn = ref.watch(
      appProvider.select((s) => s.currentUser != null),
    );

    final mode = ref.watch(appProvider.select((s) => s.themeMode));
    final brightness = switch (mode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system => View.of(
        context,
      ).platformDispatcher.platformBrightness,
    };
    // Boje (LoopColors) čitaju aktivnu paletu — postavi je prije gradnje.
    LoopColors.use(brightness);
    // Isto za jezik: t('...') čita Tr.lang tijekom gradnje.
    final lang = ref.watch(appProvider.select((s) => s.lang));
    Tr.lang = lang;

    final pendingSignup = ref.watch(
      appProvider.select((s) => s.pendingSignup != null),
    );
    final recovery = ref.watch(passwordRecoveryProvider);

    final isGuest = ref.watch(
      appProvider.select((s) => s.currentUser?.isGuest ?? false),
    );
    final autoGuest =
        ref.watch(autoGuestProvider) &&
        !ref.watch(autoGuestDoneProvider) &&
        !loggedIn &&
        !isAdmin &&
        !pendingSignup &&
        !recovery;
    if (autoGuest) {
      // Samo jednom po pokretanju: nakon odjave ostaje ekran za prijavu.
      Future.microtask(() async {
        ref.read(autoGuestDoneProvider.notifier).markDone();
        await ref.read(appProvider.notifier).loginAsGuest();
      });
    }

    final Widget home;
    if (recovery) {
      home = const PasswordRecoveryScreen();
    } else if (isAdmin) {
      home = const AdminShell();
    } else if (pendingSignup && (!loggedIn || isGuest)) {
      home = const UsernameSetupScreen();
    } else if (loggedIn) {
      home = const HomeShell();
    } else if (autoGuest) {
      home = const Scaffold();
    } else {
      home = const LoginScreen();
    }

    return MaterialApp(
      // Ključ po temi i jeziku: promjena ponovno gradi cijelo sučelje, pa
      // svaki widget preuzme nove boje i tekstove.
      key: ValueKey((brightness, lang)),
      title: 'LOOP',
      // Ugrađeni tekstovi (npr. "Natrag", kalendar) na jeziku aplikacije.
      locale: Locale(lang == AppLang.en ? 'en' : 'hr'),
      supportedLocales: const [Locale('hr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      navigatorKey: navigatorKeyFor((brightness, lang)),
      // Mali prozor s liveom lebdi iznad svih ekrana.
      builder: (context, child) =>
          Stack(children: [?child, const MiniLiveOverlay()]),
      theme: buildLoopTheme(accent: isAdmin ? LoopColors.admin : null),
      // Zaključivanje isteklih aukcija radi u pozadini cijele aplikacije.
      home: AuctionHeartbeat(child: home),
    );
  }
}
