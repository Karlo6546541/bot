import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/delivery.dart';
import '../models/live_show.dart';
import '../models/report.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/formatters.dart';
import 'add_device_screen.dart';
import 'auctions_screen.dart' show BrowseCardMedia;
import 'live_screens.dart';
import 'my_shows_screen.dart';
import 'seller_finance_screens.dart';

/// Zdravlje računa prodavača, izračunato iz stvarnih podataka: ocjene
/// kupaca, isporuke, pravovremene predaje paketa (rok
/// [Delivery.handOverDeadline]) i prijava (zadnjih [policyWindow]).
class AccountHealth {
  const AccountHealth({
    required this.ratingAverage,
    required this.ratingCount,
    required this.deliveryRate,
    required this.shipments,
    this.onTimeRate,
    this.openReports = 0,
    this.upheldReports = 0,
  });

  final double ratingAverage;
  final int ratingCount;

  /// Udio isporučenih (ili potvrđenih) pošiljki među onima s odabranom
  /// dostavom, 0…1 (null: još nema pošiljki).
  final double? deliveryRate;
  final int shipments;

  /// Udio paketa predanih dostavljaču u roku, 0…1 (null: nema podataka).
  final double? onTimeRate;

  /// Prijave protiv prodavača u zadnjih 180 dana: u obradi i potvrđene.
  final int openReports;
  final int upheldReports;

  static const policyWindow = Duration(days: 180);

  /// Pravila zajednice: bez prijava je odlično, prijava u obradi je dobro,
  /// potvrđena prijava traži pažnju.
  HealthLevel get policy => upheldReports > 0
      ? HealthLevel.attention
      : openReports > 0
      ? HealthLevel.good
      : HealthLevel.excellent;

  static HealthLevel _byRate(double rate) => rate >= 0.95
      ? HealthLevel.excellent
      : rate >= 0.85
      ? HealthLevel.good
      : HealthLevel.attention;

  /// Ukupno: najlošija od mjerenih stavki; Novo dok nema nikakvih podataka.
  /// Ocjena: ≥ 4,5 odlično, ≥ 4,0 dobro. Isporuka i pravovremena predaja:
  /// ≥ 95 % odlično, ≥ 85 % dobro.
  HealthLevel get level {
    final parts = <HealthLevel>[
      if (ratingCount > 0)
        ratingAverage >= 4.5
            ? HealthLevel.excellent
            : ratingAverage >= 4.0
            ? HealthLevel.good
            : HealthLevel.attention,
      ?deliveryRate == null ? null : _byRate(deliveryRate!),
      ?onTimeRate == null ? null : _byRate(onTimeRate!),
    ];
    if (parts.isEmpty && openReports == 0 && upheldReports == 0) {
      return HealthLevel.fresh;
    }
    parts.add(policy);
    return parts.reduce((a, b) => a.index > b.index ? a : b);
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
    // Pravovremena predaja: predano u roku = u redu; rok istekao bez
    // predaje (a kupac još nije potvrdio primitak) = kasni. Starije
    // pošiljke bez zapisa o predaji koje je kupac već potvrdio ne računaju.
    var onTime = 0;
    var measured = 0;
    for (final d in mine) {
      final due = d.handOverDue;
      if (due == null) continue;
      final handed = d.handedOverAt;
      if (handed != null) {
        measured++;
        if (!handed.isAfter(due)) onTime++;
      } else if (now.isAfter(due) && d.confirmedAt == null) {
        measured++;
      }
    }
    final since = now.subtract(policyWindow);
    var open = 0;
    var upheld = 0;
    for (final r in s.reports) {
      if (r.isAppeal || !r.createdAt.isAfter(since)) continue;
      final about = r.isDevice
          ? s.deviceById(r.targetId)?.ownerId == userId
          : r.targetId == userId;
      if (!about) continue;
      if (r.status == ReportStatus.open) open++;
      if (r.status == ReportStatus.resolved) upheld++;
    }
    return AccountHealth(
      ratingAverage: rating.average,
      ratingCount: rating.count,
      deliveryRate: due == 0 ? null : delivered / due,
      shipments: mine.length,
      onTimeRate: measured == 0 ? null : onTime / measured,
      openReports: open,
      upheldReports: upheld,
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
class SellerHubPanel extends ConsumerStatefulWidget {
  const SellerHubPanel({super.key, this.onShipping});

  /// Otvara popis pošiljki za slanje.
  final VoidCallback? onShipping;

  @override
  ConsumerState<SellerHubPanel> createState() => _SellerHubPanelState();
}

class _SellerHubPanelState extends ConsumerState<SellerHubPanel> {
  /// Sažeto: radnje i jedan redak stanja; razvijeno: sve kartice.
  bool _open = false;

  VoidCallback? get onShipping => widget.onShipping;

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 10),
          Material(
            color: LoopColors.surface,
            borderRadius: BorderRadius.circular(kRadius),
            child: InkWell(
              key: const ValueKey('hub-toggle'),
              borderRadius: BorderRadius.circular(kRadius),
              onTap: () => setState(() => _open = !_open),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kRadius),
                  border: Border.all(color: LoopColors.surfaceHover),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: t('Za predaju: {0}', ['${toShip.length}']),
                            ),
                            const TextSpan(text: '  ·  '),
                            TextSpan(
                              text: health.level.label,
                              style: TextStyle(
                                color: health.level.color,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      _open ? t('Manje') : t('Sve o prodaji'),
                      style: TextStyle(
                        color: LoopColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: LoopColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open) ...[
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
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
                      Icon(
                        Icons.chevron_right,
                        color: LoopColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            title(t('Financije')),
            Material(
              color: LoopColors.surface,
              borderRadius: BorderRadius.circular(kRadius),
              child: InkWell(
                key: const ValueKey('hub-financials'),
                borderRadius: BorderRadius.circular(kRadius),
                onTap: () => FinancialsScreen.open(context),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kRadius),
                    border: Border.all(color: LoopColors.surfaceHover),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        color: LoopColors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t('Knjiga, isplate i tjedni izvještaji'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        formatCredits(user.credits),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: LoopColors.textSecondary,
                      ),
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
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('hub-health-2'),
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
                      t('Pravovremena predaja'),
                      health.onTimeRate == null
                          ? '—'
                          : '${(health.onTimeRate! * 100).round()} %',
                    ),
                    VerticalDivider(width: 1, color: LoopColors.surfaceHover),
                    metric(
                      t('Pravila zajednice'),
                      health.policy.label,
                      color: health.policy.color,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
              child: Text(
                t(
                  'Paket predaj dostavljaču u roku od 48 sati nakon što kupac odabere dostavu.',
                ),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 11),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('Nadolazeći showovi'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('hub-all-shows'),
                    onPressed: () => MyShowsScreen.open(context),
                    child: Text(t('Svi showovi')),
                  ),
                ],
              ),
            ),
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
