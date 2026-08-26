import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/spend_repository.dart';
import '../data/migration_plan.dart';
import '../parsing/bank_alert.dart';
import '../parsing/category_matcher.dart';
import 'widget/bulk_sort_sheet.dart';
import 'widget/category_picker.dart';
import 'widget/category_setup_sheet.dart';
import 'widget/ghost_chip.dart';
import 'widget/screen_guide.dart';

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

  /// What the app worked out for each row, by counterparty.
  final Map<String, CategoryGuess> _guesses = {};

  Future<void> _load() async {
    final pending = await _repo.pendingTransactions();
    final categories = await _repo.pickerCategories();
    final tracked = await _repo.trackedCategoryNames();
    final currency = await _repo.currencySymbol();
    final owner = await _repo.ownerName();
    // The counterparty map carries the evidence a single transaction cannot:
    // whether money has ever come back from this person, and whether the
    // amounts are the round figures people send each other.
    final map = await _repo.loadCounterparties();

    if (!mounted) return;
    setState(() {
      _pending = pending;
      _categories = categories.where((c) => c.active).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _tracked = tracked;
      _currency = currency;
      _guesses.clear();
      for (final txn in pending) {
        final key = txn.counterpartyKey;
        if (key == null || key.isEmpty) continue;
        // Never suggest anything for the user's own account: a transfer
        // between their own accounts is not spending at all.
        if (looksLikeOwnAccount(key, owner)) continue;
        final entry = resolveKey(map, key);
        final g = guessCategory(
          key,
          tracked,
          ownerName: owner,
          twoWayMoney: entry?.isTwoWay ?? false,
          mostlyRoundAmounts: entry?.mostlyRound ?? false,
        );
        if (g != null) _guesses[key] = g;
      }
      _loading = false;
    });

    unawaited(_fileTheObviousOnes());
  }

  /// Files the transactions the app is sure about, without asking.
  ///
  /// A row it can place with certainty has no business sitting in a list
  /// called "needs sorting" -- the name is a request for help the app does
  /// not need. Only certain ones: anything it merely guessed at stays
  /// visible, where the user can see the guess and sweep it in bulk.
  Future<void> _fileTheObviousOnes() async {
    final sure = _pending.where((t) {
      final g = _guesses[t.counterpartyKey];
      return g != null && g.isCertain && g.categoryName.isNotEmpty;
    }).toList();
    if (sure.isEmpty) return;

    var filed = 0;
    for (final txn in sure) {
      final guess = _guesses[txn.counterpartyKey]!;
      final category = _categories.firstWhere(
        (c) => c.name.toLowerCase() == guess.categoryName.toLowerCase(),
        orElse: () => const Category(id: '', name: ''),
      );
      if (category.id.isEmpty) continue;
      try {
        await _repo.labelTransaction(
          smsId: txn.smsId,
          categoryId: category.id,
          categoryName: category.name,
          counterpartyKey: txn.counterpartyKey,
        );
        filed++;
      } catch (e) {
        // ignore: avoid_print
        print('PENDING: auto-file failed for ${txn.smsId}: $e');
      }
    }
    if (filed > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$filed sorted automatically.')));
      await _load();
    }
  }

  /// Transactions the app has nothing at all for.
  ///
  /// Narrow on purpose: a row carrying a suggested category is not unclear,
  /// it is one tap from done. Counting those made the bar warn about work the
  /// app had already done.
  List<TransactionRecord> get _unsure => _pending.where((t) {
        final g = _guesses[t.counterpartyKey];
        if (g == null) return true;
        if (g.categoryName.isNotEmpty) return false;
        return g.suggestedOptions.isEmpty;
      }).toList();

  /// Files every unsure transaction into one category at once.
  ///
  /// The alternative to guessing at each. Bare personal names carry no
  /// signal, and inventing a category for each is a chance to be wrong every
  /// time; this says the app cannot tell and turns many taps into one.
  Future<void> _bulkAssign() async {
    // Everything still waiting, not only what the app could not place. A
    // suggestion the user disagrees with is exactly what a bulk pass is for.
    final rows = _pending;
    if (rows.isEmpty || _categories.isEmpty) return;

    final money = NumberFormat('#,##0.00');
    final picks = await showBulkSortSheet(
      context,
      categories: _categories,
      rows: [
        for (final t in rows)
          BulkSortRow(
            id: t.smsId,
            title: t.counterpartyKey ?? t.narration,
            subtitle: '$_currency${money.format(t.amount ?? 0)}',
          ),
      ],
    );
    if (picks == null || picks.isEmpty || !mounted) return;

    setState(() => _savingIds.addAll(picks.keys));
    for (final txn in rows) {
      final categoryId = picks[txn.smsId];
      if (categoryId == null) continue;
      final category = _categories.firstWhere((c) => c.id == categoryId,
          orElse: () => const Category(id: '', name: ''));
      if (category.id.isEmpty) continue;
      try {
        await _repo.labelTransaction(
          smsId: txn.smsId,
          categoryId: category.id,
          categoryName: category.name,
          counterpartyKey: txn.counterpartyKey,
        );
      } catch (e) {
        // ignore: avoid_print
        print('PENDING: bulk assign failed for ${txn.smsId}: $e');
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${picks.length} sorted.')));
    }
    await _load();
  }

  Widget _bulkBar() {
    // Offered whenever there is enough to be worth it, not only when the app
    // is stuck.
    //
    // It used to appear only for rows with no suggestion at all. Narrowing
    // that count was right -- it had been warning about work already done --
    // but it also meant the bar stopped appearing at all once the matcher
    // started suggesting something for nearly everything, and the bulk sheet
    // became unreachable. The count and the shortcut are different questions.
    final unsure = _unsure.length;
    final n = _pending.length;
    if (n < 3) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.help_outline_rounded,
                size: 17, color: Colors.grey.shade500),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                unsure > 0
                    ? "$unsure still need a budget. Sort several at once?"
                    : 'Sort several at once, without opening each.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.35, color: Colors.grey.shade700),
              ),
            ),
            TextButton(
              onPressed: _bulkAssign,
              style: TextButton.styleFrom(
                foregroundColor: brandBlue,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('Choose',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  /// Files a transaction into a budget that already exists.
  Future<void> _acceptGuess(TransactionRecord txn, Category category) async {
    if (mounted) setState(() => _savingIds.add(txn.smsId));
    var also = 0;
    try {
      also = await _repo.labelTransaction(
        smsId: txn.smsId,
        categoryId: category.id,
        categoryName: category.name,
        counterpartyKey: txn.counterpartyKey,
      );
    } catch (e) {
      // ignore: avoid_print
      print('PENDING: accept failed for ${txn.smsId}: $e');
    } finally {
      if (mounted) setState(() => _savingIds.remove(txn.smsId));
    }
    // Said out loud. Rows vanishing from a list without explanation reads as
    // a bug, even when it is the thing the user just asked for.
    if (also > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$also other payment${also == 1 ? "" : "s"} to '
            '${txn.counterpartyKey} filed under ${category.name} too.'),
      ));
    }
    await _load();
  }

  /// Files a transaction into a category the app suggested but the user does
  /// not track yet, asking only for the budget.
  Future<void> _acceptSuggestion(TransactionRecord txn, String name) async {
    final setup = await showCategorySetupSheet(context,
        currency: _currency, fixedName: name);
    if (setup == null) return;

    if (mounted) setState(() => _savingIds.add(txn.smsId));
    try {
      final category =
          await _repo.startTracking(name: name, budget: setup.budget);
      await _repo.labelTransaction(
        smsId: txn.smsId,
        categoryId: category.id,
        categoryName: category.name,
        counterpartyKey: txn.counterpartyKey,
      );
    } catch (e) {
      // ignore: avoid_print
      print('PENDING: suggestion failed for ${txn.smsId}: $e');
    } finally {
      if (mounted) setState(() => _savingIds.remove(txn.smsId));
    }
    await _load();
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
      ghostOptions:
          _guesses[txn.counterpartyKey]?.suggestedOptions ?? const [],
      ghostReason: _guesses[txn.counterpartyKey]?.reason,
      onAcceptGhost: (name) async {
        final setup = await showCategorySetupSheet(context,
            currency: _currency, fixedName: name);
        if (setup == null) return null;
        final created =
            await _repo.startTracking(name: name, budget: setup.budget);
        if (mounted) {
          setState(() {
            if (!_categories.any((c) => c.id == created.id)) {
              _categories = [..._categories, created]
                ..sort((a, b) =>
                    a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            }
            _tracked.add(created.name);
          });
        }
        return created;
      },
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
        actions: const [
          GuideButton(
              id: _guideId,
              title: _guideTitle,
              steps: _guideSteps,
              footnote: _guideFootnote),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_pending.isNotEmpty) ...[
              const ScreenGuide(
                  id: _guideId,
                  title: _guideTitle,
                  steps: _guideSteps,
                  footnote: _guideFootnote),
              _intro(),
              _bulkBar(),
            ],
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  static const _guideId = 'needs_sorting';
  static const _guideTitle = 'Transactions waiting on you';
  static const _guideSteps = [
    GuideStep('Each row is a payment the app could not place on its own.'),
    GuideStep('Tap it and pick the budget it belongs to.'),
    GuideStep('The next payment to the same place is filed automatically, '
        'unless the name is a payment processor that covers many shops.'),
  ];
  static const _guideFootnote =
      'This list empties as you go. Nothing is counted against a budget until '
      'you say where it belongs.';

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
    final guess = _guesses[txn.counterpartyKey];
    final ghosts = (guess?.needsNewCategory ?? false)
        ? guess!.suggestedOptions
        : const <String>[];
    // A suggestion pointing at a budget the user already has.
    //
    // This was the gap: the card only offered something when the suggested
    // category did *not* exist. When it did -- the common case -- the row
    // showed nothing, and the whole screen looked as though the app had made
    // no attempt at all.
    final Category? suggested = (guess != null &&
            guess.categoryName.isNotEmpty)
        ? _categories.firstWhere(
            (c) => c.name.toLowerCase() == guess.categoryName.toLowerCase(),
            orElse: () => const Category(id: '', name: ''))
        : null;
    final hasSuggestion = suggested != null && suggested.id.isNotEmpty;
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
                    // A budget that already exists: one tap files it.
                    if (hasSuggestion && !saving) ...[
                      const SizedBox(height: 9),
                      GhostHint(text: guess!.reason),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          GestureDetector(
                            onTap: () => _acceptGuess(txn, suggested),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 6),
                              decoration: BoxDecoration(
                                color: brandBlue,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_rounded,
                                      size: 14, color: Colors.white),
                                  const SizedBox(width: 5),
                                  Text(suggested.name,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                          // The nearest alternatives, so disagreeing is also
                          // one tap rather than a trip through the picker.
                          for (final c in _categories
                              .where((c) => c.id != suggested.id)
                              .take(3))
                            GestureDetector(
                              onTap: () => _acceptGuess(txn, c),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(c.name,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey.shade700)),
                              ),
                            ),
                        ],
                      ),
                    ],
                    // A category the app would file this into if it existed.
                    // Offered on the row itself, so accepting it costs one tap
                    // and a number rather than a trip through the picker.
                    if (ghosts.isNotEmpty && !saving) ...[
                      const SizedBox(height: 9),
                      GhostHint(text: guess!.reason),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final g in ghosts)
                            GhostChip(
                              label: g,
                              dense: true,
                              onTap: () => _acceptSuggestion(txn, g),
                            ),
                        ],
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
