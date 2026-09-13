/// The money in every account the app can check, at the end of each day.
///
/// One series, so no legend: the card title names it. Touching the chart
/// shows that day's balance and what came in and went out, which is what
/// explains a jump or a fall.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'category_picker.dart' show brandBlue;

const _ink = Color(0xff1C1939);

class BalanceChart extends StatefulWidget {
  const BalanceChart({
    super.key,
    required this.balances,
    required this.start,
    required this.currency,
    this.moneyIn = const [],
    this.moneyOut = const [],
  });

  /// The balance at the end of each day, day one first.
  final List<double> balances;

  /// Money in and out on each day, same order. Optional.
  final List<double> moneyIn;
  final List<double> moneyOut;

  final DateTime start;
  final String currency;

  @override
  State<BalanceChart> createState() => _BalanceChartState();
}

class _BalanceChartState extends State<BalanceChart> {
  int? _selected;

  void _select(Offset local, double width) {
    final n = widget.balances.length;
    if (n == 0) return;
    final i = n == 1
        ? 0
        : ((local.dx / width) * (n - 1)).round().clamp(0, n - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,###');
    String fmt(double v) =>
        '${v < 0 ? '-' : ''}${widget.currency}${money.format(v.abs().round())}';
    final sel = _selected;
    final n = widget.balances.length;
    final end = widget.start.add(Duration(days: n - 1));

    String label(int i) {
      final parts = [
        DateFormat('EEE d MMM').format(widget.start.add(Duration(days: i))),
        fmt(widget.balances[i]),
      ];
      if (i < widget.moneyIn.length && widget.moneyIn[i] >= 0.5) {
        parts.add('in ${fmt(widget.moneyIn[i])}');
      }
      if (i < widget.moneyOut.length && widget.moneyOut[i] >= 0.5) {
        parts.add('out ${fmt(widget.moneyOut[i])}');
      }
      return parts.join(' · ');
    }

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 22,
              child: sel == null
                  ? Text(
                      'Touch the chart to see each day',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label(sel),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => _select(d.localPosition, width),
              onPanUpdate: (d) => _select(d.localPosition, width),
              onPanEnd: (_) => setState(() => _selected = null),
              onPanCancel: () => setState(() => _selected = null),
              child: SizedBox(
                height: 150,
                width: width,
                child: CustomPaint(
                  painter: _BalancePainter(
                    values: widget.balances,
                    selected: sel,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  DateFormat('d MMM').format(widget.start),
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
                const Spacer(),
                Text(
                  _isToday(end) ? 'Today' : DateFormat('d MMM').format(end),
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

class _BalancePainter extends CustomPainter {
  _BalancePainter({required this.values, required this.selected});

  final List<double> values;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final top = values.reduce((a, b) => a > b ? a : b);
    final bottom = values
        .reduce((a, b) => a < b ? a : b)
        .clamp(double.negativeInfinity, 0.0);
    final span = (top - bottom) <= 0 ? 1.0 : top - bottom;
    // A little room above the highest point so the line never clips.
    final plot = size.height - 6;
    double y(double v) => 6 + plot - ((v - bottom) / span) * plot;
    double x(int i) => n <= 1 ? size.width / 2 : i / (n - 1) * size.width;

    // Zero. A recessive hairline.
    canvas.drawLine(
      Offset(0, y(0)),
      Offset(size.width, y(0)),
      Paint()
        ..color = const Color(0xffE6E8F0)
        ..strokeWidth = 1,
    );

    final line = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < n; i++) {
      line.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(line)
      ..lineTo(x(n - 1), y(0))
      ..lineTo(x(0), y(0))
      ..close();

    canvas.drawPath(area, Paint()..color = brandBlue.withValues(alpha: 0.10));
    canvas.drawPath(
      line,
      Paint()
        ..color = brandBlue
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    void dot(Offset p) {
      canvas.drawCircle(p, 6, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4.5, Paint()..color = brandBlue);
    }

    dot(Offset(x(n - 1), y(values.last)));

    final s = selected;
    if (s != null && s < n) {
      final sx = x(s);
      canvas.drawLine(
        Offset(sx, 0),
        Offset(sx, size.height),
        Paint()
          ..color = const Color(0xff9A98AE)
          ..strokeWidth = 1,
      );
      dot(Offset(sx, y(values[s])));
    }
  }

  @override
  bool shouldRepaint(_BalancePainter old) =>
      old.selected != selected || old.values != values;
}
