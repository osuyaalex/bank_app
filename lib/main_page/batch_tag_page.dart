import 'package:flutter/material.dart';

import '../data/migration_plan.dart';
import '../data/models.dart';
import '../data/spend_repository.dart';
import 'widget/category_picker.dart';

const _brand = brandBlue;

/// One-time onboarding after migration.
///
/// The counterparty map is seeded from the SMS already on the device, so
/// instead of starting empty and interrogating the user once per transaction,
/// this asks about the handful of names that account for most of their
/// spending. Tagging the top twenty covers roughly 40% of all transactions.
class BatchTagPage extends StatefulWidget {
  const BatchTagPage({super.key, this.repo, this.limit = 20});

  final SpendRepository? repo;
  final int limit;

  @override
  State<BatchTagPage> createState() => _BatchTagPageState();
}

class _BatchTagPageState extends State<BatchTagPage> {
  late final SpendRepository _repo = widget.repo ?? SpendRepository();

  List<Category> _categories = [];

  /// Names of categories being tracked this month. A tag pointing anywhere
  /// else is remembered, but its money will not show up until the category is
  /// actually being tracked -- so the user is told and offered the fix.
  Set<String> _tracked = {};

  List<CounterpartyEntry> _rows = [];
  final Map<String, CategoryChoice> _choices = {};

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final categories = await _repo.loadCategories();
    final tracked = await _repo.trackedCategoryNames();
    final map = await _repo.loadCounterparties();

    // Self-transfers the migration proposed come first and arrive already
    // ticked -- the user is confirming a suggestion, not answering a question.
    final proposed =
        map.values.where((e) => e.disposition == Disposition.notSpending).toList()
          ..sort((a, b) => b.txCount.compareTo(a.txCount));
    for (final e in proposed) {
      _choices[e.key] = const CategoryChoice.notSpending();
    }

    if (!mounted) return;
    setState(() {
      _categories = categories.where((c) => c.active).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _tracked = tracked;
      _rows = [...proposed, ...batchTagCandidates(map, limit: widget.limit)];
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // Answers were saved as they were made; this only closes the screen.
    final settled = _choices.length;
    await _repo.markBatchTagSeen();
    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(settled == 0
          ? 'Saved. New transactions will sort themselves out.'
          : 'Saved. $settled transactions sorted.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // No back button, and the system gesture is blocked: this is shown once,
    // and leaving it by accident means never being offered it again.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: const Text('Sort your spending',
              style: TextStyle(
                  color: Colors.black,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
        ),
        body: SafeArea(
          child: _rows.isEmpty
              ? _emptyState()
              : Column(
                  children: [
                    _intro(),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                        itemCount: _rows.length,
                        itemBuilder: (_, i) => _card(_rows[i]),
                      ),
                    ),
                  ],
                ),
        ),
        bottomNavigationBar: _actionBar(),
      ),
    );
  }

  Widget _intro() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'These are the people and places you pay most.',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade900),
            ),
            const SizedBox(height: 4),
            Text(
              'Tag each one and the app will file them automatically from now on.',
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: Colors.grey.shade600),
            ),
          ],
        ),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Nothing to sort yet. As transactions come in, '
            'the app will ask about them one at a time.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.5),
          ),
        ),
      );

  Widget _card(CounterpartyEntry e) {
    final choice = _choices[e.key];
    final label = choice == null
        ? null
        : choice.notSpending
            ? 'My own account'
            : _categories
                .firstWhere((c) => c.id == choice.categoryId,
                    orElse: () => const Category(id: '', name: '?'))
                .name;
    final answered = label != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: answered ? _brand.withValues(alpha: 0.45) : Colors.transparent,
        ),
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
        onTap: _saving ? null : () => _pick(e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: answered
                      ? _brand.withValues(alpha: 0.14)
                      : Colors.grey.shade100,
                ),
                child: Icon(
                  answered ? Icons.check_rounded : Icons.person_outline,
                  size: 20,
                  color: answered ? _brand : Colors.grey.shade500,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label ?? '${e.txCount} transactions  ·  Tap to choose',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: answered ? _brand : Colors.grey.shade500,
                        fontWeight:
                            answered ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade300),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(CounterpartyEntry e) async {
    final chosen = await showCategoryPicker(
      context,
      title: e.key,
      subtitle: '${e.txCount} transactions',
      categories: _categories,
      tracked: _tracked,
      current: _choices[e.key],
      onCreate: _createCategory,
    );
    if (chosen == null) return;

    // Tagging into a category that is not tracked this month means the money
    // lands nowhere the user can see it -- the exact problem this feature
    // exists to solve. So say so, and offer the fix.
    if (!chosen.notSpending && chosen.categoryId != null) {
      final category = _categories.firstWhere((c) => c.id == chosen.categoryId,
          orElse: () => const Category(id: '', name: ''));
      if (category.name.isNotEmpty && !_tracked.contains(category.name)) {
        final start = await _confirmStartTracking(category.name);
        if (start == true) {
          await _repo.startTracking(
              name: category.name, image: category.image ?? '');
          if (mounted) setState(() => _tracked.add(category.name));
        }
      }
    }

    // Written immediately rather than held until Done. On a phone that kills
    // backgrounded apps, holding twenty answers in memory means losing twenty.
    await _repo.tagCounterparty(
      key: e.key,
      disposition:
          chosen.notSpending ? Disposition.notSpending : Disposition.tracked,
      categoryId: chosen.categoryId,
    );

    if (mounted) setState(() => _choices[e.key] = chosen);
  }

  Future<bool?> _confirmStartTracking(String name) => showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text("You're not tracking $name"),
          content: Text(
            'This will be remembered, but it will not show up this month '
            'unless you track $name. Start tracking it now?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Not now')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Start tracking')),
          ],
        ),
      );

  Future<Category?> _createCategory() async {
    final nameField = TextEditingController();
    final budgetField = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameField,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name')),
            TextField(
                controller: budgetField,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Monthly budget (optional)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add')),
        ],
      ),
    );
    final name = nameField.text.trim();
    if (ok != true || name.isEmpty) return null;

    final category = await _repo.startTracking(
      name: name,
      budget: budgetField.text.trim().isEmpty ? '0' : budgetField.text.trim(),
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

  Widget _actionBar() {
    final done = _choices.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                done == 0
                    ? 'Nothing tagged yet'
                    : '$done of ${_rows.length} tagged',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () async {
                      await _repo.markBatchTagSeen();
                      if (context.mounted) Navigator.of(context).maybePop();
                    },
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              child: const Text('Skip'),
            ),
            const SizedBox(width: 6),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveBar() {
    final done = _choices.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              done == 0 ? 'Nothing tagged yet' : '$done of ${_rows.length} tagged',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          ElevatedButton(
            onPressed: _saving || done == 0 ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
