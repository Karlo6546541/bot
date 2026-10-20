import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/formatters.dart';
import '../widgets/trade_actions.dart';

/// Detalji uređaja: veliki prikaz, specifikacije, izračun fee-a i akcija
/// (kupnja za uređaje iz Marketa, prodaja za vlastite).
class DeviceDetailScreen extends ConsumerWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});

  final String deviceId;

  static Future<void> open(BuildContext context, Device device) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DeviceDetailScreen(deviceId: device.id),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final device = state.deviceById(deviceId);
    final user = state.currentUser;

    // Uređaj je u međuvremenu obrisan (npr. u admin panelu).
    if (device == null || user == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Uređaj više nije dostupan.')),
      );
    }

    final isMine = device.ownerId == user.id;
    final canBuy = device.isOnMarket && !isMine;
    final cat = device.category;
    final fee = feeFor(device.price);
    final isFav = state.isFavorite(device.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(device.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (canBuy)
            IconButton(
              tooltip: isFav ? 'Ukloni iz favorita' : 'Dodaj u favorite',
              onPressed: () => toggleFavorite(ref, device),
              icon: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? const Color(0xFFFF5C8A) : null,
              ),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // Velika "hero" kartica u bojama kategorije.
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cat.color.withValues(alpha: 0.32),
                      LoopColors.surface,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(kRadius * 1.5),
                  border: Border.all(color: cat.color.withValues(alpha: 0.35)),
                  boxShadow: [
                    BoxShadow(
                      color: cat.color.withValues(alpha: 0.18),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Hero(
                      tag: 'device-${device.id}',
                      child: CategoryAvatar(category: cat, size: 104),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      device.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      device.model,
                      style: const TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      formatCredits(device.price),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: cat.color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    _Spec(
                      Icons.category_outlined,
                      'Kategorija',
                      cat.singular,
                      cat.color,
                    ),
                    _Spec(
                      Icons.verified_outlined,
                      'Stanje',
                      device.condition.label,
                      device.condition.color,
                    ),
                    _Spec(
                      Icons.person_outline,
                      'Vlasnik',
                      isMine ? 'Ti' : state.userLabel(device.ownerId),
                      null,
                    ),
                    _Spec(
                      Icons.schedule,
                      'Dodano',
                      formatDateTime(device.createdAt),
                      null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _Line('Cijena', formatCredits(device.price)),
                      _Line(
                        'Fee platforme (5%)',
                        '${isMine ? '−' : '+'} ${formatCredits(fee)}',
                      ),
                      const Divider(height: 20),
                      _Line(
                        isMine ? 'Dobivaš prodajom' : 'Ukupno plaćaš',
                        formatCredits(
                          isMine
                              ? sellPayout(device.price)
                              : buyTotal(device.price),
                        ),
                        bold: true,
                      ),
                      if (canBuy)
                        _Line('Tvoji krediti', formatCredits(user.credits)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (isMine)
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await confirmAndSell(context, ref, device);
                    if (ok && context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.sell_outlined),
                  label: const Text('Prodaj odmah'),
                )
              else if (canBuy)
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await confirmAndBuy(context, ref, device);
                    if (ok && context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Kupi odmah'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Spec extends StatelessWidget {
  const _Spec(this.icon, this.label, this.value, this.dot);
  final IconData icon;
  final String label;
  final String value;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: LoopColors.textSecondary),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: LoopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: bold ? LoopColors.textPrimary : LoopColors.textSecondary,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 17 : 14,
              color: bold ? LoopColors.accent : LoopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
