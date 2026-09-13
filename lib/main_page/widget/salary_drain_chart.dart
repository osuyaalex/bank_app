/// How fast a salary drained: money gone, day by day, against the salary.
///
/// One series, so no legend -- the card title names it. The salary is a solid
/// hairline reference with its own label, not a second series.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'category_picker.dart' show brandBlue;

const _ink = Color(0xff1C1939);

class SalaryDrainChart extends StatefulWidget {
  const SalaryDrainChart({
    super.key,
    required this.dailyTotals,
    required this.salary,
    required this.currency,
    required this.start,
  });

  /// Money out on each day, day 1 first.
  final List<double> dailyTotals;
  final double salary;
  final String currency;
  final DateTime start;

  @override
  State<SalaryDrainChart> createState() => _SalaryDrainChartState();
}

class _SalaryDrainChartState extends State<SalaryDrainChart> {
  int? _selected;

  List<double> get _cumulative {
    var running = 0.0;
    return [for (final d in widget.dailyTotals) running += d];
  }

  void _select(Offset local, double width) {
    final n = widget.dailyTotals.length;
    if (n == 0) return;
    final i = n == 1
        ? 0
        : ((local.dx / width) * (n - 1)).round().clamp(0, n - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final cumulative = _cumulative;
    final money = NumberFormat('#,###');
    final sel = _selected;

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
                      ' · day ${sel + 1} · '
                      '${widget.currency}${money.format(cumulative[sel].round())} gone',
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
                height: 170,
                width: width,
                child: CustomPaint(
                  painter: _DrainPainter(
                    cumulative: cumulative,
                    salary: widget.salary,
                    selected: sel,
                    salaryLabel:
                        'Salary ${widget.currency}${money.format(widget.salary.round())}',
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
                  'Today',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DrainPainter extends CustomPainter {
  _DrainPainter({
    required this.cumulative,
    required this.salary,
    required this.selected,
    required this.salaryLabel,
  });

  final List<double> cumulative;
  final double salary;
  final int? selected;
  final String salaryLabel;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 18.0; // room for the salary label
    final h = size.height - top;
    final maxY =
        [
          salary,
          if (cumulative.isNotEmpty) cumulative.last,
        ].reduce((a, b) => a > b ? a : b) *
        1.05;
    double y(double v) => top + h - (maxY <= 0 ? 0 : v / maxY * h);
    final n = cumulative.length;
    double x(int i) => n <= 1 ? size.width : i / (n - 1) * size.width;

    // Baseline: a recessive hairline.
    final hair = Paint()
      ..color = const Color(0xffE6E8F0)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, top + h), Offset(size.width, top + h), hair);

    // The salary: a solid hairline reference, labelled in ink, not colour.
    final salaryY = y(salary);
    canvas.drawLine(
      Offset(0, salaryY),
      Offset(size.width, salaryY),
      Paint()
        ..color = const Color(0xffB9BCCB)
        ..strokeWidth = 1,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: salaryLabel,
        style: const TextStyle(fontSize: 11, color: Color(0xff5F5C78)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width, salaryY - tp.height - 2));

    if (n == 0) return;

    final line = Path()..moveTo(x(0), y(cumulative[0]));
    for (var i = 1; i < n; i++) {
      line.lineTo(x(i), y(cumulative[i]));
    }
    final area = Path.from(line)
      ..lineTo(x(n - 1), top + h)
      ..lineTo(x(0), top + h)
      ..close();

    // Area as a wash, never a solid block.
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

    // End dot, with a surface ring so it reads against the line.
    final end = Offset(x(n - 1), y(cumulative.last));
    canvas.drawCircle(end, 6, Paint()..color = Colors.white);
    canvas.drawCircle(end, 4.5, Paint()..color = brandBlue);

    final s = selected;
    if (s != null && s < n) {
      final sx = x(s);
      canvas.drawLine(
        Offset(sx, top),
        Offset(sx, top + h),
        Paint()
          ..color = const Color(0xff9A98AE)
          ..strokeWidth = 1,
      );
      final p = Offset(sx, y(cumulative[s]));
      canvas.drawCircle(p, 6, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4.5, Paint()..color = brandBlue);
    }
  }

  @override
  bool shouldRepaint(_DrainPainter old) =>
      old.selected != selected ||
      old.cumulative != cumulative ||
      old.salary != salary;
}
