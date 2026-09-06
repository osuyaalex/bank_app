/// Sorting a month's spending, one question at a time.
///
/// Replaces the list this screen used to be. That list showed up to
/// twenty-two counterparties at once under a guide panel, an intro, a budget
/// banner and a bulk bar -- five propositions before the first thing a user
/// could act on -- and its rows said "7 transactions" without ever saying
/// seven transactions of how much. It also could not be left: no back button,
/// the system gesture blocked, and both exits marking the screen permanently
/// dismissed. The only reversible way out was to kill the app, which is what
/// people did.
///
/// What that screen was good at is kept. Answering one counterparty still
/// teaches the matcher something that settles others, and accepting the
/// budgets drawn from history still files everything they cover. Both used to
/// happen silently in the background; here each one is a card that says what
/// it just did. The list itself survives as the last step, doing the job it
/// was always good at -- checking twenty answers at a glance -- rather than
/// the job it was bad at, which was collecting them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/budget_suggestion.dart';
import '../data/category_catalogue.dart';
import '../data/migration_plan.dart';
import '../data/models.dart';
import '../data/sms_inbox.dart';
import '../data/spend_repository.dart';
import '../parsing/bank_alert.dart';
import '../parsing/category_matcher.dart';
import 'batch_tag_page.dart';
import 'sort_flow.dart';
import 'widget/budget_suggestion_sheet.dart';
import 'widget/bulk_sort_sheet.dart';
import 'widget/category_picker.dart';
import 'widget/category_setup_sheet.dart';
import 'widget/unreadable_sms_view.dart';

const _brand = brandBlue;
const _ink = Color(0xff1C1939);

class SortFlowPage extends StatefulWidget {
  const SortFlowPage({super.key, this.repo, this.limit = 20});

  final SpendRepository? repo;
  final int limit;

  @override
  State<SortFlowPage> createState() => _SortFlowPageState();
}

class _SortFlowPageState extends State<SortFlowPage> {
  late final SpendRepository _repo = widget.repo ?? SpendRepository();

  List<Category> _categories = [];
  Set<String> _tracked = {};
  String _currency = '';
  List<CatalogueEntry> _suggestions = [];

  List<CounterpartyEntry> _rows = [];
  final Map<String, CategoryChoice> _choices = {};
  final Map<String, CategoryGuess> _guesses = {};

  String? _ownerName;
  bool _smsGranted = true;
  ({int total, int parsed})? _readability;
  List<BudgetSuggestion> _budgetHints = [];

  /// True once the budget offer has been answered either way. Declining is an
  /// answer; re-offering it is what turned the old banner into furniture.
  bool _budgetsSettled = false;

  /// What the last answer settled on its own, waiting to be shown.
  CascadeStep? _cascade;

  /// A counterparty to show instead of the next unanswered one, so the back
  /// arrow can return to a question already answered.
  CounterpartyEntry? _revisiting;

  /// Questions passed over. They stay unanswered and reappear in the review
  /// list; this only stops the flow putting the same one back immediately.
  final Set<String> _skipped = {};

  /// Questions already put to the user, most recent last. Only ever grows
  /// within a session; it is a trail to walk back, not a record of work.
  final List<String> _asked = [];

  /// True when the user has left the cards for the list. One-way within a
  /// visit: having chosen to see everything, being dropped back into cards
  /// would be a screen taking a decision away.
  bool _reviewing = false;

  bool _loading = true;
  bool _busy = false;

  static final _money = NumberFormat('#,###');

  /// Nothing to sort and nothing tracked. The old screen doubles as the
  /// category catalogue for that case, and as the apology for having nothing
  /// to show; both are complete and tested, and neither is a flow.
  bool get _handOverToList => _rows.isEmpty;

  Set<String> get _answered => _choices.keys.toSet();

  @override
  void initState() {
    super.initState();
    _load();
  }

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------

  Future<void> _load() async {
    try {
      await _loadInner();
    } catch (e, st) {
      // Unguarded, a throw here leaves the screen on its spinner with nothing
      // logged, which is indistinguishable from having no data.
      // ignore: avoid_print
      print('SORT: load failed: $e');
      // ignore: avoid_print
      print(st.toString().split('\n').take(3).join(' | '));
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadInner() async {
    // A brand-new user has no month document at all. Without this the
    // currency reads empty and every later write lands somewhere nothing else
    // can find.
    await _repo.ensureMonthInitialised();

    final categories = await _repo.pickerCategories();
    final tracked = await _repo.trackedCategoryNames();
    final currency = await _repo.currencySymbol();
    final map = await _repo.loadCounterparties();
    final catalogue = await CategoryCatalogue.load();
    final smsGranted = await _readSmsPermission();
    final readability = await SmsInbox.readability();
    final ownerName = await _repo.ownerName();
    final budgetHints = await _repo.budgetSuggestionsWorthShowing();

    // Self-transfers the migration proposed arrive already answered: the user
    // is confirming a suggestion, not deciding anything.
    final proposed =
        map.values
            .where((e) => e.disposition == Disposition.notSpending)
            .toList()
          ..sort((a, b) => b.totalDebited.compareTo(a.totalDebited));
    for (final e in proposed) {
      _choices[e.key] = const CategoryChoice.notSpending();
    }

    if (!mounted) return;
    setState(() {
      _categories = categories.where((c) => c.active).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _tracked = tracked;
      _currency = currency;
      _suggestions = CategoryCatalogue.unseen(
        catalogue,
        categories.map((c) => c.name),
      );
      _smsGranted = smsGranted;
      _readability = readability;
      _ownerName = ownerName;
      _budgetHints = budgetHints;
      _rows = [
        ...proposed,
        ...batchTagCandidates(
          map,
          limit: widget.limit,
          trackedCategories: tracked,
        ),
      ];
      _loading = false;
    });

    unawaited(_autoAssignQuietly());
    unawaited(_refreshBudgetHints());
  }

  Future<bool> _readSmsPermission() async {
    try {
      return await Permission.sms.isGranted;
    } catch (_) {
      // Assume granted rather than accusing the user of withholding access
      // because a platform call failed.
      return true;
    }
  }

  Future<void> _refreshBudgetHints() async {
    try {
      if (await _repo.refreshBudgetSuggestions() == 0) return;
      final hints = await _repo.budgetSuggestionsWorthShowing();
      if (!mounted) return;
      setState(() => _budgetHints = hints);
    } catch (_) {
      // A suggestion is a convenience. Failing to produce one must never take
      // the screen down with it.
    }
  }

  // -------------------------------------------------------------------------
  // Filing
  // -------------------------------------------------------------------------

  /// Files everything the matcher can place, without announcing it.
  ///
  /// Used on load, where there is no answer to attribute the work to. A
  /// cascade card claims credit for the answer that caused it, and the app
  /// opening is not an answer.
  Future<void> _autoAssignQuietly() => _autoAssign();

  Future<int> _autoAssign() async {
    final applied = <String, CategoryChoice>{};

    for (final row in _rows) {
      if (_choices.containsKey(row.key)) continue;

      // Their own account. Moving money between your own accounts is not
      // spending, and filing it anywhere counts it twice.
      if (looksLikeOwnAccount(row.key, _ownerName)) {
        applied[row.key] = const CategoryChoice.notSpending();
        continue;
      }

      final guess = guessCategory(
        row.key,
        _tracked,
        ownerName: _ownerName,
        twoWayMoney: row.isTwoWay,
        mostlyRoundAmounts: row.mostlyRound,
      );
      if (guess == null) continue;
      _guesses[row.key] = guess;
      if (guess.categoryName.isEmpty) continue; // a suggestion, not a filing

      final category = _categories.firstWhere(
        (c) => c.name.toLowerCase() == guess.categoryName.toLowerCase(),
        orElse: () => const Category(id: '', name: ''),
      );
      if (category.id.isEmpty) continue;
      applied[row.key] = CategoryChoice.category(category.id);
    }

    if (applied.isEmpty || !mounted) return 0;
    setState(() => _choices.addAll(applied));

    var filed = 0;
    for (final entry in applied.entries) {
      try {
        await _repo.tagCounterparty(
          key: entry.key,
          disposition: entry.value.notSpending
              ? Disposition.notSpending
              : Disposition.tracked,
          categoryId: entry.value.categoryId,
        );
        filed++;
      } catch (err) {
        // ignore: avoid_print
        print('SORT: auto-assign failed for ${entry.key}: $err');
        if (mounted) setState(() => _choices.remove(entry.key));
      }
    }
    if (mounted) setState(() {});
    return filed;
  }

  /// Records one answer, then reports whatever it settled on its own.
  Future<void> _answer(CounterpartyEntry e, CategoryChoice choice) async {
    final before = _answered;
    setState(() {
      _choices[e.key] = choice;
      _busy = true;
    });

    try {
      // Written immediately rather than held until the end. On a phone that
      // kills backgrounded apps, holding twenty answers in memory means
      // losing twenty.
      await _repo.tagCounterparty(
        key: e.key,
        disposition: choice.notSpending
            ? Disposition.notSpending
            : Disposition.tracked,
        categoryId: choice.categoryId,
      );
    } catch (err) {
      // ignore: avoid_print
      print('SORT: tag failed for ${e.key}: $err');
      if (!mounted) return;
      setState(() {
        _choices.remove(e.key);
        _busy = false;
      });
      _say('Could not save that. Check your connection.');
      return;
    }

    await _autoAssign();
    if (!mounted) return;

    final covered = cascadedBy(
      trigger: e.key,
      before: before,
      after: _answered,
      rows: _rows,
    );
    setState(() {
      _busy = false;
      _revisiting = null;
      if (!_asked.contains(e.key)) _asked.add(e.key);
      _cascade = covered.isEmpty
          ? null
          : CascadeStep(
              trigger: e.key,
              categoryName: _nameOf(choice),
              covered: covered,
            );
    });
  }

  String _nameOf(CategoryChoice choice) => choice.notSpending
      ? 'not spending'
      : _categories
            .firstWhere(
              (c) => c.id == choice.categoryId,
              orElse: () => const Category(id: '', name: 'a budget'),
            )
            .name;

  // -------------------------------------------------------------------------
  // The three ways an answer can be given
  // -------------------------------------------------------------------------

  /// The picker, for when none of the offered answers fit.
  Future<void> _openPicker(CounterpartyEntry e) async {
    final chosen = await showCategoryPicker(
      context,
      title: e.key,
      subtitle: _spendLine(e),
      categories: _categories,
      tracked: _tracked,
      current: _choices[e.key],
      onCreate: _createCategory,
      suggestions: _suggestions,
      onAdopt: _adopt,
      ghostOptions: _guesses[e.key]?.suggestedOptions ?? const [],
      ghostReason: _guesses[e.key]?.reason,
      onAcceptGhost: (name) => _startNamed(name),
    );
    if (chosen == null || !mounted) return;

    // Tagging into a category that is not tracked this month means the money
    // lands nowhere the user can see it, which is the exact problem this
    // screen exists to solve. So say so, and offer the fix.
    if (!chosen.notSpending && chosen.categoryId != null) {
      final category = _categories.firstWhere(
        (c) => c.id == chosen.categoryId,
        orElse: () => const Category(id: '', name: ''),
      );
      if (category.name.isNotEmpty && !_tracked.contains(category.name)) {
        final started = await _startTracking(category);
        if (!started) return;
      }
    }
    await _answer(e, chosen);
  }

  /// Creates the category the app proposed and files this row into it.
  ///
  /// One tap and a number, instead of: open the picker, find "Add more", type
  /// the name the app already knew, then set the budget.
  Future<void> _acceptGhost(CounterpartyEntry e, String name) async {
    final created = await _startNamed(name);
    if (created == null || !mounted) return;
    await _answer(e, CategoryChoice.category(created.id));
  }

  Future<Category?> _startNamed(String name) async {
    final setup = await showCategorySetupSheet(
      context,
      currency: _currency,
      fixedName: name,
      history: await _repo.historyForCategory(name),
    );
    if (setup == null) return null;
    final created = await _repo.startTracking(name: name, budget: setup.budget);
    if (!mounted) return created;
    setState(() {
      if (!_categories.any((c) => c.id == created.id)) {
        _categories = [
          ..._categories,
          created,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
      _tracked.add(created.name);
    });
    return created;
  }

  Future<Category?> _adopt(CatalogueEntry entry) async {
    final setup = await showCategorySetupSheet(
      context,
      currency: _currency,
      fixedName: entry.name,
      history: await _repo.historyForCategory(entry.name),
    );
    if (setup == null) return null;
    final created = await _repo.startTracking(
      name: entry.name,
      budget: setup.budget,
      image: entry.image,
    );
    if (!mounted) return created;
    setState(() {
      if (!_categories.any((c) => c.id == created.id)) {
        _categories = [
          ..._categories,
          created,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
      _tracked.add(created.name);
      _suggestions = _suggestions.where((s) => s.name != entry.name).toList();
    });
    return created;
  }

  Future<Category?> _createCategory() async {
    final setup = await showCategorySetupSheet(context, currency: _currency);
    if (setup == null) return null;
    final created = await _repo.startTracking(
      name: setup.name,
      budget: setup.budget,
    );
    if (!mounted) return created;
    setState(() {
      if (!_categories.any((c) => c.id == created.id)) {
        _categories = [
          ..._categories,
          created,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
      _tracked.add(created.name);
    });
    return created;
  }

  /// Asks for a monthly budget before a category starts being tracked.
  ///
  /// Required, not optional: a category with no budget cannot be measured
  /// against anything. Backing out cancels the tag rather than pointing a
  /// counterparty at a category with nothing to measure it by.
  Future<bool> _startTracking(Category category) async {
    final setup = await showCategorySetupSheet(
      context,
      currency: _currency,
      fixedName: category.name,
      history: await _repo.historyForCategory(category.name),
    );
    if (setup == null) return false;
    await _repo.startTracking(name: category.name, budget: setup.budget);
    if (mounted) setState(() => _tracked.add(category.name));
    return true;
  }

  // -------------------------------------------------------------------------
  // Budgets from history -- the first card, and the biggest one
  // -------------------------------------------------------------------------

  Future<void> _takeBudgets() async {
    final current = await _repo.trackedItemsWithBudgets();
    if (!mounted) return;

    final chosen = await showBudgetSuggestionSheet(
      context,
      suggestions: _budgetHints,
      currentBudgets: {
        for (final e in current.entries)
          e.key:
              double.tryParse(e.value.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0,
      },
      currency: _currency,
    );
    // Backing out of the sheet is not the same as declining the offer: the
    // card stays, so a mis-tap costs nothing.
    if (chosen == null || chosen.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final before = _answered;
    try {
      for (final s in chosen) {
        await _repo.applyBudgetSuggestion(s);
      }

      // The categories now exist and are tracked, so every counterparty the
      // matcher would file into them can be filed into them. This is the
      // whole point of asking about budgets first.
      final categories = await _repo.pickerCategories();
      final tracked = await _repo.trackedCategoryNames();
      if (!mounted) return;
      setState(() {
        _categories = categories.where((c) => c.active).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _tracked = tracked;
        _guesses.removeWhere((k, _) => !_choices.containsKey(k));
      });

      await _autoAssign();
      final left = await _repo.budgetSuggestionsWorthShowing();
      if (!mounted) return;

      final covered = cascadedBy(
        trigger: '',
        before: before,
        after: _answered,
        rows: _rows,
      );
      setState(() {
        _budgetHints = left;
        _budgetsSettled = true;
        _busy = false;
        _cascade = covered.isEmpty
            ? null
            : CascadeStep(
                trigger: '',
                categoryName: chosen.length == 1
                    ? chosen.first.categoryName
                    : 'your budgets',
                covered: covered,
              );
      });
    } catch (e) {
      // ignore: avoid_print
      print('SORT: applying budgets failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _budgetsSettled = true;
      });
      _say('Could not set those budgets. Check your connection.');
    }
  }

  // -------------------------------------------------------------------------
  // Leaving
  // -------------------------------------------------------------------------

  Future<void> _finish() async {
    setState(() => _busy = true);
    final settled = _choices.length;
    await _repo.markBatchTagDismissed();
    if (!mounted) return;
    _leave();
    _say(
      settled == 0
          ? 'Saved. New transactions will sort themselves out.'
          : 'Saved. $settled sorted.',
    );
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/deeplink/summary');
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _bulkAssign() async {
    final rows = _rows.where((r) => !_choices.containsKey(r.key)).toList();
    if (rows.isEmpty) return;

    final assigned = await showBulkSortSheet(
      context,
      rows: [
        for (final r in rows)
          BulkSortRow(id: r.key, title: r.key, subtitle: _spendLine(r)),
      ],
      categories: _categories.where((c) => _tracked.contains(c.name)).toList(),
    );
    if (assigned == null || assigned.isEmpty || !mounted) return;

    setState(() => _busy = true);
    for (final entry in assigned.entries) {
      try {
        await _repo.tagCounterparty(
          key: entry.key,
          disposition: Disposition.tracked,
          categoryId: entry.value,
        );
        if (mounted) {
          setState(
            () => _choices[entry.key] = CategoryChoice.category(entry.value),
          );
        }
      } catch (err) {
        // ignore: avoid_print
        print('SORT: bulk tag failed for ${entry.key}: $err');
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _say('${assigned.length} sorted.');
  }

  // -------------------------------------------------------------------------
  // Words
  // -------------------------------------------------------------------------

  /// What the user has paid this counterparty, or the count when the amount
  /// is not known.
  ///
  /// Entries written before spending was recorded per name carry a total of
  /// zero. Rendering that as "₦0" would be a figure the app cannot
  /// stand behind, so those fall back to what the old screen said.
  String _spendLine(CounterpartyEntry e) {
    final n = e.txCount;
    final times = '$n payment${n == 1 ? '' : 's'}';
    if (e.totalDebited <= 0) return times;
    return '$_currency${_money.format(e.totalDebited.round())}  ·  $times';
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final r = _readability;
    final nothingReadable = r != null && r.parsed == 0 && _rows.isEmpty;
    if (!_smsGranted || nothingReadable) {
      return UnreadableSmsView(
        permissionGranted: _smsGranted,
        messagesSeen: r?.total ?? 0,
        onRetry: () async {
          if (!mounted) return;
          setState(() => _loading = true);
          await _load();
        },
      );
    }

    // Nothing to sort. Setting up from the catalogue and apologising for an
    // empty inbox are both jobs the old screen already does completely.
    if (_handOverToList) return const BatchTagPage();

    final progress = SortProgress.of(_rows, _answered);
    final step = _reviewing
        ? const ReviewStep()
        : _revisiting != null
        ? AskStep(_revisiting!)
        : nextStep(
            rows: _rows,
            answered: _answered,
            budgetHints: _budgetHints,
            budgetsSettled: _budgetsSettled,
            skipped: _skipped,
            cascade: _cascade,
          );

    return PopScope(
      // The system gesture stays blocked -- this is offered once, and leaving
      // by accident means never being offered it again -- but every card
      // carries a way back and a way out, which is what was actually missing.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: _appBar(step, progress),
        body: SafeArea(
          child: switch (step) {
            SetBudgetsStep(suggestions: final s) => _budgetsCard(s),
            CascadeStep() => _cascadeCard(step),
            AskStep(entry: final e) => _askCard(e, progress),
            ReviewStep() => _reviewList(progress),
          },
        ),
        bottomNavigationBar: _bottomBar(step, progress),
      ),
    );
  }

  PreferredSizeWidget _appBar(SortStep step, SortProgress p) {
    final canGoBack = !_reviewing && step is AskStep && _asked.isNotEmpty;
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      leading: canGoBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.black54),
              tooltip: 'Previous',
              onPressed: _busy ? null : _goBack,
            )
          : null,
      title: Text(
        _reviewing ? 'Your answers' : 'Sort your spending',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        if (!_reviewing)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _reviewing = true),
            style: TextButton.styleFrom(foregroundColor: _brand),
            child: const Text(
              'See all',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: LinearProgressIndicator(
          value: p.total == 0 ? 1 : p.answered / p.total,
          minHeight: 3,
          backgroundColor: Colors.grey.shade200,
          valueColor: const AlwaysStoppedAnimation(_brand),
        ),
      ),
    );
  }

  /// Steps back to the last question asked.
  ///
  /// The answer is already saved, so this is a chance to change it rather
  /// than an undo. Nothing is rolled back on the way in -- a user who backs
  /// up and then leaves keeps the answer they gave.
  void _goBack() {
    if (_asked.isEmpty) return;
    final key = _asked.removeLast();
    final entry = _rows.firstWhere(
      (r) => r.key == key,
      orElse: () => _rows.first,
    );
    setState(() {
      _cascade = null;
      _revisiting = entry;
    });
  }

  // -------------------------------------------------------------------------
  // Card zero: budgets from history
  // -------------------------------------------------------------------------

  Widget _budgetsCard(List<BudgetSuggestion> hints) {
    final read = _readability?.total ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      children: [
        Text(
          read > 0
              ? 'I read ${_money.format(read)} of your bank messages.'
              : 'I read your bank messages.',
          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),
        const Text(
          'Here is where your money actually goes.',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 22),
        for (final h in hints.take(5)) _hintRow(h),
        const SizedBox(height: 18),
        Text(
          'Set these as your budgets and everything they cover gets filed at '
          'once. You can change any of them.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _hintRow(BudgetSuggestion h) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.categoryName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!h.isTracked) ...[
                  const SizedBox(height: 3),
                  Text(
                    'new',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            'about $_currency${_money.format(h.amount.round())} a month',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: _brand,
            ),
          ),
        ],
      ),
    ),
  );

  // -------------------------------------------------------------------------
  // The question
  // -------------------------------------------------------------------------

  Widget _askCard(CounterpartyEntry e, SortProgress p) {
    final guess = _guesses[e.key];
    final ghosts = guess?.suggestedOptions ?? const <String>[];
    final suggested =
        guess != null &&
            guess.categoryName.isNotEmpty &&
            _tracked.contains(guess.categoryName)
        ? guess.categoryName
        : null;
    // A short list, deliberately. The picker is one tap away and holds every
    // category; putting ten options on the card turns one question back into
    // the wall of choices this screen was built to get rid of.
    final others = _categories
        .where((c) => _tracked.contains(c.name) && c.name != suggested)
        .take(suggested == null && ghosts.isEmpty ? 5 : 3)
        .toList();
    final answered = _choices.containsKey(e.key);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      children: [
        Text(
          'You have paid',
          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 7),
        Text(
          e.key,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: _ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 9),
        // The figure, which is the fact the old list withheld. "7
        // transactions" could be airtime or it could be rent, and nobody can
        // answer the question without knowing which.
        Text(
          e.totalDebited > 0
              ? '$_currency${_money.format(e.totalDebited.round())}'
              : '${e.txCount} payment${e.txCount == 1 ? '' : 's'}',
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: _brand,
          ),
        ),
        if (e.totalDebited > 0) ...[
          const SizedBox(height: 4),
          Text(
            'across ${e.txCount} payment${e.txCount == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
        const SizedBox(height: 26),
        Text(
          'Which budget does this belong to?',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade900,
          ),
        ),
        if (guess?.reason != null) ...[
          const SizedBox(height: 6),
          Text(
            guess!.reason,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (suggested != null)
          _option(
            label: suggested,
            hint: 'what the app worked out',
            emphasised: true,
            onTap: () => _answerNamed(e, suggested),
          ),
        // Categories the app would create for this, where nothing tracked
        // fits. A transfer to a person could be a gift, a loan or lunch, and
        // the user often does not know either -- so all of them are offered
        // rather than one confident wrong answer.
        for (final g in ghosts)
          _option(
            label: g,
            hint: 'new budget',
            leading: Icons.add_rounded,
            onTap: () => _acceptGhost(e, g),
          ),
        for (final c in others)
          _option(label: c.name, onTap: () => _answerNamed(e, c.name)),
        _option(
          label: 'Something else…',
          muted: true,
          onTap: () => _openPicker(e),
        ),
        _option(
          label: 'Not spending — my own account',
          hint: 'money moved between your own accounts',
          muted: true,
          onTap: () => _answer(e, const CategoryChoice.notSpending()),
        ),
        if (answered) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 15,
                color: Color(0xff2E7D32),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Already filed under ${_nameOf(_choices[e.key]!)}. '
                  'Choosing again changes it.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _answerNamed(CounterpartyEntry e, String name) async {
    final category = _categories.firstWhere(
      (c) => c.name.toLowerCase() == name.toLowerCase(),
      orElse: () => const Category(id: '', name: ''),
    );
    if (category.id.isEmpty) return;
    await _answer(e, CategoryChoice.category(category.id));
  }

  Widget _option({
    required String label,
    required VoidCallback onTap,
    String? hint,
    IconData? leading,
    bool emphasised = false,
    bool muted = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: emphasised ? _brand.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: emphasised
                  ? _brand.withValues(alpha: 0.55)
                  : Colors.grey.shade200,
              width: emphasised ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                Icon(leading, size: 18, color: _brand),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: emphasised
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: muted ? Colors.grey.shade700 : _ink,
                      ),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: Colors.grey.shade300,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // -------------------------------------------------------------------------
  // What that answer settled
  // -------------------------------------------------------------------------

  Widget _cascadeCard(CascadeStep step) {
    final n = step.covered.length;
    final money = step.covered.fold(0.0, (s, e) => s + e.totalDebited);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 24),
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 22, color: _brand),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                step.trigger.isEmpty
                    ? 'That set your budgets.'
                    : '✓  ${step.categoryName}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          n == 1
              ? 'One more payment was filed on its own.'
              : '$n more were filed on their own.',
          style: TextStyle(
            fontSize: 14.5,
            height: 1.4,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 18),
        for (final e in step.covered.take(6)) _coveredRow(e),
        if (n > 6) ...[
          const SizedBox(height: 4),
          Text(
            'and ${n - 6} more',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
          ),
        ],
        const SizedBox(height: 18),
        if (money > 0)
          Text(
            'That is $_currency${_money.format(money.round())} sorted in one '
            'answer.',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: _brand,
            ),
          ),
      ],
    );
  }

  Widget _coveredRow(CounterpartyEntry e) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        const Icon(Icons.check_rounded, size: 16, color: Color(0xff2E7D32)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            e.key,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        if (e.totalDebited > 0)
          Text(
            '$_currency${_money.format(e.totalDebited.round())}',
            style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
          ),
      ],
    ),
  );

  // -------------------------------------------------------------------------
  // The list, at the end
  // -------------------------------------------------------------------------

  Widget _reviewList(SortProgress p) {
    final unanswered = p.remaining;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      itemCount: _rows.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unanswered == 0
                      ? 'All ${_rows.length} sorted. Check anything that looks '
                            'wrong.'
                      : '${p.answered} of ${_rows.length} sorted. '
                            'Tap any to change it.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (unanswered >= 3) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _busy ? null : _bulkAssign,
                    icon: const Icon(
                      Icons.playlist_add_check_rounded,
                      size: 18,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: _brand,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    label: Text(
                      'Answer the remaining $unanswered together',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        return _reviewRow(_rows[i - 1]);
      },
    );
  }

  Widget _reviewRow(CounterpartyEntry e) {
    final choice = _choices[e.key];
    final answered = choice != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: _busy ? null : () => _openPicker(e),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: answered
                    ? _brand.withValues(alpha: 0.3)
                    : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  answered
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 19,
                  color: answered ? _brand : Colors.grey.shade300,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        answered
                            ? '${_nameOf(choice)}  ·  ${_spendLine(e)}'
                            : _spendLine(e),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: answered ? _brand : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.grey.shade300,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // The bar at the bottom, which is different for every card
  // -------------------------------------------------------------------------

  Widget _bottomBar(SortStep step, SortProgress p) {
    final (
      primary,
      onPrimary,
      secondary,
      onSecondary,
      caption,
    ) = switch (step) {
      SetBudgetsStep() => (
        'Use these',
        _takeBudgets,
        'Set my own',
        () => setState(() => _budgetsSettled = true),
        'One tap sets them all',
      ),
      CascadeStep() => (
        'Keep going',
        () => setState(() => _cascade = null),
        null,
        null,
        '${p.answered} of ${p.total} sorted',
      ),
      AskStep() => (
        null,
        null,
        'Skip this one',
        () => _skip(step),
        _askCaption(p),
      ),
      ReviewStep() => (
        'Done',
        _finish,
        p.remaining > 0 ? 'Back to questions' : null,
        p.remaining > 0 ? () => setState(() => _reviewing = false) : null,
        '${p.answered} of ${p.total} sorted',
      ),
    };

    // The honest early exit. Offered only once most of the money is settled
    // and enough is left that finishing is a real chore -- otherwise it is
    // either a lie or a nudge to abandon work nearly done.
    final offerExit = step is AskStep && p.worthOfferingAnExit;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (offerExit) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'That is ${(p.shareOfMoney * 100).round()}% of your '
                        'spending sorted. The rest can wait.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _busy ? null : _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: _brand,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text(
                        'Finish',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    caption,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                if (secondary != null)
                  TextButton(
                    onPressed: _busy ? null : onSecondary,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                    ),
                    child: Text(
                      secondary,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (primary != null) ...[
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: _busy ? null : onPrimary,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 17,
                            width: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            primary,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _askCaption(SortProgress p) => p.answered == 0
      ? 'Question 1 of ${p.total}'
      : '${p.answered} of ${p.total} sorted';

  /// Passes over a question without answering it.
  ///
  /// The row stays unanswered and turns up again in the review list, which is
  /// the difference between this and an answer: skipping costs nothing and
  /// commits to nothing.
  void _skip(AskStep step) {
    final key = step.entry.key;
    setState(() {
      if (!_asked.contains(key)) _asked.add(key);
      _skipped.add(key);
      _revisiting = null;
    });
  }
}
