import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/admin_shell.dart';
import 'providers/app_providers.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/countdown.dart';
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

    final Widget home;
    if (isAdmin) {
      home = const AdminShell();
    } else if (loggedIn) {
      home = const HomeShell();
    } else {
      home = const LoginScreen();
    }

    return MaterialApp(
      // Ključ po temi: promjena teme ponovno gradi cijelo sučelje, pa
      // svaki widget preuzme nove boje.
      key: ValueKey(brightness),
      title: 'LOOP',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: buildLoopTheme(accent: isAdmin ? LoopColors.admin : null),
      // Zaključivanje isteklih aukcija radi u pozadini cijele aplikacije.
      home: AuctionHeartbeat(child: home),
    );
  }
}
