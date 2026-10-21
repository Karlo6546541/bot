import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_shell.dart';
import 'admin_auctions_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_devices_screen.dart';
import 'admin_transactions_screen.dart';
import 'admin_users_screen.dart';

/// Admin panel. Koristi narančasti akcent i poseban AppBar kako bi bio
/// jasno vizualno odvojen od korisničkog dijela aplikacije.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int _index = 0;

  static const _destinations = [
    ShellDestination('Dashboard', Icons.dashboard_outlined, Icons.dashboard),
    ShellDestination('Korisnici', Icons.group_outlined, Icons.group),
    ShellDestination('Predmeti', Icons.inventory_2_outlined, Icons.inventory_2),
    ShellDestination('Aukcije', Icons.gavel_outlined, Icons.gavel),
    ShellDestination('Transakcije', Icons.swap_horiz, Icons.swap_horiz),
  ];

  @override
  Widget build(BuildContext context) {
    return AdaptiveShell(
      destinations: _destinations,
      selectedIndex: _index,
      onSelect: (i) => setState(() => _index = i),
      railHeader: Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Icon(
          Icons.admin_panel_settings,
          color: LoopColors.admin,
          size: 32,
        ),
      ),
      appBar: AppBar(
        backgroundColor: LoopColors.admin.withValues(alpha: 0.14),
        shape: Border(bottom: BorderSide(color: LoopColors.admin, width: 2)),
        title: Row(
          children: [
            Icon(Icons.admin_panel_settings, color: LoopColors.admin),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'LOOP Admin · ${_destinations[_index].label}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => ref.read(appProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Odjava'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          AdminDashboardScreen(),
          AdminUsersScreen(),
          AdminDevicesScreen(),
          AdminAuctionsScreen(),
          AdminTransactionsScreen(),
        ],
      ),
    );
  }
}

/// Zajednički omotač liste u admin panelu (ograničena širina na desktopu).
class AdminList extends StatelessWidget {
  const AdminList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.header,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final hasHeader = header != null;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: itemCount + (hasHeader ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (hasHeader && i == 0) return header!;
            return itemBuilder(context, i - (hasHeader ? 1 : 0));
          },
        ),
      ),
    );
  }
}
