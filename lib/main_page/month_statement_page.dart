/// One month of money: what came in, what went out, and how it adds up to
/// the balance the bank reported.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/big_payments.dart';
import '../data/models.dart';
import '../data/month_statement.dart';
import '../data/spend_repository.dart';
import '../data/statement_store.dart';
import 'payment_ledger_page.dart';
import 'widget/balance_chart.dart';
import 'widget/category_picker.dart' show brandBlue;

const _ink = Color(0xff1C1939);
final _money = NumberFormat('#,###');

String titleCase(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .map((w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}')
    .join(' ');

String bankLabel(String bank) {
  const kept = {'GTBANK': 'GTBank', 'UBA': 'UBA', 'FCMB': 'FCMB'};
  return kept[bank.toUpperCase()] ?? titleCase(bank);
}

class MonthStatementPage extends StatefulWidget {
  const MonthStatementPage({super.key});

  @override
  State<MonthStatementPage> createState() => _MonthStatementPageState();
}

class _MonthStatementPageState extends State<MonthStatementPage> {
  bool _loading = true;
  String _currency = '₦';
  StatementData? _data;
  Map<String, String> _categoryNames = {};
  List<DateTime> _months = [];
  int _monthIndex = 0;
  MonthStatement? _statement;
  Map<String, BigPayment> _bigPayments = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = SpendRepository();
      final results = await Future.wait([
        StatementStore().load(),
        repo.currencySymbol(),
        repo.loadCategories(),
      ]);
      final data = results[0] as StatementData;
      final c = results[1] as String;
      if (c.isNotEmpty) _currency = c;
      _categoryNames = {
        for (final cat in results[2] as List<Category>) cat.id: cat.name,
      };
      _data = data;
      _months = statementMonths(data.history, limit: StatementStore.months);
      _bigPayments = {
        for (final p in whereBigPaymentsWent(
          data.history,
          ownerName: data.ownerName,
          ownKeys: data.ownKeys,
        ))
          p.credit.smsId: p,
      };
      _show(0);
      if (_statement != null) {
        StatementStore.saveSummary(_statement!, currency: _currency);
      }
    } catch (e) {
      // ignore: avoid_print
      print('STATEMENT: load failed: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _show(int index) {
    final data = _data;
    if (data == null || _months.isEmpty) return;
    _monthIndex = index;
    _statement = statementFor(
      data.history,
      _months[index],
      ownerName: data.ownerName,
      ownKeys: data.ownKeys,
    );
  }

  String _fmt(double v) =>
      '${v < 0 ? '-' : ''}$_currency${_money.format(v.abs().round())}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    final m = _statement!.month;
    return m.year == now.year && m.month == now.month;
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
          'Money in and out',
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
              child: _statement == null || _statement!.isEmpty
                  ? _empty()
                  : _body(),
            ),
    );
  }

  Widget _body() {
    final s = _statement!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _monthSwitcher(),
        const SizedBox(height: 8),
        _headline(s),
        if (s.checkedAccounts.isNotEmpty) ...[
          const SizedBox(height: 14),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title('Your balance, all accounts'),
                const SizedBox(height: 8),
                BalanceChart(
                  balances: s.dailyBalance,
                  moneyIn: s.dailyIn,
                  moneyOut: s.dailyOut,
                  start: s.month,
                  currency: _currency,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _card(_addsUp(s)),
        ],
        const SizedBox(height: 14),
        _card(_moneyIn(s)),
        const SizedBox(height: 14),
        _card(_moneyOut(s)),
      ],
    );
  }

  Widget _monthSwitcher() {
    final older = _monthIndex < _months.length - 1;
    final newer = _monthIndex > 0;
    final label = DateFormat('MMMM yyyy').format(_months[_monthIndex]);
    return Row(
      children: [
        IconButton(
          onPressed: older
              ? () => setState(() => _show(_monthIndex + 1))
              : null,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Earlier month',
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              if (_isCurrentMonth)
                Text(
                  'So far',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: newer
              ? () => setState(() => _show(_monthIndex - 1))
              : null,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Later month',
        ),
      ],
    );
  }

  Widget _headline(MonthStatement s) {
    final moved = s.movedIn > s.movedOut ? s.movedIn : s.movedOut;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _figure('Money in', s.moneyIn)),
              Container(width: 1, height: 44, color: Colors.grey.shade200),
              const SizedBox(width: 16),
              Expanded(child: _figure('Money out', s.moneyOut)),
            ],
          ),
          if (moved >= 0.5) ...[
            const SizedBox(height: 12),
            _note(
              Icons.swap_horiz_rounded,
              '${_fmt(moved)} moved between your own accounts. '
              'Not counted as either.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _figure(String label, double value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          _fmt(value),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // How it adds up
  // ---------------------------------------------------------------------------

  Widget _addsUp(MonthStatement s) {
    final startLabel = 'On 1 ${DateFormat('MMMM').format(s.month)}';
    final endLabel = _isCurrentMonth
        ? 'Now'
        : 'On ${DateFormat('d MMMM').format(s.until.subtract(const Duration(days: 1)))}';
    final moved = s.checkedMovedNet;
    final declined = s.declined.fold(0.0, (t, d) => t + (d.amount ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('How it adds up'),
        const SizedBox(height: 4),
        Text(
          'Starting from the balances in your bank texts.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        _sumRow(startLabel, _fmt(s.openingTotal)),
        _sumRow('+ Money in', _fmt(s.checkedIn)),
        _sumRow('− Money out', _fmt(s.checkedOut)),
        if (moved.abs() >= 0.5)
          _sumRow(
            moved > 0
                ? '+ Moved in from your other accounts'
                : '− Moved to your other accounts',
            _fmt(moved.abs()),
          ),
        if (s.leftWithoutText >= 0.5)
          _sumRow(
            '− Left with no bank text',
            _fmt(s.leftWithoutText),
            flagged: true,
          ),
        if (s.arrivedWithoutText >= 0.5)
          _sumRow(
            '+ Arrived with no bank text',
            _fmt(s.arrivedWithoutText),
            flagged: true,
          ),
        const Divider(height: 18),
        _sumRow(endLabel, _fmt(s.closingTotal), bold: true),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 15,
              color: Colors.green.shade600,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Matches the balance in your latest bank texts',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
        if (s.leftWithoutText >= 0.5 || s.arrivedWithoutText >= 0.5) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xffFFF7E6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              s.leftWithoutText >= 0.5
                  ? 'Your balance fell by ${_fmt(s.leftWithoutText)} more than '
                        'your texts explain. Usually a card payment, a charge, '
                        'or a transfer your bank didn\'t text you about. Your '
                        'bank app will show what it was.'
                  : 'Your balance rose by ${_fmt(s.arrivedWithoutText)} more '
                        'than your texts explain. Usually money that arrived '
                        'without a text, or a payment that was reversed.',
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: _ink),
            ),
          ),
        ],
        if (s.declined.isNotEmpty) ...[
          const SizedBox(height: 12),
          _note(
            Icons.block_rounded,
            '${s.declined.length == 1 ? 'A declined payment' : '${s.declined.length} declined payments'} '
            '(${_fmt(declined)}) not counted. Your bank texted, but your '
            'balance didn\'t change.',
          ),
        ],
        const SizedBox(height: 14),
        for (final a in s.accounts) _accountRow(a),
      ],
    );
  }

  Widget _sumRow(
    String label,
    String value, {
    bool bold = false,
    bool flagged = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: flagged ? const Color(0xffA15C00) : _ink,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: flagged ? const Color(0xffA15C00) : _ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );

  Widget _accountRow(AccountMonth a) {
    final name =
        '${bankLabel(a.bank)}${a.lastDigits.isEmpty ? '' : ' ••${a.lastDigits}'}';
    final String detail;
    if (!a.checked) {
      detail = 'Its texts don\'t show a balance, so it isn\'t in the sum';
    } else if (a.lastText == null || a.lastText!.isBefore(_statement!.month)) {
      detail =
          '${_fmt(a.closing!)} · no texts this month, last on '
          '${DateFormat('d MMM').format(a.lastText!)}';
    } else {
      final gap = a.unexplained;
      detail =
          '${_fmt(a.opening!)} → ${_fmt(a.closing!)}'
          '${gap.abs() >= unexplainedTolerance ? ' · ${_fmt(gap.abs())} not in any text' : ''}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.account_balance_outlined,
            size: 16,
            color: Colors.grey.shade500,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Money in
  // ---------------------------------------------------------------------------

  Widget _moneyIn(MonthStatement s) {
    const shown = 6;
    final lines = s.received;
    final rest = lines.skip(shown).toList();
    final restTotal = rest.fold(0.0, (t, l) => t + l.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Money in'),
        const SizedBox(height: 8),
        if (lines.isEmpty && s.refunds < 0.5)
          Text(
            'Nothing came in.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        for (final l in lines.take(shown)) _receivedRow(l),
        if (rest.isNotEmpty)
          _plainRow(
            '${rest.length} smaller payment${rest.length == 1 ? '' : 's'}',
            restTotal,
          ),
        if (s.refunds >= 0.5) _plainRow('Refunds and reversals', s.refunds),
      ],
    );
  }

  Widget _receivedRow(StatementLine l) {
    final big = _bigPayments[l.smsId];
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleCase(l.name),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  big == null
                      ? DateFormat('d MMM').format(l.when)
                      : '${DateFormat('d MMM').format(l.when)} · See where it went',
                  style: TextStyle(
                    fontSize: 12,
                    color: big == null ? Colors.grey.shade600 : brandBlue,
                    fontWeight: big == null ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _fmt(l.amount),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          if (big != null)
            const Icon(Icons.chevron_right, size: 20, color: Colors.black38),
        ],
      ),
    );
    if (big == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentLedgerPage(
            payment: big,
            currency: _currency,
            categoryNames: _categoryNames,
          ),
        ),
      ),
      child: row,
    );
  }

  Widget _plainRow(String name, double amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
        ),
        Text(
          _fmt(amount),
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------------------
  // Money out
  // ---------------------------------------------------------------------------

  Widget _moneyOut(MonthStatement s) {
    const shownPayees = 5;
    final payees = s.unsortedByPayee.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final rest = payees.skip(shownPayees).fold(0.0, (t, e) => t + e.value);
    final rows = <({String name, double amount})>[
      for (final e in s.spentByCategory.entries)
        (name: _categoryNames[e.key] ?? 'Other', amount: e.value),
      for (final e in payees.take(shownPayees))
        (name: '${titleCase(e.key)} (not sorted)', amount: e.value),
      if (rest >= 0.5) (name: 'Others, not sorted', amount: rest),
      if (s.charges >= 0.5) (name: 'Bank charges', amount: s.charges),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    final top = rows.isEmpty ? 1.0 : rows.first.amount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Money out'),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          Text(
            'Nothing went out.',
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

  // ---------------------------------------------------------------------------

  Widget _empty() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.receipt_long_outlined,
          size: 44,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Text(
          'No bank texts yet',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'When your bank texts you, your month shows up here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ],
    ),
  );

  Widget _title(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: _ink,
    ),
  );

  Widget _note(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: Colors.grey.shade500),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: Colors.grey.shade700,
          ),
        ),
      ),
    ],
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
