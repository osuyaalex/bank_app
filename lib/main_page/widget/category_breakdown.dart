import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../data/spend_repository.dart';
import 'category_picker.dart';

/// What made up a category's spending, and the controls to change it.
///
/// Two views of the same month: who the money went to, and when it went.
/// The first is where a counterparty gets moved to another category; the
/// second is where a single transaction gets corrected.
class CategoryBreakdown extends StatefulWidget {
  const CategoryBreakdown({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.currency,
    required this.legacyTotal,
    this.repo,
  });

  final String categoryId;
  final String categoryName;
  final String currency;

  /// What the app's own screens show for this category. Itemised records only
  /// exist for transactions the new pipeline has seen, so this is usually the
  /// larger figure and the difference has to be explained rather than hidden.
  final double legacyTotal;

  final SpendRepository? repo;

  @override
  State<CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends State<CategoryBreakdown> {
  late final SpendRepository _repo = widget.repo ?? SpendRepository();

  List<({String key, int count, double total})> _contributors = [];
  List<TransactionRecord> _txns = [];
  List<Category> _categories = [];
  Set<String> _tracked = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final contributors = await _repo.contributorsTo(widget.categoryId);
      final txns = await _repo.transactionsForCategory(widget.categoryId);
      final categories = await _repo.loadCategories();
      final tracked = await _repo.trackedCategoryNames();
      if (!mounted) return;
      setState(() {
        _contributors = contributors;
        _txns = txns;
        _categories = categories.where((c) => c.active).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _tracked = tracked;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(double v) =>
      '${widget.currency}${NumberFormat('#,##0.00').format(v)}';

  /// Transactions grouped by day, newest day first.
  List<({DateTime day, List<TransactionRecord> items, double total})>
      get _byDay {
    final buckets = <DateTime, List<TransactionRecord>>{};
    for (final t in _txns) {
      final d = t.occurredAt;
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      buckets.putIfAbsent(day, () => []).add(t);
    }
    final days = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        (
          day: day,
          items: buckets[day]!,
          total: buckets[day]!
              .fold<double>(0, (s, t) => s + (t.amount ?? 0)),
        ),
    ];
  }

  Future<Category?> _chooseCategory(String title, String subtitle) async {
    final choice = await showCategoryPicker(
      context,
      title: title,
      subtitle: subtitle,
      categories: _categories.where((c) => c.id != widget.categoryId).toList(),
      tracked: _tracked,
    );
    if (choice == null || choice.notSpending || choice.categoryId == null) {
      return null;
    }
    return _categories.firstWhere((c) => c.id == choice.categoryId);
  }

  Future<void> _switch(({String key, int count, double total}) row) async {
    final target =
        await _chooseCategory(row.key, 'Move to another category');
    if (target == null) return;
    if (!mounted) return;

    // The two things "move it" can mean. Getting this wrong either rewrites
    // history the user considers settled, or leaves spending filed where they
    // no longer think it belongs.
    final moveHistory = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Move ${row.key} to ${target.name}'),
        content: Text(
          'This month you have ${_money(row.total)} from ${row.key} '
          'under ${widget.categoryName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('From now on'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('It was always this'),
          ),
        ],
      ),
    );
    if (moveHistory == null) return;

    await _repo.switchCounterparty(
      key: row.key,
      toCategoryId: target.id,
      toCategoryName: target.name,
      moveHistory: moveHistory,
    );
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(moveHistory
            ? '${row.key} moved to ${target.name}, along with this month.'
            : '${row.key} will go to ${target.name} from now on.'),
      ));
    }
  }

  Future<void> _correct(TransactionRecord txn) async {
    final target = await _chooseCategory(
      _money(txn.amount ?? 0),
      txn.counterpartyKey ?? txn.narration,
    );
    if (target == null) return;
    await _repo.correctTransaction(
      txn: txn,
      toCategoryId: target.id,
      toCategoryName: target.name,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_contributors.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          widget.legacyTotal > 0
              ? 'The ${_money(widget.legacyTotal)} under '
                  '${widget.categoryName} was recorded before the app kept '
                  'individual transactions, so it cannot be broken down yet. '
                  'New spending will appear here.'
              : 'Nothing recorded under ${widget.categoryName} yet this month.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, height: 1.4),
        ),
      );
    }

    final itemised =
        _txns.fold<double>(0, (s, t) => s + (t.amount ?? 0));
    final unaccounted = widget.legacyTotal - itemised;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summary(itemised),
          if (unaccounted > 1) _reconciliation(itemised, unaccounted),
          const SizedBox(height: 22),
          _heading('WHO THIS WENT TO', _contributors.length),
          const SizedBox(height: 10),
          for (final row in _contributors) _contributorRow(row),
          const SizedBox(height: 26),
          _heading('WHEN IT WENT', _byDay.length),
          const SizedBox(height: 10),
          for (final day in _byDay) _dayGroup(day),
        ],
      ),
    );
  }

  /// The category's own total, so the panel stands on its own rather than
  /// making the reader hold the figure from the card above.
  Widget _summary(double itemised) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: brandBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_money(itemised),
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: brandBlue)),
            const SizedBox(height: 2),
            Text(
              '${_txns.length} transaction${_txns.length == 1 ? '' : 's'} '
              'across ${_contributors.length} '
              'place${_contributors.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );

  /// Explains a gap between the category total and what is itemised.
  ///
  /// After the cutover both come from the same records, so this should never
  /// appear -- it stays as a tripwire for the two drifting apart again.
  Widget _reconciliation(double itemised, double unaccounted) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${_money(unaccounted)} of this category is not itemised yet — '
          'it is still waiting in Needs sorting.',
          style: TextStyle(
              fontSize: 11.5, height: 1.4, color: Colors.brown.shade700),
        ),
      );

  Widget _heading(String text, int count) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Text(text,
                style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w700,
                    color: Colors.black38)),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: Colors.grey.shade200)),
          ],
        ),
      );

  Widget _contributorRow(({String key, int count, double total}) row) {
    final initial = row.key.trim().isEmpty ? '?' : row.key.trim()[0];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _switch(row),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: brandBlue.withValues(alpha: 0.14),
                  ),
                  child: Text(initial.toUpperCase(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: brandBlue)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                          '${row.count} transaction${row.count == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_money(row.total),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Move',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: brandBlue.withValues(alpha: 0.9))),
                        Icon(Icons.chevron_right,
                            size: 14, color: brandBlue.withValues(alpha: 0.9)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayGroup(
          ({DateTime day, List<TransactionRecord> items, double total}) g) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(DateFormat('EEEE, d MMM').format(g.day),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                        '${_money(g.total)} · ${g.items.length}',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600)),
                  ),
                ],
              ),
            ),
            for (final t in g.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Material(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(11),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => _correct(t),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.counterpartyKey ?? t.narration,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                                if (t.occurredAt != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                      DateFormat('h:mm a')
                                          .format(t.occurredAt!),
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: Colors.grey.shade500)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_money(t.amount ?? 0),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 12.5)),
                          const SizedBox(width: 6),
                          Icon(Icons.edit_outlined,
                              size: 14, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}
