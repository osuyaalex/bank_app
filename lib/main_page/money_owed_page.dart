/// Who owes the user money, and which past transfers might have been loans.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/money_owed.dart';
import '../data/money_owed_store.dart';
import '../data/spend_repository.dart';
import 'widget/category_picker.dart' show brandBlue;

const _ink = Color(0xff1C1939);

class MoneyOwedPage extends StatefulWidget {
  const MoneyOwedPage({super.key});

  @override
  State<MoneyOwedPage> createState() => _MoneyOwedPageState();
}

class _MoneyOwedPageState extends State<MoneyOwedPage> {
  final _store = MoneyOwedStore();

  bool _loading = true;
  String _currency = '₦';
  String? _ownerName;
  List<TransactionRecord> _transfers = [];
  Map<String, LoanDecision> _decisions = {};

  List<PersonOwing> get _owed => moneyOwed(_transfers, decisions: _decisions);
  List<LoanCandidate> get _candidates =>
      loanCandidates(_transfers, decisions: _decisions, ownerName: _ownerName);

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
        _store.transfers(),
        _store.decisions(),
        repo.currencySymbol(),
        repo.ownerName(),
      ]);
      if (!mounted) return;
      setState(() {
        _transfers = results[0] as List<TransactionRecord>;
        _decisions = results[1] as Map<String, LoanDecision>;
        final c = results[2] as String;
        if (c.isNotEmpty) _currency = c;
        _ownerName = results[3] as String?;
        _loading = false;
      });
      _remember();
    } catch (e) {
      // ignore: avoid_print
      print('MONEY OWED: load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Keeps the home screen's summary in step with what is shown here.
  void _remember() {
    final owed = _owed;
    MoneyOwedStore.saveSummary(
      outstanding: owed.fold(0.0, (t, p) => t + p.outstanding),
      people: owed.length,
      toReview: _candidates.length,
      currency: _currency,
    );
  }

  Future<void> _decide(LoanCandidate c, LoanDecision decision) async {
    final smsId = c.transfer.smsId;
    setState(() => _decisions = {..._decisions, smsId: decision});
    _remember();
    try {
      await _store.decide(c.transfer, decision);
    } catch (_) {
      if (!mounted) return;
      setState(() => _decisions = {..._decisions}..remove(smsId));
      _say('Could not save that. Check your connection.');
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          decision == LoanDecision.loan
              ? 'Added to money owed to you.'
              : 'Got it. Not a loan.',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            setState(() => _decisions = {..._decisions}..remove(smsId));
            _remember();
            await _store.forget(smsId);
          },
        ),
      ),
    );
  }

  Future<void> _copyReminder(PersonOwing p) async {
    await Clipboard.setData(
      ClipboardData(text: reminderText(p, currency: _currency)),
    );
    _say('Reminder copied. Paste it into your chat with ${_first(p.name)}.');
  }

  Future<void> _markPaid(PersonOwing p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_first(p.name)} paid you back?'),
        content: Text(
          'This clears the ${_fmt(p.outstanding)} still showing. Use it if '
          'they paid in cash or some other way the app could not see.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, paid'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final before = _decisions;
    setState(
      () => _decisions = {
        ..._decisions,
        for (final l in p.loans.where((l) => l.isOpen))
          l.transfer.smsId: LoanDecision.settled,
      },
    );
    _remember();
    try {
      await _store.settle(p);
    } catch (_) {
      if (!mounted) return;
      setState(() => _decisions = before);
      _say('Could not save that. Check your connection.');
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _first(String name) {
    final w = name.trim().split(RegExp(r'\s+')).first;
    return w.isEmpty ? name : '${w[0]}${w.substring(1).toLowerCase()}';
  }

  String _title(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}')
      .join(' ');

  String _ago(DateTime? when) {
    if (when == null) return '';
    final days = DateTime.now().difference(when).inDays;
    if (days < 1) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 14) return '$days days ago';
    if (days < 60) return '${(days / 7).floor()} weeks ago';
    return '${(days / 30).floor()} months ago';
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
          'Money owed to you',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(child: _body()),
    );
  }

  Widget _body() {
    final owed = _owed;
    final candidates = _candidates;
    final total = owed.fold(0.0, (t, p) => t + p.outstanding);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _header(total, owed.length),
        if (owed.isNotEmpty) ...[
          const SizedBox(height: 24),
          _label('OWED TO YOU'),
          for (final p in owed) _personCard(p),
        ],
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: 24),
          _label('WERE ANY OF THESE LOANS?'),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Only the ones you mark as loans are counted.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          for (final c in candidates) _candidateCard(c),
        ],
        if (owed.isEmpty && candidates.isEmpty) _empty(),
      ],
    );
  }

  Widget _header(double total, int people) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Owed to you',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),
        Text(
          _fmt(total),
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          people == 0
              ? 'Nobody owes you anything right now'
              : people == 1
              ? 'by 1 person'
              : 'across $people people',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ],
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w800,
        color: Colors.grey.shade500,
      ),
    ),
  );

  Widget _personCard(PersonOwing p) {
    final repaidLine = p.repaid > 0.5 ? ' · ${_fmt(p.repaid)} paid back' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _title(p.name),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ),
              Text(
                _fmt(p.outstanding),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: brandBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Lent ${_fmt(p.lent)}, ${_ago(p.oldestOpen)}$repaidLine',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _copyReminder(p),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                label: const Text('Copy reminder'),
                style: TextButton.styleFrom(foregroundColor: brandBlue),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _markPaid(p),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                ),
                child: const Text('Mark as paid'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _candidateCard(LoanCandidate c) {
    final t = c.transfer;
    final when = t.occurredAt == null
        ? ''
        : DateFormat('d MMM yyyy').format(t.occurredAt!);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _title(t.counterpartyKey ?? ''),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ),
              Text(
                _fmt(t.amount ?? 0),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            c.hasSentBack
                ? 'Sent $when · ${_first(t.counterpartyKey ?? '')} has sent you money before'
                : 'Sent $when',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _decide(c, LoanDecision.notLoan),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade800,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Not a loan'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _decide(c, LoanDecision.loan),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('It was a loan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.only(top: 40),
    child: Column(
      children: [
        Icon(Icons.handshake_outlined, size: 44, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(
          'Nothing to show yet',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'When you send someone ${_fmt(loanCandidateFloor)} or more, '
          'it will show up here so you can mark it as a loan.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ],
    ),
  );
}
