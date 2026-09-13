/// One big payment, as a statement of its own: every payment counted against
/// it, in order, with what was left after each.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/big_payments.dart';
import '../data/models.dart';
import '../parsing/bank_alert.dart';
import 'month_statement_page.dart' show titleCase;
import 'widget/category_picker.dart' show brandBlue;

const _ink = Color(0xff1C1939);
final _money = NumberFormat('#,##0');
final _exact = NumberFormat('#,##0.##');

/// One line of the ledger. A transfer and the charge the bank took for it
/// arrive as two texts stamped with the same second; they read as one line.
class _LedgerLine {
  _LedgerLine(this.first);

  final PaymentUse first;
  final List<PaymentUse> charges = [];
  PaymentUse? main;

  DateTime get when => first.spend.occurredAt!;
  double get taken =>
      (main?.taken ?? 0) + charges.fold(0.0, (t, c) => t + c.taken);
  double get chargeTaken => charges.fold(0.0, (t, c) => t + c.taken);
  double get leftAfter => [
    if (main != null) main!.leftAfter,
    for (final c in charges) c.leftAfter,
  ].reduce((a, b) => a < b ? a : b);
}

List<_LedgerLine> _lines(List<PaymentUse> uses) {
  final lines = <_LedgerLine>[];
  for (final u in uses) {
    final isCharge = u.spend.kind == AlertKind.charge;
    final same =
        lines.isNotEmpty &&
            lines.last.when == u.spend.occurredAt &&
            lines.last.first.spend.bank == u.spend.bank
        ? lines.last
        : null;
    if (same != null && (isCharge || same.main == null)) {
      if (isCharge) {
        same.charges.add(u);
      } else {
        same.main = u;
      }
      continue;
    }
    final line = _LedgerLine(u);
    if (isCharge) {
      line.charges.add(u);
    } else {
      line.main = u;
    }
    lines.add(line);
  }
  return lines;
}

class PaymentLedgerPage extends StatelessWidget {
  const PaymentLedgerPage({
    super.key,
    required this.payment,
    required this.currency,
    required this.categoryNames,
  });

  final BigPayment payment;
  final String currency;
  final Map<String, String> categoryNames;

  String _fmt(double v) => '$currency${_money.format(v.round())}';
  String _fmtExact(double v) => '$currency${_exact.format(v)}';

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final share = p.amount <= 0 ? 0.0 : (p.used / p.amount).clamp(0.0, 1.0);
    final lines = _lines(p.uses);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          '${_fmt(p.amount)} from ${titleCase(p.from)}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Arrived ${DateFormat('EEEE d MMM, h:mm a').format(p.arrivedAt)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.isGone
                        ? 'All gone by ${DateFormat('d MMM').format(p.goneOn!)}'
                        : '${_fmt(p.left)} left',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  if (p.isGone)
                    Text(
                      p.daysToGo == 1
                          ? 'The same day it arrived'
                          : 'In ${p.daysToGo} days, across ${lines.length} payments',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation(brandBlue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How this is worked out',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _rule(
                    '1',
                    'Everything you paid after it arrived comes out of it, in order.',
                  ),
                  _rule(
                    '2',
                    'If an earlier big payment still had money, that goes first.',
                  ),
                  _rule(
                    '3',
                    'Moving money to your own account and declined payments don\'t count.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ledgerHeader(),
                  const Divider(height: 20),
                  _arrivedRow(),
                  ..._ledgerRows(lines),
                  if (p.isGone) ...[
                    const Divider(height: 24),
                    Text(
                      'All of it is accounted for. Anything you paid after '
                      'this came from other money.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  if (!p.isGone && lines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Nothing has come out of it yet.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rule(String n, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: brandBlue.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            n,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.35, color: _ink),
          ),
        ),
      ],
    ),
  );

  Widget _ledgerHeader() => Row(
    children: [
      const Expanded(
        child: Text(
          'Every payment, in order',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
      ),
      Text(
        'Left',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
        ),
      ),
    ],
  );

  Widget _arrivedRow() => _row(
    title: 'Arrived from ${titleCase(payment.from)}',
    subtitle: DateFormat('EEE d MMM, h:mm a').format(payment.arrivedAt),
    amount: '+${_fmt(payment.amount)}',
    left: _fmt(payment.amount),
    strong: true,
  );

  List<Widget> _ledgerRows(List<_LedgerLine> lines) {
    final out = <Widget>[];
    DateTime? day;
    for (final l in lines) {
      final d = DateTime(l.when.year, l.when.month, l.when.day);
      if (day != d) {
        day = d;
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 2),
            child: Text(
              DateFormat('EEEE d MMM').format(d),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        );
      }
      out.add(_lineRow(l));
    }
    return out;
  }

  Widget _lineRow(_LedgerLine l) {
    final main = l.main;
    final spend = main?.spend;
    final String title;
    if (spend == null) {
      title = 'Bank charge';
    } else if (spend.status == TxnStatus.labeled && spend.categoryId != null) {
      final who = spend.counterpartyKey;
      final category = categoryNames[spend.categoryId] ?? 'Other';
      title = who == null || who.isEmpty
          ? category
          : '${titleCase(who)} · $category';
    } else {
      final who = spend.counterpartyKey;
      title = who == null || who.isEmpty ? 'Unknown' : titleCase(who);
    }

    final details = <String>[DateFormat('h:mm a').format(l.when)];
    if (main != null && l.chargeTaken > 0) {
      details.add('incl. ${_fmtExact(l.chargeTaken)} charge');
    }
    if (main != null && main.isPart) {
      details.add(
        '${_fmt(main.taken)} of ${_fmt(main.spend.amount ?? 0)} from this',
      );
    }

    return _row(
      title: title,
      subtitle: details.join(' · '),
      amount: '−${l.taken < 100 ? _fmtExact(l.taken) : _fmt(l.taken)}',
      left: _fmt(l.leftAfter),
    );
  }

  Widget _row({
    required String title,
    required String subtitle,
    required String amount,
    required String left,
    bool strong = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 88,
          child: Text(
            amount,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: strong ? Colors.green.shade700 : _ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        SizedBox(
          width: 84,
          child: Text(
            left,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: child,
  );
}
