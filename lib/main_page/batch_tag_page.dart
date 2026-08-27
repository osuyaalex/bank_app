import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/category_catalogue.dart';
import '../data/migration_plan.dart';
import '../data/models.dart';
import '../data/budget_suggestion.dart';
import '../data/sms_inbox.dart';
import '../parsing/bank_alert.dart';
import '../parsing/category_matcher.dart';
import '../data/spend_repository.dart';
import 'widget/bulk_sort_sheet.dart';
import 'widget/budget_suggestion_sheet.dart';
import 'widget/category_picker.dart';
import 'widget/category_setup_sheet.dart';
import 'widget/ghost_chip.dart';
import 'widget/screen_guide.dart';
import 'widget/unreadable_sms_view.dart';

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
  String _currency = '';

  /// Curated categories the user has not got yet. This is what the deleted
  /// track-items screen offered; it is offered here instead, either in the
  /// picker or -- when there is nothing to tag -- as the whole screen.
  List<CatalogueEntry> _suggestions = [];

  List<CounterpartyEntry> _rows = [];
  final Map<String, CategoryChoice> _choices = {};

  /// Counterparties whose answer is still being written. Tagging settles the
  /// transactions waiting on it and rebuilds the month, which takes a few
  /// seconds -- long enough that silence reads as the tap not registering.
  final Set<String> _savingKeys = {};

  /// What the app worked out for each row before the user touched anything.
  ///
  /// Kept alongside [_choices] rather than folded into it, because the two
  /// mean different things: a guess is the app's, a choice is the user's, and
  /// a row has to be able to say which it is showing.
  final Map<String, CategoryGuess> _guesses = {};

  /// The account holder's name, for spotting relatives by surname.
  String? _ownerName;

  /// Whether the app can read the SMS inbox. Without it there is nothing to
  /// tag and no amount of waiting will change that, so the screen says so
  /// rather than letting the user assume they simply have no spending.
  bool _smsGranted = true;

  /// How much of the inbox could be understood. Null until checked.
  ({int total, int parsed})? _readability;

  /// Budgets the app worked out from the user's own history, for categories
  /// where the figure they set is missing or nowhere near what they spend.
  List<BudgetSuggestion> _budgetHints = [];


  /// Cleared once the user has answered the offer, either way. Re-offering a
  /// suggestion someone has just declined is nagging.
  bool _budgetHintsDismissed = false;

  bool _loading = true;
  bool _saving = false;

  /// True when this screen is standing in for the old track-items screen:
  /// no counterparties worth asking about and no categories yet. The rules
  /// differ -- there is nothing to skip, and leaving without a budget would
  /// drop the user onto an empty home screen.
  bool get _isSetup => _rows.isEmpty && _tracked.isEmpty;

  static const _guideId = 'batch_tag';
  static const _guideTitle = 'Sort your spending, once';
  static const _guideSteps = [
    GuideStep('These are the people and places you pay most often.'),
    GuideStep('Tap one and choose which budget it belongs to.'),
    GuideStep('Every future payment to them is filed there automatically.'),
  ];
  static const _guideFootnote =
      'You only see this once. Tap Done when you have had enough \u2014 anything '
      'left over can be sorted later from the summary.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _loadInner();
    } catch (e, st) {
      // Previously unguarded: a throw here left the screen on its spinner with
      // nothing logged, which is indistinguishable from "no data".
      print('BATCH: load failed: $e');
      print(st.toString().split('\n').take(3).join(' | '));
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadInner() async {
    // A brand-new user has no month document at all, and the screen that used
    // to create one is gone. Without this the currency reads empty and every
    // later write lands on a document nothing else can find.
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
      _currency = currency;
      _suggestions = CategoryCatalogue.unseen(
          catalogue, categories.map((c) => c.name));
      _smsGranted = smsGranted;
      _readability = readability;
      _ownerName = ownerName;
      _budgetHints = budgetHints;
      _rows = [
        ...proposed,
        ...batchTagCandidates(map,
            limit: widget.limit, trackedCategories: tracked),
      ];
      _loading = false;
    });

    // After the frame, so the list is on screen while this fills it in.
    unawaited(_autoAssign());
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

  Future<void> _requestSms() async {
    final status = await Permission.sms.request();
    if (status.isGranted) {
      // The migration stopped short without the inbox, so re-running it is
      // what actually produces something to tag.
      if (mounted) setState(() => _loading = true);
      await _load();
      return;
    }
    if (status.isPermanentlyDenied) await openAppSettings();
  }

  /// Files every row the app can place, before the user sees the screen.
  ///
  /// This is the point of the dictionary. A user who opens this to twenty
  /// untouched rows has the same chore they had before; a user who opens it to
  /// twenty already-filed rows only has to check the ones the app flagged.
  ///
  /// Writes happen in the background. The guesses are shown immediately --
  /// making the user watch twenty spinners resolve before they can read their
  /// own screen would be backwards.
  /// Re-runs the matcher after a category is created.
  ///
  /// Accepting `+ Family` on one row taught the app what Family is, but every
  /// other relative kept its stale guess and went on offering the same chip.
  /// Creating a category answers every row that was waiting on it, so all of
  /// them are re-evaluated rather than only the one that was tapped.
  Future<void> _reassignAfterNewCategory() => _autoAssign();

  Future<void> _autoAssign() async {
    final applied = <String, CategoryChoice>{};

    for (final row in _rows) {
      if (_choices.containsKey(row.key)) continue; // already answered

      // Their own account. Moving money between your own accounts is not
      // spending, and filing it anywhere -- Family, Others, a best guess --
      // counts it twice and inflates the month.
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

    if (applied.isEmpty || !mounted) return;
    setState(() => _choices.addAll(applied));

    for (final entry in applied.entries) {
      try {
        await _repo.tagCounterparty(
          key: entry.key,
          disposition: entry.value.notSpending
              ? Disposition.notSpending
              : Disposition.tracked,
          categoryId: entry.value.categoryId,
        );
      } catch (err) {
        // ignore: avoid_print
        print('BATCH: auto-assign failed for ${entry.key}: $err');
        if (mounted) setState(() => _choices.remove(entry.key));
      }
    }
  }

  /// Creates the category the app suggested and files this row into it.
  ///
  /// One tap and a number, instead of: open the picker, find "Add more", type
  /// the name the app already knew, then set the budget.
  Future<void> _acceptSuggestion(CounterpartyEntry row, String name) async {
    final setup =
        await showCategorySetupSheet(context,
            currency: _currency,
            fixedName: name,
            history: await _repo.historyForCategory(name));
    if (setup == null) return;

    final category =
        await _repo.startTracking(name: name, budget: setup.budget);
    if (!mounted) return;
    setState(() {
      if (!_categories.any((c) => c.id == category.id)) {
        _categories = [..._categories, category]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
      _tracked.add(category.name);
      _suggestions = _suggestions.where((s) => s.name != name).toList();
      _choices[row.key] = CategoryChoice.category(category.id);
      _guesses.remove(row.key);
      _savingKeys.add(row.key);
    });

    try {
      await _repo.tagCounterparty(
        key: row.key,
        disposition: Disposition.tracked,
        categoryId: category.id,
      );
    } finally {
      if (mounted) setState(() => _savingKeys.remove(row.key));
    }
    await _reassignAfterNewCategory();
  }

  /// Rows the app has nothing at all for.
  ///
  /// Deliberately narrow. It used to count every row it was less than certain
  /// about, which meant the bar announced "14 weren't clear" on a screen where
  /// all fourteen had been given a track -- a warning about work that was
  /// already done. A row with a track, or with a suggested one waiting to be
  /// accepted, is not unclear; only a row with neither is.
  List<CounterpartyEntry> get _unsureRows => _rows.where((r) {
        // Already answered, by the user or by the app.
        if (_choices.containsKey(r.key)) return false;
        final g = _guesses[r.key];
        // A recommendation is an answer too -- one the user need only accept.
        if (g != null && g.suggestedOptions.isNotEmpty) return false;
        return true;
      }).toList();

  /// Files every unsure row into one category at once.
  ///
  /// The alternative to guessing. Eighty counterparties that are bare
  /// personal names carry no signal, and inventing a category for each is
  /// eighty chances to be wrong; this says plainly that the app cannot tell
  /// and turns eighty taps into one.
  Future<void> _bulkAssign() async {
    // Everything not yet answered, not only what the app could not place.
    final rows =
        _rows.where((r) => !_choices.containsKey(r.key)).toList();
    if (rows.isEmpty || _categories.isEmpty) return;

    final picks = await showBulkSortSheet(
      context,
      categories: _categories,
      rows: [
        for (final r in rows)
          BulkSortRow(
            id: r.key,
            title: r.key,
            subtitle: '${r.txCount} transaction'
                '${r.txCount == 1 ? "" : "s"}',
          ),
      ],
    );
    if (picks == null || picks.isEmpty || !mounted) return;

    setState(() {
      picks.forEach((key, categoryId) {
        _choices[key] = CategoryChoice.category(categoryId);
        _guesses.remove(key);
        _savingKeys.add(key);
      });
    });

    for (final entry in picks.entries) {
      try {
        await _repo.tagCounterparty(
          key: entry.key,
          disposition: Disposition.tracked,
          categoryId: entry.value,
        );
      } catch (err) {
        // ignore: avoid_print
        print('BATCH: bulk assign failed for ${entry.key}: $err');
        if (mounted) setState(() => _choices.remove(entry.key));
      } finally {
        if (mounted) setState(() => _savingKeys.remove(entry.key));
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${picks.length} sorted.')));
    }
  }

  Widget _bulkBar() {
    // Offered whenever there is enough to be worth it, not only when the app
    // is stuck.
    //
    // It used to appear only for rows with no suggestion at all. Narrowing
    // that count was right -- it had been warning about work already done --
    // but it also meant the bar stopped appearing once the matcher started
    // suggesting something for nearly everything, and the bulk sheet became
    // unreachable. The count and the shortcut are different questions.
    final unsure = _unsureRows.length;
    final n = _rows.where((r) => !_choices.containsKey(r.key)).length;
    if (n < 3) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
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
              onPressed: _saving ? null : _bulkAssign,
              style: TextButton.styleFrom(
                foregroundColor: _brand,
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

  Future<void> _save() async {
    setState(() => _saving = true);
    // Answers were saved as they were made; this only closes the screen.
    final settled = _choices.length;
    final wasSetup = _isSetup;
    await _repo.markBatchTagDismissed();
    if (!mounted) return;
    _leave();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(wasSetup
          ? "You're all set. Spending will be filed as it comes in."
          : settled == 0
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

    // Nothing on this screen means anything without transactions. Rather than
    // an empty list the user has to interpret, say why it is empty.
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
          title: Text(_isSetup ? 'Set up your budget' : 'Sort your spending',
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
          actions: const [
            GuideButton(
                id: _guideId,
                title: _guideTitle,
                steps: _guideSteps,
                footnote: _guideFootnote),
          ],
        ),
        body: SafeArea(
          child: _rows.isEmpty
              ? Column(
                  children: [
                    if (!_smsGranted) _smsBanner(),
                    Expanded(child: _emptyState()),
                  ],
                )
              // The banner and the intro ride inside the list rather than
              // sitting in a fixed row above it. Stacked in a Column they
              // claimed height the list then could not give back, which
              // overflowed as soon as the screen was short -- landscape, or a
              // small phone with large system text.
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                  itemCount: _rows.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_smsGranted) _smsBanner(),
                          const ScreenGuide(
                              id: _guideId,
                              title: _guideTitle,
                              steps: _guideSteps,
                              footnote: _guideFootnote),
                          _intro(),
                          _budgetBanner(),
                          _bulkBar(),
                        ],
                      );
                    }
                    return _card(_rows[i - 1]);
                  },
                ),
        ),
        bottomNavigationBar: _actionBar(),
      ),
    );
  }

  /// Rebuilds the budget proposals from the inbox, then shows what changed.
  ///
  /// Runs behind the screen rather than in front of it: reading and parsing
  /// the whole inbox takes a moment, and none of it is worth making the user
  /// wait on when the list they came for is ready.
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

  /// Offers to fill in budgets from the months already on the phone.
  ///
  /// Sits here rather than on the setup screen because the setup screen runs
  /// first, before any SMS has been read -- at that point the app knows
  /// nothing about the user and has nothing to propose. By the time this
  /// screen appears the whole inbox has been through the parser.
  Widget _budgetBanner() {
    if (_budgetHints.isEmpty || _budgetHintsDismissed) {
      return const SizedBox.shrink();
    }
    final top = _budgetHints.first;
    final newOnes = _budgetHints.where((h) => !h.isTracked).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 14),
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      decoration: BoxDecoration(
        color: const Color(0xffF4F7FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brand.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 19, color: _brand),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _budgetHints.length == 1
                      ? 'A budget for ${top.categoryName}, from your history'
                      : 'Budgets for ${_budgetHints.length} categories, '
                          'from your history',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff1C1939)),
                ),
                const SizedBox(height: 2),
                Text(
                  newOnes > 0
                      ? 'About $_currency'
                          '${NumberFormat('#,###').format(top.amount)} a month '
                          'on ${top.categoryName}, plus $newOnes '
                          '${newOnes == 1 ? "category" : "categories"} you do '
                          'not track yet.'
                      : 'You have been spending about $_currency'
                          '${NumberFormat('#,###').format(top.amount)} '
                          'a month on ${top.categoryName}.',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _brand,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: _openBudgetSuggestions,
            child: const Text('See',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _openBudgetSuggestions() async {
    final current = await _repo.trackedItemsWithBudgets();
    if (!mounted) return;

    final chosen = await showBudgetSuggestionSheet(
      context,
      suggestions: _budgetHints,
      currentBudgets: {
        for (final e in current.entries)
          e.key: double.tryParse(
                  e.value.replaceAll(RegExp(r'[^0-9.]'), '')) ??
              0,
      },
      currency: _currency,
    );

    // Backing out is an answer too, but a softer one: the banner stays so the
    // offer can be picked up again on this visit.
    if (chosen == null || chosen.isEmpty) return;

    for (final s in chosen) {
      await _repo.applyBudgetSuggestion(s);
    }
    if (!mounted) return;
    setState(() {
      _budgetHintsDismissed = true;
      _tracked = {..._tracked, ...chosen.map((s) => s.categoryName)};
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(chosen.length == 1
            ? '${chosen.first.categoryName} budget set'
            : '${chosen.length} budgets set'),
      ),
    );
  }

  Widget _intro() => Padding(
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 16),
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

  /// Shown when there is nothing to tag.
  ///
  /// Two very different situations end up here. Someone already tracking
  /// categories has simply run out of counterparties worth asking about. A new
  /// user -- no bank alerts we recognise, or a fresh phone -- has nothing at
  /// all, and if this screen just apologised they would land on an empty home
  /// screen with no budget anywhere. So they get the catalogue instead, which
  /// is the job the track-items screen used to do.
  Widget _emptyState() =>
      _tracked.isEmpty ? _catalogueSetup() : _nothingToSort();

  Widget _nothingToSort() => Center(
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

  Widget _catalogueSetup() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What do you want to budget for?',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pick a few to start with and set what you plan to spend on '
                  'each. You can add more at any time.',
                  style: TextStyle(
                      fontSize: 13, height: 1.4, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 10,
                children: [
                  for (final entry in _suggestions) _catalogueChip(entry),
                  _newCategoryChip(),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _smsBanner() => Container(
        margin: const EdgeInsets.fromLTRB(2, 8, 2, 4),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xffFFF4E5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xffFFD9A8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sms_outlined,
                    size: 18, color: Color(0xff9A6412)),
                const SizedBox(width: 8),
                Text('SMS access is off',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.brown.shade800)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'This app finds your spending by reading your bank alerts. '
              'Until you turn it on, new transactions will not show up here '
              'and nothing will be tracked automatically.',
              style: TextStyle(
                  fontSize: 12.5, height: 1.45, color: Colors.brown.shade700),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _requestSms,
              child: Text('Turn on SMS access',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.brown.shade900,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ),
      );

  Widget _catalogueChip(CatalogueEntry entry) => GestureDetector(
        onTap: () => _adopt(entry),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.image.isNotEmpty) ...[
                // A missing or unparseable SVG must not blank the whole grid.
                SvgPicture.asset(
                  entry.image,
                  height: 16,
                  width: 16,
                  placeholderBuilder: (_) => const SizedBox(width: 16),
                ),
                const SizedBox(width: 8),
              ],
              Text(entry.name,
                  style: const TextStyle(fontSize: 14, color: Colors.black87)),
            ],
          ),
        ),
      );

  Widget _newCategoryChip() => GestureDetector(
        onTap: _createCategory,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('+ Something else',
              style: TextStyle(
                  fontSize: 14, color: _brand, fontWeight: FontWeight.w600)),
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
    final saving = _savingKeys.contains(e.key);
    final guess = _guesses[e.key];
    // A category the app would file this into if it existed. Offered on the
    // card so accepting it is one tap rather than a trip through the picker.
    final ghosts = !answered && (guess?.needsNewCategory ?? false)
        ? guess!.suggestedOptions
        : const <String>[];

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
        onTap: saving ? null : () => _pick(e),
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
                  color: answered
                      ? _brand.withValues(alpha: 0.14)
                      : Colors.grey.shade100,
                ),
                child: saving
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _brand),
                      )
                    : Icon(
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
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        saving
                            ? '$label  ·  saving'
                            : label ??
                                '${e.txCount} transactions  ·  Tap to choose',
                        key: ValueKey('${e.key}-$label-$saving'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: answered ? _brand : Colors.grey.shade500,
                          fontWeight:
                              answered ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    // Only where the app is unsure. A note on every row is
                    // noise, and noise is what gets ignored.
                    if (guess?.note != null && answered && !saving) ...[
                      const SizedBox(height: 4),
                      Text(guess!.note!,
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.3,
                              color: Colors.grey.shade500)),
                    ],
                    if (ghosts.isNotEmpty && !saving) ...[
                      const SizedBox(height: 9),
                      GhostHint(text: guess!.reason),
                      const SizedBox(height: 7),
                      // Several, where the app genuinely cannot choose. A
                      // transfer to a person could be a gift, a loan or
                      // lunch, and the user often does not know either --
                      // three plausible buckets on the card beats one
                      // confident wrong answer or an empty row.
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final g in ghosts)
                            GhostChip(
                              label: g,
                              dense: true,
                              onTap: () => _acceptSuggestion(e, g),
                            ),
                        ],
                      ),
                    ],
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

  /// Leaves the screen.
  ///
  /// Reached two ways: replacing the progress screen after a migration, where
  /// there is nothing beneath to return to, or pushed from the summary's
  /// banner, where popping is right.
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/deeplink/summary');
    }
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
      suggestions: _suggestions,
      onAdopt: _adopt,
      ghostOptions: _guesses[e.key]?.suggestedOptions ?? const [],
      ghostReason: _guesses[e.key]?.reason,
      onAcceptGhost: (name) async {
        final setup = await showCategorySetupSheet(context,
            currency: _currency,
            fixedName: name,
            history: await _repo.historyForCategory(name));
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
            _guesses.remove(e.key);
          });
          await _reassignAfterNewCategory();
        }
        return created;
      },
    );
    if (chosen == null) return;

    // Tagging into a category that is not tracked this month means the money
    // lands nowhere the user can see it -- the exact problem this feature
    // exists to solve. So say so, and offer the fix.
    if (!chosen.notSpending && chosen.categoryId != null) {
      final category = _categories.firstWhere((c) => c.id == chosen.categoryId,
          orElse: () => const Category(id: '', name: ''));
      if (category.name.isNotEmpty && !_tracked.contains(category.name)) {
        // Backing out of the budget sheet cancels the tag too, rather than
        // pointing this counterparty at a category with no budget.
        final started = await _startTracking(category);
        if (!started) return;
      }
    }

    // Shown straight away and saved behind it. The answer is the user's
    // decision, not the database's -- making them watch a spinner before
    // seeing their own choice reflected would be backwards.
    if (mounted) {
      setState(() {
        _choices[e.key] = chosen;
        _savingKeys.add(e.key);
      });
    }

    try {
      // Written immediately rather than held until Done. On a phone that kills
      // backgrounded apps, holding twenty answers in memory means losing
      // twenty.
      await _repo.tagCounterparty(
        key: e.key,
        disposition:
            chosen.notSpending ? Disposition.notSpending : Disposition.tracked,
        categoryId: chosen.categoryId,
      );
    } catch (err) {
      // ignore: avoid_print
      print('BATCH: tag failed for ${e.key}: $err');
      if (mounted) setState(() => _choices.remove(e.key));
    } finally {
      if (mounted) setState(() => _savingKeys.remove(e.key));
    }
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
      history: await _repo.historyForCategory(category.name),
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

  /// Turns a suggested category into a tracked one.
  ///
  /// The budget sheet still runs: a suggestion is a name, not a decision about
  /// how much to spend, and a category without a budget is not trackable.
  Future<Category?> _adopt(CatalogueEntry entry) async {
    final setup = await showCategorySetupSheet(
      context,
      currency: _currency,
      fixedName: entry.name,
      history: await _repo.historyForCategory(entry.name),
    );
    if (setup == null) return null;

    final category = await _repo.startTracking(
      name: entry.name,
      budget: setup.budget,
      image: entry.image,
    );
    if (mounted) {
      setState(() {
        if (!_categories.any((c) => c.id == category.id)) {
          _categories = [..._categories, category]
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        }
        _tracked.add(category.name);
        _suggestions =
            _suggestions.where((s) => s.name != entry.name).toList();
      });
      await _reassignAfterNewCategory();
    }
    return category;
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
        _suggestions =
            _suggestions.where((s) => s.name != category.name).toList();
      });
    }
    return category;
  }

  Widget _actionBar() =>
      _isSetup ? _setupActionBar() : _taggingActionBar();

  /// No Skip. A budget is the thing this app measures against, so leaving
  /// here with none set would hand the user an app that cannot do its job.
  Widget _setupActionBar() {
    final ready = _tracked.isNotEmpty;
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
                ready
                    ? '${_tracked.length} '
                        '${_tracked.length == 1 ? "category" : "categories"} set up'
                    : 'Pick at least one to continue',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
            ElevatedButton(
              onPressed: ready && !_saving ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Get started',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taggingActionBar() {
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
                      // Same effect as Done: the screen has been dealt with.
                      // The summary's banner is how anyone who wants another
                      // round gets back to it.
                      await _repo.markBatchTagDismissed();
                      if (context.mounted) _leave();
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

}
