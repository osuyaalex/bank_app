/// How much of a payment was left at the end of each day.
///
/// One series, falling from the full amount to zero, so it can never show
/// more gone than the payment was. The card title names it; no legend.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'category_picker.dart' show brandBlue;

const _ink = Color(0xff1C1939);

class MoneyLeftChart extends StatefulWidget {
  const MoneyLeftChart({
    super.key,
    required this.leftByDay,
    required this.amount,
    required this.currency,
    required this.start,
  });

  /// What was left at the end of each day, day one first.
  final List<double> leftByDay;
  final double amount;
  final String currency;
  final DateTime start;

  @override
  State<MoneyLeftChart> createState() => _MoneyLeftChartState();
}

class _MoneyLeftChartState extends State<MoneyLeftChart> {
  int? _selected;

  void _select(Offset local, double width) {
    final n = widget.leftByDay.length;
    if (n == 0) return;
    final i = n == 1
        ? 0
        : ((local.dx / width) * (n - 1)).round().clamp(0, n - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,###');
    final sel = _selected;
    final n = widget.leftByDay.length;
    final end = widget.start.add(Duration(days: n - 1));

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 24,
              child: sel == null
                  ? Text(
                      'Touch the chart to see each day',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    )
                  : Text(
                      '${DateFormat('EEE d MMM').format(widget.start.add(Duration(days: sel)))}'
                      ' · ${widget.currency}${money.format(widget.leftByDay[sel].round())} left',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => _select(d.localPosition, width),
              onPanUpdate: (d) => _select(d.localPosition, width),
              onPanEnd: (_) => setState(() => _selected = null),
              onPanCancel: () => setState(() => _selected = null),
              child: SizedBox(
                height: 160,
                width: width,
                child: CustomPaint(
                  painter: _LeftPainter(
                    left: widget.leftByDay,
                    amount: widget.amount,
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

class _LeftPainter extends CustomPainter {
  _LeftPainter({
    required this.left,
    required this.amount,
    required this.selected,
  });

  final List<double> left;
  final double amount;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final n = left.length;
    if (n == 0 || amount <= 0) return;
    double y(double v) => size.height - (v / amount) * size.height;
    double x(int i) => n <= 1 ? 0 : i / (n - 1) * size.width;

    // Baseline: zero left. A recessive hairline.
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = const Color(0xffE6E8F0)
        ..strokeWidth = 1,
    );

    // Start from the full amount at the moment it arrived, then each day.
    final line = Path()..moveTo(0, y(amount));
    for (var i = 0; i < n; i++) {
      line.lineTo(x(i), y(left[i]));
    }
    final area = Path.from(line)
      ..lineTo(x(n - 1), size.height)
      ..lineTo(0, size.height)
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

    final end = Offset(x(n - 1), y(left.last));
    canvas.drawCircle(end, 6, Paint()..color = Colors.white);
    canvas.drawCircle(end, 4.5, Paint()..color = brandBlue);

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
      final p = Offset(sx, y(left[s]));
      canvas.drawCircle(p, 6, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4.5, Paint()..color = brandBlue);
    }
  }

  @override
  bool shouldRepaint(_LeftPainter old) =>
      old.selected != selected || old.left != left || old.amount != amount;
}
