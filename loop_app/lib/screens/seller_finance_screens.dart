import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/live_show.dart';
import '../models/loop_transaction.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/live_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/loop_snackbar.dart';
import 'seller_screens.dart' show showPayoutDialog;

/// Prodaje, naknade i isplate prodavača (po zapisima transakcija).
List<LoopTransaction> sellerLedger(AppState s, String me) => [
  for (final tx in s.transactions)
    if ((tx.type == TransactionType.sell &&
            (tx.sellerId ?? tx.userId) == me &&
            tx.buyerId != null &&
            tx.buyerId != me) ||
        ((tx.type == TransactionType.payout ||
                tx.type == TransactionType.auctionFee) &&
            tx.userId == me))
      tx,
]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

/// Ponedjeljak tjedna u kojem je [d] (ponoć).
DateTime weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// CSV tjednog izvještaja narudžbi (prodaja, naknada, zarada).
String weeklyReportCsv(
  List<LoopTransaction> sales,
  DateTime start,
  String Function(String) userLabel,
) {
  final end = start.add(const Duration(days: 7));
  final rows = [
    for (final tx in sales)
      if (!tx.createdAt.isBefore(start) && tx.createdAt.isBefore(end)) tx,
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  String q(String v) => '"${v.replaceAll('"', '""')}"';
  final out = StringBuffer('datum,predmet,kupac,cijena,naknada,zarada\n');
  for (final tx in rows) {
    out.writeln(
      [
        tx.createdAt.toIso8601String(),
        q(tx.deviceName),
        q(tx.buyerId == null ? tx.buyerLabel : userLabel(tx.buyerId!)),
        tx.price.toStringAsFixed(2),
        tx.fee.toStringAsFixed(2),
        tx.amount.toStringAsFixed(2),
      ].join(','),
    );
  }
  return out.toString();
}

/// Financije prodavača: Knjiga / Isplate / Izvještaji.
class FinancialsScreen extends ConsumerWidget {
  const FinancialsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const FinancialsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final user = s.currentUser;
    if (user == null) return const SizedBox.shrink();
    final ledger = sellerLedger(s, user.id);
    final payouts = [
      for (final tx in ledger)
        if (tx.type == TransactionType.payout) tx,
    ];
    final sales = [
      for (final tx in ledger)
        if (tx.type == TransactionType.sell) tx,
    ];
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('Financije')),
          bottom: TabBar(
            tabs: [
              Tab(key: const ValueKey('fin-tab-ledger'), text: t('Knjiga')),
              Tab(key: const ValueKey('fin-tab-payouts'), text: t('Isplate')),
              Tab(
                key: const ValueKey('fin-tab-reports'),
                text: t('Izvještaji'),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Card(
                child: ListTile(
                  title: Text(t('Dostupno za isplatu')),
                  subtitle: Text(
                    formatCredits(user.credits),
                    key: const ValueKey('fin-balance'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  trailing: FilledButton(
                    key: const ValueKey('fin-payout'),
                    onPressed: user.credits > 0
                        ? () => showPayoutDialog(context, ref)
                        : null,
                    child: Text(t('Isplati')),
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _txList(ledger, t('Još nema prodaja ni isplata.')),
                  _txList(payouts, t('Još nema isplata.')),
                  _Reports(sales: sales),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _txList(List<LoopTransaction> list, String empty) => list.isEmpty
      ? EmptyState(icon: Icons.receipt_long_outlined, title: empty, message: '')
      : ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final tx = list[i];
            final out = tx.type != TransactionType.sell;
            return ListTile(
              key: ValueKey('fin-tx-${tx.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                tx.deviceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${tx.type.label} · ${formatDateTime(tx.createdAt)}'
                '${tx.type == TransactionType.sell && tx.fee > 0 ? ' · ${t('naknada {0}', [formatCredits(tx.fee)])}' : ''}',
              ),
              trailing: Text(
                '${out ? '−' : '+'}${formatCredits(tx.amount.abs())}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: out ? LoopColors.textPrimary : LoopColors.buyNow,
                ),
              ),
            );
          },
        );
}

/// Tjedni izvještaji narudžbi: zadnjih 12 tjedana, CSV se kopira.
class _Reports extends ConsumerWidget {
  const _Reports({required this.sales});
  final List<LoopTransaction> sales;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final thisWeek = weekStart(DateTime.now());
    final weeks = [
      for (var i = 0; i < 12; i++) thisWeek.subtract(Duration(days: 7 * i)),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            t(
              'Tjedni izvještaj narudžbi: prodaja, naknade i zarada po tjednu (ponedjeljak – nedjelja).',
            ),
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
          ),
        ),
        for (final w in weeks)
          Builder(
            builder: (_) {
              final end = w.add(const Duration(days: 7));
              final n = sales
                  .where(
                    (tx) =>
                        !tx.createdAt.isBefore(w) && tx.createdAt.isBefore(end),
                  )
                  .length;
              final current = w == thisWeek;
              return ListTile(
                key: ValueKey('fin-report-${w.toIso8601String()}'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${formatDateTime(w).split(' ').first} – '
                  '${formatDateTime(end.subtract(const Duration(days: 1))).split(' ').first}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  current
                      ? t('Tjedan je u tijeku · {0} narudžbi', ['$n'])
                      : t('{0} narudžbi', ['$n']),
                ),
                trailing: TextButton.icon(
                  onPressed: n == 0
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: weeklyReportCsv(sales, w, s.userLabel),
                            ),
                          );
                          showLoopSnackBar(t('CSV je kopiran u međuspremnik.'));
                        },
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: Text(t('Kopiraj CSV')),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Metrike jednog showa, izračunate iz prodaja i događaja u sobi.
class ShowAnalytics {
  const ShowAnalytics({
    required this.sales,
    required this.earnings,
    required this.orders,
    required this.averageOrder,
    required this.salesPerHour,
    required this.ordersPerHour,
    required this.viewers,
    required this.buyers,
    required this.newBuyers,
    required this.returningBuyers,
    required this.bids,
    required this.topBuyers,
    required this.duration,
    required this.avgWatchSeconds,
    required this.newFollowers,
  });

  final double sales;
  final double earnings;
  final int orders;
  final double averageOrder;
  final double salesPerHour;
  final double ordersPerHour;

  /// Različiti gledatelji (iz događaja; čuvaju se 2 dana nakon showa).
  final int viewers;
  final int buyers;
  final int newBuyers;
  final int returningBuyers;
  final int bids;
  final List<({String userId, double spent, int orders})> topBuyers;
  final Duration duration;

  /// Prosječno vrijeme gledanja po gledatelju koji se javljao (s).
  final int avgWatchSeconds;

  /// Gledatelji koji su zapratili domaćina iz sobe showa.
  final int newFollowers;

  static ShowAnalytics of(
    AppState s,
    LiveShow show,
    List<LiveEvent> events,
    DateTime now,
  ) {
    final prefix = 'live-${show.id}-';
    final txs = [
      for (final tx in s.transactions)
        if (tx.type == TransactionType.sell &&
            tx.id.startsWith(prefix) &&
            tx.buyerId != null)
          tx,
    ];
    final sales = txs.fold<double>(0, (a, tx) => a + tx.price);
    final earnings = txs.fold<double>(0, (a, tx) => a + tx.amount);
    final st = s.liveStateOf(show, now);
    final start = [
      show.startsAt,
      for (final l in st.lots) ?l.start,
    ].reduce((a, b) => a.isBefore(b) ? a : b);
    final end = [
      show.endedAt ?? show.hostSeenAt ?? now,
      for (final l in st.lots) ?l.end,
    ].reduce((a, b) => a.isAfter(b) ? a : b);
    final duration = end.difference(start);
    final hours = (duration.inSeconds / 3600).clamp(1 / 60, 1e9).toDouble();
    final buyerIds = {for (final tx in txs) tx.buyerId!};
    final returning = {
      for (final tx in s.transactions)
        if (tx.type == TransactionType.sell &&
            (tx.sellerId ?? tx.userId) == show.hostId &&
            tx.createdAt.isBefore(show.startsAt) &&
            buyerIds.contains(tx.buyerId))
          tx.buyerId!,
    };
    // Zapisi u sobi se brišu 2 dana nakon showa; tada vrijedi spremljeni
    // sažetak.
    final live = events.isNotEmpty
        ? LiveService.summarize(show, events)
        : (show.summary ?? const <String, num>{});
    final perBuyer = <String, ({double spent, int orders})>{};
    for (final tx in txs) {
      final p = perBuyer[tx.buyerId!];
      perBuyer[tx.buyerId!] = (
        spent: (p?.spent ?? 0) + tx.price,
        orders: (p?.orders ?? 0) + 1,
      );
    }
    final top = [
      for (final e in perBuyer.entries)
        (userId: e.key, spent: e.value.spent, orders: e.value.orders),
    ]..sort((a, b) => b.spent.compareTo(a.spent));
    return ShowAnalytics(
      sales: sales,
      earnings: earnings,
      orders: txs.length,
      averageOrder: txs.isEmpty ? 0 : sales / txs.length,
      salesPerHour: sales / hours,
      ordersPerHour: txs.length / hours,
      viewers: (live['viewers'] ?? 0).toInt(),
      buyers: buyerIds.length,
      newBuyers: buyerIds.length - returning.length,
      returningBuyers: returning.length,
      bids: (live['bids'] ?? 0).toInt(),
      avgWatchSeconds: (live['avgWatchSeconds'] ?? 0).toInt(),
      newFollowers: (live['newFollowers'] ?? 0).toInt(),
      topBuyers: top.take(5).toList(),
      duration: duration,
    );
  }
}

/// Analitika showa: prodaja, publika i najbolji kupci.
class ShowAnalyticsScreen extends ConsumerWidget {
  const ShowAnalyticsScreen({super.key, required this.showId});
  final String showId;

  static Future<void> open(BuildContext context, String showId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShowAnalyticsScreen(showId: showId),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final show = s.liveShowById(showId);
    if (show == null) return const Scaffold(body: SizedBox.shrink());
    final events = ref.read(storageProvider).liveEventsOf(showId);
    final a = ShowAnalytics.of(s, show, events, DateTime.now());

    Widget tile(String key, String label, String value) => Expanded(
      child: Card(
        key: ValueKey(key),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Widget row(List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: children),
    );
    Widget head(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(t('Analitika showa'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            show.title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          Text(
            '${formatDateTime(show.startsAt)} · ${t('{0} min', ['${a.duration.inMinutes}'])}',
            style: TextStyle(color: LoopColors.textSecondary),
          ),
          head(t('Prodaja')),
          row([
            tile('an-sales', t('Prodaja'), formatCredits(a.sales)),
            const SizedBox(width: 8),
            tile('an-earn', t('Zarada'), formatCredits(a.earnings)),
          ]),
          row([
            tile('an-orders', t('Narudžbe'), '${a.orders}'),
            const SizedBox(width: 8),
            tile('an-aov', t('Prosj. narudžba'), formatCredits(a.averageOrder)),
          ]),
          row([
            tile('an-sph', t('Prodaja / sat'), formatCredits(a.salesPerHour)),
            const SizedBox(width: 8),
            tile(
              'an-oph',
              t('Narudžbe / sat'),
              a.ordersPerHour.toStringAsFixed(1),
            ),
          ]),
          head(t('Publika')),
          row([
            tile('an-viewers', t('Gledatelji'), '${a.viewers}'),
            const SizedBox(width: 8),
            tile('an-bids', t('Ponude'), '${a.bids}'),
          ]),
          row([
            tile(
              'an-watch',
              t('Prosj. gledanje'),
              a.avgWatchSeconds == 0
                  ? '—'
                  : t('{0} min {1} s', [
                      '${a.avgWatchSeconds ~/ 60}',
                      '${a.avgWatchSeconds % 60}',
                    ]),
            ),
            const SizedBox(width: 8),
            tile('an-followers', t('Novi pratitelji'), '${a.newFollowers}'),
          ]),
          row([
            tile('an-new', t('Novi kupci'), '${a.newBuyers}'),
            const SizedBox(width: 8),
            tile('an-returning', t('Ponovni kupci'), '${a.returningBuyers}'),
          ]),
          Text(
            t(
              'Publika se računa iz zapisa u sobi; nakon 2 dana ostaje spremljeni sažetak.',
            ),
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 11),
          ),
          head(t('Najbolji kupci')),
          if (a.topBuyers.isEmpty)
            Text(
              t('Još nema kupaca.'),
              style: TextStyle(color: LoopColors.textSecondary),
            )
          else
            for (final (i, b) in a.topBuyers.indexed)
              ListTile(
                key: ValueKey('an-top-$i'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: LoopColors.surfaceHover,
                  child: Text('${i + 1}'),
                ),
                title: Text(
                  s.userLabel(b.userId),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(t('{0} narudžbi', ['${b.orders}'])),
                trailing: Text(
                  formatCredits(b.spent),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
        ],
      ),
    );
  }
}
