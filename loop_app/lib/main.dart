import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/app_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/backend_config.dart';
import 'services/auth_backend.dart';
import 'services/remote_store.dart';
import 'services/storage_service.dart';
import 'services/sync_service.dart';
import 'theme/app_theme.dart';
import 'widgets/adaptive_shell.dart';
import 'l10n/tr.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Bootstrap());
}

/// Prikazuje splash s indikatorom dok se Hive ne inicijalizira,
/// zatim pokreće aplikaciju s inicijaliziranom pohranom.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<(StorageService, SyncService?)> _init = _initStorage();

  Future<(StorageService, SyncService?)> _initStorage() async {
    final storage = StorageService();
    await storage.init();
    // Online baza (Supabase) ako su predane postavke; inače lokalno.
    SyncService? sync;
    if (BackendConfig.isOnline) {
      await Supabase.initialize(
        url: BackendConfig.supabaseUrl,
        publishableKey: BackendConfig.supabaseKey,
      );
      sync = SyncService(
        storage,
        SupabaseRemoteStore(Supabase.instance.client),
      );
      // Spajanje ide u pozadini: aplikacija se odmah otvori s lokalnim
      // podacima, a online podaci stignu čim veza proradi.
      unawaited(sync.start());
      // Lokalna sesija bez važeće online prijave (npr. istekla) → odjava.
      final user = storage.currentUserId == null
          ? null
          : storage.userById(storage.currentUserId!);
      if (user != null &&
          !user.isGuest &&
          Supabase.instance.client.auth.currentSession == null) {
        await storage.saveSession();
      }
    }
    return (storage, sync);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(StorageService, SyncService?)>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ProviderScope(
            overrides: [
              storageProvider.overrideWithValue(snapshot.data!.$1),
              syncProvider.overrideWithValue(snapshot.data!.$2),
              if (snapshot.data!.$2 != null)
                authBackendProvider.overrideWithValue(
                  SupabaseAuthBackend(Supabase.instance.client),
                ),
            ],
            child: const LoopApp(),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildLoopTheme(),
          home: Scaffold(
            body: Center(
              child: snapshot.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        t('Greška pri učitavanju podataka:\n{0}', [
                          snapshot.error,
                        ]),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LoopLogo(size: 36),
                        SizedBox(height: 24),
                        CircularProgressIndicator(),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}
