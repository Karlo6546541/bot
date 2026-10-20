import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/app_providers.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/adaptive_shell.dart';

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
  late final Future<StorageService> _init = _initStorage();

  Future<StorageService> _initStorage() async {
    final storage = StorageService();
    await storage.init();
    return storage;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StorageService>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ProviderScope(
            overrides: [storageProvider.overrideWithValue(snapshot.data!)],
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
                        'Greška pri učitavanju podataka:\n${snapshot.error}',
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
