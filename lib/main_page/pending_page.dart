import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/spend_repository.dart';
import 'widget/category_picker.dart';
import 'widget/category_setup_sheet.dart';

/// Transactions the app could not file on its own, waiting for an answer.
///
/// Without this screen a transaction from an unknown counterparty is marked
/// pending in the database and then never surfaces anywhere -- the money is
/// simply missing from the user's totals with nothing to explain it.
class PendingPage extends StatefulWidget {
  const PendingPage({super.key, this.repo, this.embedded = false});

  final SpendRepository? repo;

  /// When true, renders as a bare list for embedding in another screen.
  final bool embedded;

  @override
  State<PendingPage> createState() => _PendingPageState();
}

class _PendingPageState extends State<PendingPage> {
  late final SpendRepository _repo = widget.repo ?? SpendRepository();

  List<TransactionRecord> _pending = [];
  List<Category> _categories = [];
  Set<String> _tracked = {};
  String _currency = '';
  bool _loading = true;

  /// Transactions whose answer is still being written. Filing one settles it
  /// and rebuilds the month, which takes long enough that silence reads as
  /// the tap having missed.
  final Set<String> _savingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pending = await _repo.pendingTransactions();
    final categories = await _repo.loadCategories();
    final tracked = await _repo.trackedCategoryNames();
    final currency = await _repo.currencySymbol();
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _categories = categories.where((c) => c.active).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _tracked = tracked;
      _currency = currency;
      _loading = false;
    });
  }

  Future<void> _sort(TransactionRecord txn) async {
    final amount = NumberFormat('#,##0.00').format(txn.amount ?? 0);
    final choice = await showCategoryPicker(
      context,
      title: '$_currency$amount',
      subtitle: txn.counterpartyKey ?? txn.narration,
      categories: _categories,
      tracked: _tracked,
      onCreate: _createCategory,
    );
    if (choice == null) return;

    if (mounted) setState(() => _savingIds.add(txn.smsId));
    try {
    if (choice.notSpending) {
      await _repo.tagCounterparty(
        key: txn.counterpartyKey ?? '',
        disposition: Disposition.notSpending,
      );
    } else {
      final category = _categories.firstWhere((c) => c.id == choice.categoryId,
          orElse: () => const Category(id: '', name: ''));
      if (category.id.isEmpty) return;

      if (!_tracked.contains(category.name)) {
        // Backing out of the budget sheet cancels the whole action. Labelling
        // into a category the user never finished setting up would take this
        // transaction off the list and file the money somewhere with nothing
        // on screen to show it.
        final started = await _startTracking(category);
        if (!started) return;
      }

      await _repo.labelTransaction(
        smsId: txn.smsId,
        categoryId: category.id,
        categoryName: category.name,
        counterpartyKey: txn.counterpartyKey,
      );
    }
    } catch (e) {
      // ignore: avoid_print
      print('PENDING: filing failed for ${txn.smsId}: $e');
    } finally {
      if (mounted) setState(() => _savingIds.remove(txn.smsId));
    }
    await _load();
  }

  /// Asks for a monthly budget before a category starts being tracked.
  ///
  /// Required, not optional: a category with no budget cannot be measured
  /// against anything, and the details screen shows it as unset.
  Future<bool> _startTracking(Category category) async {
    final setup = await showCategorySetupSheet(
      context,
      currency: _currency,
      fixedName: category.name,
    );
    if (setup == null) return false;
    await _repo.startTracking(
      name: category.name,
      budget: setup.budget,
      image: category.image ?? '',
    );
    if (mounted) setState(() => _tracked.add(category.name));
    return true;
  }

  Future<Category?> _createCategory() async {
    final setup = await showCategorySetupSheet(context, currency: _currency);
    if (setup == null) return null;

    final category = await _repo.startTracking(
      name: setup.name,
      budget: setup.budget,
    );
    if (mounted) {
      setState(() {
        if (!_categories.any((c) => c.id == category.id)) {
          _categories = [..._categories, category]
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        }
        _tracked.add(category.name);
      });
    }
    return category;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded && (_loading || _pending.isEmpty)) {
      return const SizedBox.shrink();
    }

    final body = _loading
        ? const Center(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator()))
        : _pending.isEmpty
            ? _empty()
            : ListView.builder(
                shrinkWrap: widget.embedded,
                physics:
                    widget.embedded ? const NeverScrollableScrollPhysics() : null,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                itemCount: _pending.length,
                itemBuilder: (_, i) => _card(_pending[i]),
              );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('Needs sorting',
            style: TextStyle(
                color: Colors.black, fontSize: 17, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_pending.isNotEmpty) _intro(),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _intro() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "These didn't match anyone you've tagged. "
            'Tell the app what they were and it will remember.',
            style: TextStyle(
                fontSize: 13, height: 1.4, color: Colors.grey.shade600),
          ),
        ),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: brandBlue.withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.check_rounded,
                    color: brandBlue, size: 30),
              ),
              const SizedBox(height: 18),
              Text('Everything is sorted',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800)),
              const SizedBox(height: 6),
              Text('New transactions will show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );

  Widget _card(TransactionRecord txn) {
    final saving = _savingIds.contains(txn.smsId);
    final amount = NumberFormat('#,##0.00').format(txn.amount ?? 0);
    final when = txn.occurredAt == null
        ? ''
        : DateFormat('d MMM, h:mm a').format(txn.occurredAt!);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _sort(txn),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: saving
                      ? brandBlue.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.12),
                ),
                child: saving
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: brandBlue),
                      )
                    : const Icon(Icons.help_outline,
                        size: 20, color: Colors.orange),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_currency$amount',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(
                      txn.counterpartyKey ?? txn.narration,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                    // On its own line: sharing one with the name pushed the
                    // date off the end of a narrow screen.
                    if (when.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        when,
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade400),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: brandBlue.withValues(alpha: saving ? 0.06 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(saving ? 'Saving' : 'Sort',
                    style: TextStyle(
                        color: brandBlue.withValues(alpha: saving ? 0.6 : 1),
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
