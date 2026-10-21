import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../models/portfolio_point.dart';
import '../theme/app_theme.dart';
import 'formatters.dart';
import '../l10n/tr.dart';

/// Raspon prikaza grafikona.
enum ChartRange {
  week('7D', Duration(days: 7)),
  month('30D', Duration(days: 30)),
  all('Sve', null);

  const ChartRange(this._label, this.duration);
  final String _label;
  String get label => t(_label);
  final Duration? duration;
}

/// Grafikon ukupne vrijednosti (krediti + portfolio) kroz vrijeme.
///
/// Vrijednost se mijenja samo pri transakcijama, pa je linija stepenasta
/// (između događaja vrijednost je stvarno konstantna). Jedna serija: bez
/// legende, naslov je imenuje. Prelazak mišem / dodir prikazuje crosshair
/// i tooltip; ikonom tablice prikazuju se iste vrijednosti kao popis.
class PortfolioChart extends StatefulWidget {
  const PortfolioChart({
    super.key,
    required this.history,
    required this.current,
  });

  /// Povijest, najstarije prvo.
  final List<PortfolioPoint> history;

  /// Trenutno stanje (zadnja točka linije, "sada").
  final PortfolioPoint current;

  @override
  State<PortfolioChart> createState() => _PortfolioChartState();
}

class _PortfolioChartState extends State<PortfolioChart> {
  ChartRange _range = ChartRange.month;
  bool _table = false;

  /// Indeks točke pod kursorom (null = nema hovera).
  int? _hover;

  /// Točke u odabranom rasponu, s početnom vrijednošću na rubu raspona
  /// i trenutnim stanjem na kraju.
  List<PortfolioPoint> _series() {
    final now = widget.current.time;
    final all = [...widget.history, widget.current];
    final d = _range.duration;
    if (d == null) return all.length == 1 ? [all.first, ...all] : all;

    final start = now.subtract(d);
    final before = all.where((p) => !p.time.isAfter(start)).toList();
    final inRange = all.where((p) => p.time.isAfter(start)).toList();
    // Povijest počinje unutar raspona: crtamo od prvog zapisa, ne izmišljamo
    // ravnu liniju prije njega.
    if (before.isEmpty) {
      return inRange.length == 1 ? [...inRange, ...inRange] : inRange;
    }
    final first = before.last;
    return [
      PortfolioPoint(
        time: start,
        credits: first.credits,
        portfolio: first.portfolio,
      ),
      ...inRange,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final series = _series();
    final startV = series.first.total;
    final endV = series.last.total;
    final change = endV - startV;
    final pct = startV == 0 ? 0.0 : change / startV * 100;
    final up = change >= 0;

    final compact = MediaQuery.sizeOf(context).width < 600;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('Vrijednost portfolija'),
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      // Promjena u rasponu: status boja + strelica + tekst,
                      // nikad samo boja.
                      Row(
                        children: [
                          Icon(
                            up ? Icons.trending_up : Icons.trending_down,
                            size: 18,
                            color: up ? LoopColors.success : LoopColors.error,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${up ? '+' : '−'}${formatCredits(change.abs())} '
                              '(${up ? '+' : '−'}${pct.abs().toStringAsFixed(1)}%) '
                              '· ${_range == ChartRange.all ? t('ukupno') : t('zadnjih {0} dana', [_range.duration!.inDays])}',
                              style: TextStyle(
                                color: LoopColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Na mobitelu raspon ide u zaseban red ispod naslova.
                if (!compact)
                  _RangePicker(
                    value: _range,
                    onChanged: (r) => setState(() {
                      _range = r;
                      _hover = null;
                    }),
                  ),
                IconButton(
                  tooltip: _table
                      ? t('Prikaži grafikon')
                      : t('Prikaži tablicu'),
                  onPressed: () => setState(() => _table = !_table),
                  icon: Icon(
                    _table ? Icons.show_chart : Icons.table_rows_outlined,
                  ),
                ),
              ],
            ),
            if (compact) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _RangePicker(
                  value: _range,
                  onChanged: (r) => setState(() {
                    _range = r;
                    _hover = null;
                  }),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: compact ? 180 : 200,
              child: _table ? _TableView(series: series) : _chart(series),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chart(List<PortfolioPoint> series) {
    return LayoutBuilder(
      builder: (context, box) {
        final geo = _Geometry(series, box.biggest);

        void hoverAt(Offset pos) {
          final i = geo.indexAt(pos.dx);
          if (i != _hover) setState(() => _hover = i);
        }

        final hovered = _hover == null ? null : series[_hover!];
        return MouseRegion(
          onHover: (e) => hoverAt(e.localPosition),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            onTapDown: (e) => hoverAt(e.localPosition),
            onHorizontalDragUpdate: (e) => hoverAt(e.localPosition),
            onHorizontalDragEnd: (_) => setState(() => _hover = null),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ChartPainter(
                      geo: geo,
                      color: Theme.of(context).colorScheme.primary,
                      hover: _hover,
                    ),
                  ),
                ),
                if (hovered != null)
                  _Tooltip(
                    point: hovered,
                    anchor: geo.offsetOf(_hover!),
                    width: box.maxWidth,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pretvorba vremena/vrijednosti u piksele (zajedničko za crtanje i hover).
class _Geometry {
  _Geometry(this.series, this.size) {
    final values = series.map((p) => p.total);
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    if (hi - lo < 1) {
      lo -= 50;
      hi += 50;
    }
    final pad = (hi - lo) * 0.15;
    minV = math.max(0, lo - pad);
    maxV = hi + pad;
    t0 = series.first.time.millisecondsSinceEpoch.toDouble();
    final last = series.last.time.millisecondsSinceEpoch.toDouble();
    // Jedna točka (novi korisnik): raspon od barem 1 ms.
    t1 = last - t0 < 1 ? t0 + 1 : last;
  }

  static const left = 58.0; // mjesto za oznake osi Y
  static const bottom = 22.0; // mjesto za datume

  final List<PortfolioPoint> series;
  final Size size;
  late final double minV, maxV, t0, t1;

  double get plotW => size.width - left - 8;
  double get plotH => size.height - bottom;

  double x(DateTime t) =>
      left + (t.millisecondsSinceEpoch - t0) / (t1 - t0) * plotW;
  double y(double v) => plotH - (v - minV) / (maxV - minV) * plotH;

  Offset offsetOf(int i) => Offset(x(series[i].time), y(series[i].total));

  /// Točka koja vrijedi na poziciji kursora (zadnja promjena lijevo od njega).
  int indexAt(double dx) {
    var best = 0;
    for (var i = 0; i < series.length; i++) {
      if (x(series[i].time) <= dx) best = i;
    }
    return best;
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.geo, required this.color, required this.hover});

  final _Geometry geo;
  final Color color;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final s = geo.series;
    final grid = Paint()
      ..color = LoopColors.surfaceHover
      ..strokeWidth = 1;

    // Mreža: 3 tanke pune linije s oznakama vrijednosti.
    for (var k = 0; k <= 2; k++) {
      final v = geo.minV + (geo.maxV - geo.minV) * k / 2;
      final yy = geo.y(v);
      canvas.drawLine(
        Offset(_Geometry.left, yy),
        Offset(size.width - 8, yy),
        grid,
      );
      _text(
        canvas,
        _compact(v),
        Offset(0, yy - 7),
        width: _Geometry.left - 8,
        align: TextAlign.right,
      );
    }

    // Datumi na početku i kraju osi X.
    final fmt = DateFormat('d.M.', 'en_US');
    _text(
      canvas,
      fmt.format(s.first.time),
      Offset(_Geometry.left, geo.plotH + 6),
    );
    _text(
      canvas,
      t('sada'),
      Offset(size.width - 8 - 60, geo.plotH + 6),
      width: 60,
      align: TextAlign.right,
    );

    // Stepenasta putanja.
    final line = Path()..moveTo(geo.x(s.first.time), geo.y(s.first.total));
    for (var i = 1; i < s.length; i++) {
      line.lineTo(geo.x(s[i].time), geo.y(s[i - 1].total));
      line.lineTo(geo.x(s[i].time), geo.y(s[i].total));
    }

    // Ispuna ~10% boje serije.
    final area = Path.from(line)
      ..lineTo(geo.x(s.last.time), geo.plotH)
      ..lineTo(geo.x(s.first.time), geo.plotH)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.10));

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Završna točka (trenutno stanje) s prstenom boje pozadine.
    _dot(canvas, geo.offsetOf(s.length - 1));

    // Crosshair i točka pod kursorom.
    if (hover != null) {
      final o = geo.offsetOf(hover!);
      canvas.drawLine(
        Offset(o.dx, 0),
        Offset(o.dx, geo.plotH),
        Paint()
          ..color = LoopColors.textSecondary.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
      _dot(canvas, o);
    }
  }

  void _dot(Canvas canvas, Offset o) {
    canvas.drawCircle(o, 6, Paint()..color = LoopColors.surface);
    canvas.drawCircle(o, 4, Paint()..color = color);
  }

  static String _compact(double v) =>
      v >= 10000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.round().toString();

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    double? width,
    TextAlign align = TextAlign.left,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: LoopColors.textSecondary, fontSize: 11),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: width ?? 0, maxWidth: width ?? double.infinity);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.geo.series != geo.series ||
      old.geo.size != geo.size ||
      old.hover != hover ||
      old.color != color;
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({
    required this.point,
    required this.anchor,
    required this.width,
  });

  final PortfolioPoint point;
  final Offset anchor;
  final double width;

  static const _w = 176.0;

  @override
  Widget build(BuildContext context) {
    // Tooltip ostaje unutar grafikona: desno od kursora, ili lijevo ako nema mjesta.
    final left = anchor.dx + 12 + _w > width
        ? anchor.dx - 12 - _w
        : anchor.dx + 12;
    return Positioned(
      left: left.clamp(0, math.max(0, width - _w)),
      top: 0,
      child: IgnorePointer(
        child: Container(
          width: _w,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: LoopColors.surfaceHover,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LoopColors.background),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatDateTime(point.time),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 11),
              ),
              SizedBox(height: 4),
              Text(
                formatCredits(point.total),
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 2),
              Text(
                t('Stanje {0}\nPredmeti {1}', [
                  formatNumber(point.credits),
                  formatNumber(point.portfolio),
                ]),
                style: TextStyle(
                  color: LoopColors.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tablični prikaz istih podataka (najnovije prvo).
class _TableView extends StatelessWidget {
  const _TableView({required this.series});
  final List<PortfolioPoint> series;

  @override
  Widget build(BuildContext context) {
    final rows = series.reversed.toList();
    final head = TextStyle(color: LoopColors.textSecondary, fontSize: 12);
    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: Text(t('Vrijeme'), style: head)),
            Expanded(
              flex: 2,
              child: Text(
                t('Stanje računa'),
                style: head,
                textAlign: TextAlign.right,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                t('Predmeti'),
                style: head,
                textAlign: TextAlign.right,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(t('Ukupno'), style: head, textAlign: TextAlign.right),
            ),
          ],
        ),
        const Divider(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final p = rows[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        formatDateTime(p.time),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatNumber(p.credits),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatNumber(p.portfolio),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatNumber(p.total),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.value, required this.onChanged});
  final ChartRange value;
  final ValueChanged<ChartRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: LoopColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in ChartRange.values)
            GestureDetector(
              onTap: () => onChanged(r),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: r == value ? accent.withValues(alpha: 0.18) : null,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  r.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: r == value
                        ? LoopColors.textPrimary
                        : LoopColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
