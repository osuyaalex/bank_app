/// Where the user's latest salary went.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/salary.dart';
import '../data/salary_store.dart';
import '../data/spend_repository.dart';
import '../parsing/bank_alert.dart';
import 'widget/category_picker.dart' show brandBlue;
import 'widget/salary_drain_chart.dart';

const _ink = Color(0xff1C1939);

class SalaryPage extends StatefulWidget {
  const SalaryPage({super.key});

  @override
  State<SalaryPage> createState() => _SalaryPageState();
}

class _SalaryPageState extends State<SalaryPage> {
  final _store = SalaryStore();

  bool _loading = true;
  String _currency = '₦';
  String? _ownerName;
  List<TransactionRecord> _txns = [];
  Map<String, String> _categoryNames = {};
  Set<String> _ignored = {};

  SalaryPattern? _salary;
  PayCycle? _cycle;
  PayCycle? _previous;

  static final _money = NumberFormat('#,###');
  String _fmt(double v) => '$_currency${_money.format(v.round())}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = SpendRepository();
      final results = await Future.wait([
        _store.recentTransactions(),
        repo.currencySymbol(),
        repo.ownerName(),
        repo.loadCategories(),
        SalaryStore.ignoredPayers(),
      ]);
      _txns = results[0] as List<TransactionRecord>;
      final c = results[1] as String;
      if (c.isNotEmpty) _currency = c;
      _ownerName = results[2] as String?;
      _categoryNames = {
        for (final cat in results[3] as List<Category>) cat.id: cat.name,
      };
      _ignored = results[4] as Set<String>;
      _compute();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      // ignore: avoid_print
      print('SALARY: load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _compute() {
    final candidates = _txns
        .where(
          (t) =>
              t.kind != AlertKind.credit ||
              t.counterpartyKey == null ||
              !_ignored.any((p) => samePayer(p, t.counterpartyKey!)),
        )
        .toList();
    final salary = detectSalary(candidates, ownerName: _ownerName);
    _salary = salary;
    _cycle = null;
    _previous = null;
    final now = DateTime.now();

    if (salary == null) {
      SalaryStore.saveSummary(
        SalarySummary(
          salary: 0,
          spent: 0,
          paidOn: now,
          currency: _currency,
          computedAt: now,
          found: false,
        ),
      );
      return;
    }

    final latest = salary.latest;
    final amount = latest.amount ?? salary.typical;
    _cycle = payCycle(
      _txns,
      start: latest.occurredAt!,
      end: now,
      salary: amount,
    );

    // The previous cycle, cut off at the same day number, so "at this point
    // last month" compares like with like.
    if (salary.paydays.length >= 2) {
      final prev = salary.paydays[salary.paydays.length - 2];
      final full = payCycle(
        _txns,
        start: prev.occurredAt!,
        end: latest.occurredAt!.subtract(const Duration(seconds: 1)),
        salary: prev.amount ?? salary.typical,
      );
      _previous = full;
    }

    SalaryStore.saveSummary(
      SalarySummary(
        salary: amount,
        spent: _cycle!.spent,
        paidOn: latest.occurredAt!,
        currency: _currency,
        computedAt: now,
        found: true,
      ),
    );
  }

  Future<void> _notMySalary() async {
    final s = _salary;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not your salary?'),
        content: Text(
          'Payments from ${_title(s.payer)} will not be treated as salary. '
          'The app will look for another regular payment instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Not my salary'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SalaryStore.ignorePayer(s.payer);
    _ignored = {..._ignored, s.payer};
    setState(_compute);
  }

  String _title(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .map(
        (w) =>
            w.length <= 3 &&
                w == w.toUpperCase() &&
                w.contains(RegExp('[A-Z]{2}'))
            ? w
            : w.isEmpty
            ? w
            : '${w[0]}${w.substring(1).toLowerCase()}',
      )
      .join(' ');

  String _ago(DateTime when) {
    final days = DateTime.now().difference(when).inDays;
    if (days < 1) return 'today';
    if (days == 1) return 'yesterday';
    return '$days days ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          'Where your salary went',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: _salary == null || _cycle == null ? _empty() : _body(),
            ),
    );
  }

  Widget _body() {
    final s = _salary!;
    final c = _cycle!;
    final latest = s.latest;
    final amount = c.salary;
    final share = c.shareGone.clamp(0.0, 1.0);
    final half = c.dayWhenGone(0.5);
    final left = amount - c.spent;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your ${_fmt(amount)} salary arrived ${_ago(latest.occurredAt!)}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Text(
                '${_fmt(c.spent)} gone',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: _ink,
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
              const SizedBox(height: 8),
              Text(
                left > 0
                    ? '${(share * 100).round()}% of it · ${_fmt(left)} not spent yet'
                    : 'More than all of it · ${_fmt(-left)} over',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),
              _line(Icons.flag_outlined, _milestone(half, c)),
              if (_comparison(c) != null)
                _line(Icons.compare_arrows_rounded, _comparison(c)!),
              _line(
                Icons.event_outlined,
                'Next payday expected around ${DateFormat('d MMM').format(s.nextExpected)}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How fast it went',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 8),
              SalaryDrainChart(
                dailyTotals: c.dailyTotals,
                salary: amount,
                currency: _currency,
                start: latest.occurredAt!,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _card(child: _whereItWent(c)),
        const SizedBox(height: 14),
        Text(
          'Paid by ${_title(s.payer)} on ${DateFormat('d MMM').format(latest.occurredAt!)}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        Center(
          child: TextButton(
            onPressed: _notMySalary,
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
            child: const Text('This isn\'t my salary'),
          ),
        ),
      ],
    );
  }

  String _milestone(int? half, PayCycle c) {
    if (half == null) return 'Less than half of it has gone so far';
    if (half == 1) return 'Half of it was gone on the day it arrived';
    return 'Half of it was gone by day $half';
  }

  /// How this cycle compares with the last one at the same point.
  String? _comparison(PayCycle c) {
    final prev = _previous;
    if (prev == null) return null;
    final day = c.daysIn;
    final upTo = prev.dailyTotals.take(day).fold(0.0, (t, d) => t + d);
    final diff = c.spent - upTo;
    if (diff.abs() < 1000) return 'About the same as this point last month';
    return diff > 0
        ? '${_fmt(diff)} more gone than at this point last month'
        : '${_fmt(-diff)} less gone than at this point last month';
  }

  Widget _whereItWent(PayCycle c) {
    final rows = <({String name, double amount})>[
      for (final e in c.byCategory.entries)
        (name: _categoryNames[e.key] ?? 'Other', amount: e.value),
      if (c.unsorted > 0) (name: 'Not sorted yet', amount: c.unsorted),
      if (c.charges > 0) (name: 'Bank charges', amount: c.charges),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    final top = rows.isEmpty ? 1.0 : rows.first.amount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Where it went',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          Text(
            'Nothing spent since it arrived.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ),
                    Text(
                      _fmt(r.amount),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                LayoutBuilder(
                  builder: (_, box) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: (box.maxWidth * (r.amount / top)).clamp(
                        4,
                        box.maxWidth,
                      ),
                      height: 6,
                      decoration: BoxDecoration(
                        color: brandBlue,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: child,
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.payments_outlined, size: 44, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(
          'No regular salary found',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'This appears once the same payment has arrived at least twice, '
          'about a month apart.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        if (_ignored.isNotEmpty) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              await SalaryStore.clearIgnored();
              _ignored = {};
              setState(_compute);
            },
            child: const Text('Undo "not my salary"'),
          ),
        ],
      ],
    ),
  );
}
