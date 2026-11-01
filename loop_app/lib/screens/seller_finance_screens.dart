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
import 'seller_screens.dart' show SellerInfoScreen, showPayoutDialog;
import 'seller_verification_screen.dart';

/// Prodaje, naknade i isplate prodavača (po zapisima transakcija).
List<LoopTransaction> sellerLedger(AppState s, String me) => [
  for (final tx in s.transactions)
    if ((tx.type == TransactionType.sell &&
            (tx.sellerId ?? tx.userId) == me &&
            tx.buyerId != null &&
            tx.buyerId != me) ||
        ((tx.type == TransactionType.payout ||
                tx.type == TransactionType.auctionFee ||
                tx.type == TransactionType.promotion ||
                tx.type == TransactionType.refund) &&
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

/// Datum kad isplata stiže na račun: 2 radna dana nakon slanja.
DateTime payoutArrival(DateTime sent) {
  var d = sent;
  var left = 2;
  while (left > 0) {
    d = d.add(const Duration(days: 1));
    if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) {
      left--;
    }
  }
  return d;
}

/// Isplata je još na putu do banke.
bool payoutInTransit(LoopTransaction tx, DateTime now) =>
    tx.type == TransactionType.payout &&
    now.isBefore(payoutArrival(tx.createdAt));

/// Financije prodavača kao Whatnot: Isplate (stanje računa, dostupno i na
/// putu, povijest isplata, "Pokreni isplatu"), Transakcije i Izvještaji.
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
    final sales = [
      for (final tx in ledger)
        if (tx.type == TransactionType.sell) tx,
    ];
    Widget tab(String key, String text) => Tab(key: ValueKey(key), text: text);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('Financije')),
          bottom: TabBar(
            dividerColor: LoopColors.surfaceHover,
            indicatorColor: LoopColors.textPrimary,
            labelColor: LoopColors.textPrimary,
            unselectedLabelColor: LoopColors.textSecondary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
            tabs: [
              tab('fin-tab-payouts', t('Isplate')),
              tab('fin-tab-ledger', t('Transakcije')),
              tab('fin-tab-reports', t('Izvještaji')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PayoutsTab(ledger: ledger),
            _TransactionsTab(ledger: ledger),
            _Reports(sales: sales),
          ],
        ),
      ),
    );
  }
}

/// Tab "Isplate": stanje računa, raspored po stanju, povijest isplata i
/// gumb za isplatu na dnu.
class _PayoutsTab extends ConsumerWidget {
  const _PayoutsTab({required this.ledger});
  final List<LoopTransaction> ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appProvider).currentUser!;
    final now = DateTime.now();
    final payouts = [
      for (final tx in ledger)
        if (tx.type == TransactionType.payout) tx,
    ];
    final transit = payouts
        .where((tx) => payoutInTransit(tx, now))
        .fold<double>(0, (a, tx) => a + tx.amount);
    final held = ref.watch(appProvider).heldEarnings(user.id);
    final balance = user.credits;
    final available = balance - held < 0 ? 0.0 : balance - held;
    final verified = isVerifiedSeller(user);
    final seller = user.seller;
    final muted = TextStyle(color: LoopColors.textSecondary, fontSize: 13);

    Widget balanceRow(String key, double amount, String text, {Widget? end}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: formatCredits(amount),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      TextSpan(text: ' $text'),
                    ],
                  ),
                  key: ValueKey(key),
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              ?end,
            ],
          ),
        );

    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('fin-payouts'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (!verified)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Material(
                    color: LoopColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(kRadius),
                    child: InkWell(
                      key: const ValueKey('fin-verify'),
                      borderRadius: BorderRadius.circular(kRadius),
                      onTap: () => SellerVerificationScreen.open(context),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              color: LoopColors.accent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t('Započni verifikaciju prodavača'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    t('Potrebno za isplate na tvoj račun.'),
                                    style: muted,
                                  ),
                                ],
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
                ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: LoopColors.surface,
                  borderRadius: BorderRadius.circular(kRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('Stanje računa'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatCredits(balance),
                      key: const ValueKey('fin-balance'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 34,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: LoopColors.surfaceHover,
                        borderRadius: BorderRadius.circular(kRadius - 4),
                      ),
                      child: Column(
                        children: [
                          balanceRow(
                            'fin-available',
                            available,
                            t('dostupno za isplatu'),
                          ),
                          if (held > 0) ...[
                            Divider(height: 1, color: LoopColors.surface),
                            balanceRow(
                              'fin-held',
                              held,
                              t('zadržano zbog zahtjeva za povrat'),
                              end: Icon(
                                Icons.lock_clock_outlined,
                                size: 18,
                                color: LoopColors.accent,
                              ),
                            ),
                          ],
                          Divider(height: 1, color: LoopColors.surface),
                          balanceRow(
                            'fin-transit',
                            transit,
                            t('na putu do banke'),
                            end: Tooltip(
                              message: t(
                                'Isplate stižu za 1–2 radna dana nakon slanja.',
                              ),
                              child: Icon(
                                Icons.info_outline,
                                size: 18,
                                color: LoopColors.textSecondary,
                              ),
                            ),
                          ),
                          Divider(height: 1, color: LoopColors.surface),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.bolt,
                                  size: 18,
                                  color: LoopColors.buyNow,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    t(
                                      'Isplata je besplatna i bez najmanjeg iznosa.',
                                    ),
                                    style: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      key: const ValueKey('fin-bank'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => SellerInfoScreen.open(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.account_balance_outlined,
                              size: 20,
                              color: LoopColors.textSecondary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                seller == null
                                    ? t('Dodaj račun za isplatu')
                                    : t('Isplata na {0}', [seller.maskedIban]),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: LoopColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                t('Povijest isplata'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              if (payouts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 40,
                        color: LoopColors.textSecondary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t('Još nema isplata.'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        t('Isplate koje pokreneš pojavit će se ovdje.'),
                        style: muted,
                      ),
                    ],
                  ),
                )
              else
                for (final tx in payouts)
                  _PayoutRow(tx: tx, inTransit: payoutInTransit(tx, now)),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    key: const ValueKey('fin-payout'),
                    onPressed: available > 0
                        ? () => showPayoutDialog(context, ref)
                        : null,
                    child: Text(t('Pokreni isplatu')),
                  ),
                ),
                const SizedBox(height: 6),
                Text(t('Novac obično stiže za 1–2 radna dana.'), style: muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.tx, required this.inTransit});
  final LoopTransaction tx;
  final bool inTransit;

  @override
  Widget build(BuildContext context) {
    final color = inTransit ? LoopColors.accent : LoopColors.success;
    return Padding(
      key: ValueKey('fin-payout-${tx.id}'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: LoopColors.surfaceHover,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.account_balance_outlined, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatCredits(tx.amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                Text(
                  inTransit
                      ? t('Poslano {0} · stiže do {1}', [
                          formatDate(tx.createdAt),
                          formatDate(payoutArrival(tx.createdAt)),
                        ])
                      : t('Poslano {0}', [formatDate(tx.createdAt)]),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              inTransit ? t('Na putu') : t('Isplaćeno'),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vrsta stavke u transakcijama prodavača (čipovi filtra).
enum _TxFilter { all, sales, payouts, fees }

/// Tab "Transakcije": prodaje, isplate, naknade i promocije po danima.
class _TransactionsTab extends StatefulWidget {
  const _TransactionsTab({required this.ledger});
  final List<LoopTransaction> ledger;

  @override
  State<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<_TransactionsTab> {
  _TxFilter _filter = _TxFilter.all;

  bool _matches(LoopTransaction tx) => switch (_filter) {
    _TxFilter.all => true,
    _TxFilter.sales => tx.type == TransactionType.sell,
    _TxFilter.payouts => tx.type == TransactionType.payout,
    _TxFilter.fees =>
      tx.type == TransactionType.auctionFee ||
          tx.type == TransactionType.promotion ||
          (tx.type == TransactionType.sell && tx.fee > 0),
  };

  @override
  Widget build(BuildContext context) {
    final list = widget.ledger.where(_matches).toList();
    final labels = {
      _TxFilter.all: t('Sve'),
      _TxFilter.sales: t('Prodaje'),
      _TxFilter.payouts: t('Isplate'),
      _TxFilter.fees: t('Naknade i promocije'),
    };
    final rows = <Widget>[];
    String? day;
    for (final tx in list) {
      final d = formatDate(tx.createdAt);
      if (d != day) {
        day = d;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
            child: Text(
              d,
              style: TextStyle(
                color: LoopColors.textSecondary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        );
      }
      rows.add(_TxRow(tx: tx));
    }
    return ListView(
      key: const ValueKey('fin-transactions'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in _TxFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('fin-filter-${f.name}'),
                    label: Text(labels[f]!),
                    selected: _filter == f,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: t('Još nema prodaja ni isplata.'),
              message: '',
            ),
          )
        else
          ...rows,
      ],
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});
  final LoopTransaction tx;

  @override
  Widget build(BuildContext context) {
    final out = tx.type != TransactionType.sell;
    final icon = switch (tx.type) {
      TransactionType.sell => Icons.sell_outlined,
      TransactionType.payout => Icons.account_balance_outlined,
      TransactionType.promotion => Icons.trending_up,
      _ => Icons.receipt_outlined,
    };
    return Padding(
      key: ValueKey('fin-tx-${tx.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: LoopColors.surfaceHover,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${tx.type.label} · ${formatDateTime(tx.createdAt).split(' ').last}'
                  '${tx.type == TransactionType.sell && tx.fee > 0 ? ' · ${t('naknada {0}', [formatCredits(tx.fee)])}' : ''}',
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${out ? '−' : '+'}${formatCredits(tx.amount.abs())}',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: out ? LoopColors.textPrimary : LoopColors.buyNow,
            ),
          ),
        ],
      ),
    );
  }
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
