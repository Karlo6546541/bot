import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/delivery.dart';
import '../models/live_show.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import 'add_device_screen.dart';
import 'auctions_screen.dart' show BrowseCardMedia;
import 'live_screens.dart';

/// Zdravlje računa prodavača, izračunato iz stvarnih podataka: ocjene
/// kupaca i udjela isporučenih pošiljki. Bez podataka je "Novo".
class AccountHealth {
  const AccountHealth({
    required this.ratingAverage,
    required this.ratingCount,
    required this.deliveryRate,
    required this.shipments,
  });

  final double ratingAverage;
  final int ratingCount;

  /// Udio isporučenih (ili potvrđenih) pošiljki među onima s odabranom
  /// dostavom, 0…1 (null: još nema pošiljki).
  final double? deliveryRate;
  final int shipments;

  /// Odlično: ocjena ≥ 4,5 i isporuka ≥ 95 %. Dobro: ≥ 4,0 i ≥ 85 %.
  /// Inače treba pažnju. Bez ocjena i pošiljki: novo.
  HealthLevel get level {
    if (ratingCount == 0 && deliveryRate == null) return HealthLevel.fresh;
    final rating = ratingCount == 0 ? 5.0 : ratingAverage;
    final rate = deliveryRate ?? 1.0;
    if (rating >= 4.5 && rate >= 0.95) return HealthLevel.excellent;
    if (rating >= 4.0 && rate >= 0.85) return HealthLevel.good;
    return HealthLevel.attention;
  }

  static AccountHealth of(AppState s, String userId, DateTime now) {
    final rating = s.ratingOf(userId);
    final mine = [
      for (final d in s.sellerDeliveries)
        if (d.method != null && d.method != DeliveryMethod.digital) d,
    ];
    final delivered = mine
        .where((d) => d.confirmedAt != null || d.isDelivered(now))
        .length;
    // Pošiljke u tijeku se ne računaju kao neuspjeh: mjeri se samo ono što
    // je trebalo stići (dostava je trajala dulje od prikazane procjene).
    final due = mine
        .where(
          (d) =>
              d.confirmedAt != null ||
              d.isDelivered(now) ||
              (d.eta()?.isBefore(now) ?? false),
        )
        .length;
    return AccountHealth(
      ratingAverage: rating.average,
      ratingCount: rating.count,
      deliveryRate: due == 0 ? null : delivered / due,
      shipments: mine.length,
    );
  }
}

enum HealthLevel {
  fresh('Novo'),
  excellent('Odlično'),
  good('Dobro'),
  attention('Treba pažnju');

  const HealthLevel(this._label);
  final String _label;
  String get label => t(_label);

  Color get color => switch (this) {
    excellent => LoopColors.buyNow,
    good => LoopColors.info,
    attention => LoopColors.accent,
    fresh => LoopColors.textSecondary,
  };
}

/// "Prodavač": pregled na jednom mjestu — brze radnje, otprema, zdravlje
/// računa i nadolazeći showovi.
class SellerHubPanel extends ConsumerWidget {
  const SellerHubPanel({super.key, this.onShipping});

  /// Otvara popis pošiljki za slanje.
  final VoidCallback? onShipping;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final user = s.currentUser;
    if (user == null || user.isGuest) return const SizedBox.shrink();
    final now = DateTime.now();
    final health = AccountHealth.of(s, user.id, now);
    final toShip = s.toShip;
    final dueSoon = toShip
        .where(
          (d) => d.eta()?.isBefore(now.add(const Duration(days: 1))) ?? false,
        )
        .length;
    final shows = [
      for (final show in s.liveShows)
        if (show.hostId == user.id &&
            show.endedAt == null &&
            !s.liveStateOf(show, now).isOver)
          show,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    Widget action(Key key, IconData icon, String label, VoidCallback onTap) =>
        Expanded(
          child: Material(
            color: LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(kRadius),
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 88),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kRadius),
                  border: Border.all(color: LoopColors.surfaceHover),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: LoopColors.accent, size: 26),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    Widget metric(String label, String value, {Color? color}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: LoopColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );

    Widget title(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
      ),
    );

    final name = user.name.isNotEmpty
        ? user.name.split(' ').first
        : user.handle;
    return Padding(
      key: const ValueKey('seller-hub'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('Bok, {0}!', [name]),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              action(
                const ValueKey('hub-add-item'),
                Icons.add_box_outlined,
                t('Dodaj predmet'),
                () => AddDeviceScreen.open(context),
              ),
              const SizedBox(width: 10),
              action(
                const ValueKey('hub-schedule-show'),
                Icons.event_outlined,
                t('Zakaži show'),
                () => CreateLiveShowScreen.open(context),
              ),
            ],
          ),
          title(t('Otprema')),
          Material(
            color: LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            child: InkWell(
              key: const ValueKey('hub-shipping'),
              borderRadius: BorderRadius.circular(kRadius),
              onTap: onShipping,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kRadius),
                  border: Border.all(color: LoopColors.surfaceHover),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_shipping_outlined,
                      color: LoopColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            toShip.isEmpty
                                ? t('Nema paketa za predaju')
                                : t('Spremno za predaju'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (dueSoon > 0)
                            Text(
                              t('{0} do sutra', ['$dueSoon']),
                              style: TextStyle(
                                color: LoopColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${toShip.length}',
                      key: const ValueKey('hub-shipping-count'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: LoopColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
          title(t('Zdravlje računa')),
          Container(
            key: const ValueKey('hub-health'),
            decoration: BoxDecoration(
              color: LoopColors.surface,
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(color: LoopColors.surfaceHover),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  metric(
                    t('Ocjena kupaca'),
                    health.ratingCount == 0
                        ? t('Novo')
                        : '★ ${health.ratingAverage.toStringAsFixed(1)} (${health.ratingCount})',
                  ),
                  VerticalDivider(width: 1, color: LoopColors.surfaceHover),
                  metric(
                    t('Uspješna isporuka'),
                    health.deliveryRate == null
                        ? '—'
                        : '${(health.deliveryRate! * 100).round()} %',
                  ),
                  VerticalDivider(width: 1, color: LoopColors.surfaceHover),
                  metric(
                    t('Status'),
                    health.level.label,
                    color: health.level.color,
                  ),
                ],
              ),
            ),
          ),
          title(t('Nadolazeći showovi')),
          if (shows.isEmpty)
            Container(
              key: const ValueKey('hub-no-shows'),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: LoopColors.surface,
                borderRadius: BorderRadius.circular(kRadius),
                border: Border.all(color: LoopColors.surfaceHover),
              ),
              child: Text(
                t(
                  'Nemaš zakazanih showova. Zakaži prvi pa pratitelji dobiju podsjetnik.',
                ),
                style: TextStyle(color: LoopColors.textSecondary),
              ),
            )
          else
            SizedBox(
              height: 214,
              child: ListView.separated(
                key: const ValueKey('hub-shows'),
                scrollDirection: Axis.horizontal,
                itemCount: shows.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _ShowTile(show: shows[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShowTile extends StatelessWidget {
  const _ShowTile({required this.show});
  final LiveShow show;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    child: InkWell(
      key: ValueKey('hub-show-${show.id}'),
      borderRadius: BorderRadius.circular(kRadius),
      onTap: () => LiveRoomScreen.open(context, show.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BrowseCardMedia(device: null, cover: show.coverPath),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        formatDateTime(show.startsAt),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            show.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
