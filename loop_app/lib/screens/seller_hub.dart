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
import 'auctions_screen.dart' show BrowseCardMedia, MyAuctionsScreen, MyTab;
import 'create_auction_screen.dart';
import 'live_screens.dart';
import 'my_shows_screen.dart';
import 'portfolio_screen.dart';
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

/// Razine tjednog cilja prodavača (vlastiti cilj, bez bonusa platforme).
enum SellerGoal {
  rising('Rastem', 250, 120, 5),
  power('Napredujem', 750, 240, 10),
  top('Vrh', 2500, 480, 25);

  const SellerGoal(this._label, this.sales, this.liveMinutes, this.buyers);
  final String _label;
  String get label => t(_label);

  /// Prodaja u eurima, minute uživo i različiti kupci u tjednu.
  final int sales;
  final int liveMinutes;
  final int buyers;
}

/// Napredak prema tjednom cilju (ponedjeljak – nedjelja).
class WeeklyProgress {
  const WeeklyProgress({
    required this.sales,
    required this.liveMinutes,
    required this.buyers,
  });
  final double sales;
  final int liveMinutes;
  final int buyers;

  static WeeklyProgress of(AppState s, String userId, DateTime now) {
    final start = weekStart(now);
    final end = start.add(const Duration(days: 7));
    final sales = [
      for (final tx in s.salesOf(userId))
        if (!tx.createdAt.isBefore(start) && tx.createdAt.isBefore(end)) tx,
    ];
    var minutes = 0;
    for (final show in s.liveShows) {
      if (show.hostId != userId || show.hostSeenAt == null) continue;
      final from = show.hostSeenAt!.isBefore(show.startsAt)
          ? show.hostSeenAt!
          : show.startsAt;
      if (from.isBefore(start) || !from.isBefore(end)) continue;
      final st = s.liveStateOf(show, now);
      final to = [
        show.endedAt ?? show.hostSeenAt!,
        for (final l in st.lots) ?l.end,
      ].reduce((a, b) => a.isAfter(b) ? a : b);
      final capped = to.isAfter(now) ? now : to;
      if (capped.isAfter(from)) minutes += capped.difference(from).inMinutes;
    }
    return WeeklyProgress(
      sales: sales.fold<double>(0, (a, tx) => a + tx.price),
      liveMinutes: minutes,
      buyers: {for (final tx in sales) tx.buyerId}.length,
    );
  }
}

/// Tjedni ciljevi: izabereš razinu i pratiš napredak (prodaja, minute uživo,
/// različiti kupci). Vlastiti cilj — platforma ne isplaćuje bonuse.
class SellerGoalsCard extends ConsumerStatefulWidget {
  const SellerGoalsCard({super.key});

  @override
  ConsumerState<SellerGoalsCard> createState() => _SellerGoalsCardState();
}

class _SellerGoalsCardState extends ConsumerState<SellerGoalsCard> {
  late int _level = ref.read(storageProvider).sellerGoal;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId;
    if (me == null) return const SizedBox.shrink();
    final goal = _level == 0 ? null : SellerGoal.values[_level - 1];
    final p = WeeklyProgress.of(s, me, DateTime.now());

    Widget bar(
      String key,
      String label,
      double value,
      double target,
      String text,
    ) {
      final f = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          key: ValueKey(key),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  text,
                  style: TextStyle(
                    color: f >= 1
                        ? LoopColors.buyNow
                        : LoopColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: f,
                minHeight: 8,
                color: f >= 1 ? LoopColors.buyNow : LoopColors.accent,
                backgroundColor: LoopColors.surfaceHover,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('hub-goals'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: LoopColors.surfaceHover),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final (i, g) in SellerGoal.values.indexed)
                ChoiceChip(
                  key: ValueKey('hub-goal-${g.name}'),
                  label: Text(g.label),
                  selected: _level == i + 1,
                  onSelected: (on) async {
                    final next = on ? i + 1 : 0;
                    await ref.read(storageProvider).setSellerGoal(next);
                    if (mounted) setState(() => _level = next);
                  },
                ),
            ],
          ),
          if (goal == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                t('Odaberi cilj za ovaj tjedan pa prati napredak.'),
                style: TextStyle(color: LoopColors.textSecondary),
              ),
            )
          else ...[
            bar(
              'goal-sales',
              t('Prodaja'),
              p.sales,
              goal.sales.toDouble(),
              '${formatCredits(p.sales)} / ${formatCredits(goal.sales.toDouble())}',
            ),
            bar(
              'goal-live',
              t('Minute uživo'),
              p.liveMinutes.toDouble(),
              goal.liveMinutes.toDouble(),
              '${p.liveMinutes} / ${goal.liveMinutes} min',
            ),
            bar(
              'goal-buyers',
              t('Različiti kupci'),
              p.buyers.toDouble(),
              goal.buyers.toDouble(),
              '${p.buyers} / ${goal.buyers}',
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t(
                'Vlastiti tjedni cilj (ponedjeljak – nedjelja), bez bonusa platforme.',
              ),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prodajni centar okuplja postojeće alate za liveove, aukcije i otpremu.
class SellerHubScreen extends ConsumerWidget {
  const SellerHubScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const SellerHubScreen()),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final user = state.currentUser;
    if (user == null || user.isGuest) {
      return Scaffold(appBar: AppBar(title: Text(t('Seller Hub'))));
    }
    final health = AccountHealth.of(state, user.id, DateTime.now());
    final shipping = state.toShip.length;
    void openSales(MyTab tab) => MyAuctionsScreen.open(context, initialTab: tab);

    Widget tile(Key key, IconData icon, String label, VoidCallback onTap) =>
        Material(
          color: LoopColors.surface,
          borderRadius: BorderRadius.circular(kRadius),
          child: InkWell(
            key: key,
            onTap: onTap,
            borderRadius: BorderRadius.circular(kRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: LoopColors.accent),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Icon(Icons.chevron_right, color: LoopColors.textSecondary),
                ],
              ),
            ),
          ),
        );

    Widget heading(String title) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(t('Seller Hub')),
        actions: [
          PopupMenuButton<int>(
            key: const ValueKey('seller-hub-menu'),
            onSelected: (value) {
              switch (value) {
                case 0: MyItemsScreen.open(context);
                case 1: MyShowsScreen.open(context);
                case 2: openSales(MyTab.selling);
                case 3: openSales(MyTab.notes);
                case 4: FinancialsScreen.open(context);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 0, child: Text(t('Moji predmeti'))),
              PopupMenuItem(value: 1, child: Text(t('Moji showovi'))),
              PopupMenuItem(value: 2, child: Text(t('Aukcije i predmeti'))),
              PopupMenuItem(value: 3, child: Text(t('Otpremnice'))),
              PopupMenuItem(value: 4, child: Text(t('Financije'))),
            ],
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
            children: [
              Text(t('Pregled prodaje'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(t('Sve za tvoju prodaju na jednom mjestu.'), style: TextStyle(color: LoopColors.textSecondary)),
              heading(t('Za napraviti')),
              tile(
                const ValueKey('seller-hub-shipping'),
                Icons.local_shipping_outlined,
                shipping == 0 ? t('Nema paketa za predaju') : t('Za predaju: {0}', ['$shipping']),
                () => openSales(MyTab.notes),
              ),
              heading(t('Brze radnje')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('seller-hub-live'),
                    onPressed: () => CreateLiveShowScreen.open(context),
                    icon: const Icon(Icons.videocam_outlined),
                    label: Text(t('Pokreni ili zakaži live')),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('seller-hub-auction'),
                    onPressed: () => CreateAuctionScreen.open(context),
                    icon: const Icon(Icons.gavel),
                    label: Text(t('Nova aukcija')),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('seller-hub-add'),
                    onPressed: () => AddDeviceScreen.open(context),
                    icon: const Icon(Icons.add),
                    label: Text(t('Dodaj predmet')),
                  ),
                ],
              ),
              heading(t('Zdravlje računa')),
              Material(
                key: const ValueKey('hub-health'),
                color: LoopColors.surface,
                borderRadius: BorderRadius.circular(kRadius),
                child: InkWell(
                  key: const ValueKey('seller-hub-health-details'),
                  borderRadius: BorderRadius.circular(kRadius),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: Text(t('Zdravlje računa'))),
                      body: ListView(children: [
                        SellerHubPanel(initiallyExpanded: true, onShipping: () => openSales(MyTab.notes)),
                      ]),
                    ),
                  )),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.health_and_safety_outlined, color: health.level.color),
                          const SizedBox(width: 10),
                          Expanded(child: Text(health.level.label, style: TextStyle(color: health.level.color, fontWeight: FontWeight.w900, fontSize: 17))),
                          Icon(Icons.chevron_right, color: LoopColors.textSecondary),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                          health.ratingCount == 0
                              ? t('Još nema ocjena kupaca.')
                              : t('Ocjena kupaca: {0}', ['★ ${health.ratingAverage.toStringAsFixed(1)} (${health.ratingCount})']),
                          style: TextStyle(color: LoopColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          health.onTimeRate == null
                              ? t('Nema podataka o pravovremenoj predaji.')
                              : t('Pravovremena predaja: {0}', ['${(health.onTimeRate! * 100).round()} %']),
                          style: TextStyle(color: LoopColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              heading(t('Alati za prodaju')),
              tile(const ValueKey('seller-hub-shows'), Icons.live_tv_outlined, t('Moji showovi'), () => MyShowsScreen.open(context)),
              const SizedBox(height: 8),
              tile(const ValueKey('seller-hub-inventory'), Icons.inventory_2_outlined, t('Moji predmeti'), () => MyItemsScreen.open(context)),
              const SizedBox(height: 8),
              tile(const ValueKey('seller-hub-inventory'), Icons.inventory_2_outlined, t('Moji predmeti'), () => MyItemsScreen.open(context)),
              const SizedBox(height: 8),
              tile(const ValueKey('seller-hub-sales'), Icons.sell_outlined, t('Aukcije i predmeti'), () => openSales(MyTab.selling)),
              const SizedBox(height: 8),
              tile(const ValueKey('seller-hub-shipments'), Icons.inventory_2_outlined, t('Otpremnice'), () => openSales(MyTab.notes)),
              const SizedBox(height: 8),
              tile(const ValueKey('seller-hub-finance'), Icons.account_balance_wallet_outlined, t('Financije'), () => FinancialsScreen.open(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Prodavač": pregled na jednom mjestu — brze radnje, otprema, zdravlje
/// računa i nadolazeći showovi.
class SellerHubPanel extends ConsumerStatefulWidget {
  const SellerHubPanel({super.key, this.onShipping, this.initiallyExpanded = false});

  final bool initiallyExpanded;

  /// Otvara popis pošiljki za slanje.
  final VoidCallback? onShipping;

  @override
  ConsumerState<SellerHubPanel> createState() => _SellerHubPanelState();
}

class _SellerHubPanelState extends ConsumerState<SellerHubPanel> {
  /// Sažeto: radnje i jedan redak stanja; razvijeno: sve kartice.
  late bool _open = widget.initiallyExpanded;

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
            title(t('Tjedni cilj')),
            const SellerGoalsCard(),
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
