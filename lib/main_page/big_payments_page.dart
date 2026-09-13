/// Every big payment the user received, and what happened to each one.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/big_payment_store.dart';
import '../data/big_payments.dart';
import '../data/models.dart';
import '../data/spend_repository.dart';
import 'widget/category_picker.dart' show brandBlue;
import 'widget/money_left_chart.dart';

const _ink = Color(0xff1C1939);
final _money = NumberFormat('#,###');

String _title(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .map((w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}')
    .join(' ');

class BigPaymentsPage extends StatefulWidget {
  const BigPaymentsPage({super.key});

  @override
  State<BigPaymentsPage> createState() => _BigPaymentsPageState();
}

class _BigPaymentsPageState extends State<BigPaymentsPage> {
  final _store = BigPaymentStore();

  bool _loading = true;
  String _currency = '₦';
  String? _ownerName;
  List<TransactionRecord> _history = [];
  Map<String, String> _categoryNames = {};
  Set<String> _hidden = {};
  List<BigPayment> _payments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = SpendRepository();
      final results = await Future.wait([
        _store.history(),
        repo.currencySymbol(),
        repo.ownerName(),
        repo.loadCategories(),
        BigPaymentStore.hidden(),
      ]);
      _history = results[0] as List<TransactionRecord>;
      final c = results[1] as String;
      if (c.isNotEmpty) _currency = c;
      _ownerName = results[2] as String?;
      _categoryNames = {
        for (final cat in results[3] as List<Category>) cat.id: cat.name,
      };
      _hidden = results[4] as Set<String>;
      _compute();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      // ignore: avoid_print
      print('BIG PAYMENTS: load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _compute() {
    _payments = whereBigPaymentsWent(
      _history,
      ownerName: _ownerName,
      hidden: _hidden,
    );
    BigPaymentStore.saveSummary(_payments, currency: _currency);
  }

  Future<void> _open(BigPayment p) async {
    final hide = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BigPaymentPage(
          payment: p,
          currency: _currency,
          categoryNames: _categoryNames,
        ),
      ),
    );
    if (hide != true) return;
    await BigPaymentStore.hide(p.credit.smsId);
    _hidden = {..._hidden, p.credit.smsId};
    setState(_compute);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Hidden. ${_title(p.from)} will not be followed.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await BigPaymentStore.unhide(p.credit.smsId);
            _hidden = {..._hidden}..remove(p.credit.smsId);
            if (mounted) setState(_compute);
          },
        ),
      ),
    );
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
          'Where your money went',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(child: _payments.isEmpty ? _empty() : _list()),
    );
  }

  Widget _list() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
        child: Text(
          'Every payment of ${_currency}100,000 or more you received, '
          'and what happened to it.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ),
      for (final p in _payments) _paymentCard(p),
    ],
  );

  Widget _paymentCard(BigPayment p) {
    final share = p.amount <= 0 ? 0.0 : (p.used / p.amount).clamp(0.0, 1.0);
    final status = p.isGone
        ? p.daysToGo == 1
              ? 'All gone the same day'
              : 'All gone in ${p.daysToGo} days'
        : '$_currency${_money.format(p.left.round())} left';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(p),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_currency${_money.format(p.amount.round())}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'from ${_title(p.from)} · ${DateFormat('d MMM yyyy').format(p.arrivedAt)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: share,
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation(brandBlue),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.payments_outlined, size: 44, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(
          'No big payments yet',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'When ${_currency}100,000 or more arrives in one payment, this '
          'shows where it went.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ],
    ),
  );
}

/// One big payment in detail. Pops `true` if the user chose to hide it.
class BigPaymentPage extends StatelessWidget {
  const BigPaymentPage({
    super.key,
    required this.payment,
    required this.currency,
    required this.categoryNames,
  });

  final BigPayment payment;
  final String currency;
  final Map<String, String> categoryNames;

  String _fmt(double v) => '$currency${_money.format(v.round())}';

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final now = DateTime.now();
    final until = p.goneOn ?? now;
    final share = p.amount <= 0 ? 0.0 : (p.used / p.amount).clamp(0.0, 1.0);

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
          '${_fmt(p.amount)} from ${_title(p.from)}',
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
                    'Arrived ${DateFormat('EEEE d MMM').format(p.arrivedAt)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.isGone ? 'All of it is gone' : '${_fmt(p.left)} left',
                    style: const TextStyle(
                      fontSize: 28,
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
                    '${_fmt(p.used)} of ${_fmt(p.amount)} spent',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (p.isGone)
                    _line(
                      Icons.flag_outlined,
                      p.daysToGo == 1
                          ? 'It was all gone the same day'
                          : 'It was all gone by ${DateFormat('d MMM').format(p.goneOn!)}, '
                                'in ${p.daysToGo} days',
                    ),
                  if (p.fromOtherMoney > 0.5)
                    _line(
                      Icons.account_balance_wallet_outlined,
                      'After that, ${_fmt(p.fromOtherMoney)} more was spent from '
                      'other money you had',
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
                    'How much was left each day',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  MoneyLeftChart(
                    leftByDay: p.leftByDay(until),
                    amount: p.amount,
                    currency: currency,
                    start: p.arrivedAt,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _card(_whereItWent()),
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                ),
                child: const Text('This wasn\'t really my money, hide it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _whereItWent() {
    final p = payment;
    const shown = 4;
    final payees = p.unsortedByPayee.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final rest = payees.skip(shown).fold(0.0, (t, e) => t + e.value);
    final rows = <({String name, double amount})>[
      for (final e in p.byCategory.entries)
        (name: categoryNames[e.key] ?? 'Other', amount: e.value),
      for (final e in payees.take(shown))
        (name: '${_title(e.key)} (not sorted)', amount: e.value),
      if (rest > 0) (name: 'Other, not sorted yet', amount: rest),
      if (p.charges > 0) (name: 'Bank charges', amount: p.charges),
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
            'None of it has been spent yet.',
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
