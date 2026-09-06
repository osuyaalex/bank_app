import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/budget_suggestion.dart';
import '../data/category_catalogue.dart';
import '../data/models.dart';
import '../data/spend_repository.dart';
import '../utilities/snackbar.dart';
import 'widget/category_picker.dart' show brandBlue;
import 'widget/category_setup_sheet.dart';
import 'widget/remove_category_sheet.dart';
import 'widget/screen_guide.dart';

/// What taking a row off the budget list actually means.
///
/// Both kinds of row look identical on the screen, and confusing them is how
/// the money goes missing: a tracker removed without saying where its
/// transactions should go leaves them pointing at a category the user can no
/// longer see, still counted in the month total with no way to correct it.
enum Removal {
  /// Picked on this screen and never saved. Nothing has been written and
  /// nothing has been filed against it, so dropping it is the whole job and
  /// asking the user to confirm an action with no consequence is noise.
  unpick,

  /// Already being tracked when the screen opened -- carried over from last
  /// month, or set up weeks ago. It may have transactions behind it, and they
  /// have to be given a home before the tracker goes.
  askWhereTheMoneyGoes,
}

/// Which of the two [name] is, given what was already tracked when the screen
/// opened.
Removal removalFor(Set<String> tracked, String name) =>
    tracked.contains(name) ? Removal.askWhereTheMoneyGoes : Removal.unpick;

/// A budget of zero is not a budget.
///
/// Checking only that the field was non-empty let a "0" through, and a
/// carried-forward category whose figure was never set arrives as exactly
/// that -- so a month could be confirmed with a category that measures
/// against nothing.
bool isRealBudget(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  return (int.tryParse(digits) ?? 0) > 0;
}

/// The figures added up, ignoring the separators they are stored with.
double budgetTotal(Iterable<String> budgets) => budgets.fold(0.0, (sum, b) {
  final digits = b.replaceAll(RegExp(r'[^0-9]'), '');
  return sum + (double.tryParse(digits) ?? 0);
});

/// Where the user says what they want to budget for, and how much.
///
/// This runs before the scan, deliberately. The app files a transaction by
/// matching it to a category that already exists, so a user who reaches the
/// batch screen with no categories gets nothing matched and has to tag every
/// row by hand -- which is exactly what happened on a fresh account.
///
/// Rebuilt rather than restored. The old screen made the user set a budget
/// for all twenty-nine categories before the button would enable, showed the
/// selection and the budget in two disconnected places, and explained none of
/// it.
class SelectTrackItems extends StatefulWidget {
  const SelectTrackItems({super.key, this.repo, this.returnOnDone = false});

  final SpendRepository? repo;

  /// True when the user came here to add a category and expects to be handed
  /// back where they were.
  ///
  /// Without it, adding one budget from the home screen dropped the user into
  /// the scan and then the batch screen -- a whole onboarding flow in answer
  /// to "add a category". The screen is used for two different things and has
  /// to know which.
  final bool returnOnDone;

  @override
  State<SelectTrackItems> createState() => _SelectTrackItemsState();
}

class _SelectTrackItemsState extends State<SelectTrackItems> {
  late final SpendRepository _repo = widget.repo ?? SpendRepository();

  static const _guideId = 'track_items';
  static const _guideTitle = 'Set up your budgets';
  static const _guideSteps = [
    GuideStep('Tap the things you spend money on each month.'),
    GuideStep(
      'Give each one a budget \u2014 what you plan to spend, not what '
      'you have spent.',
    ),
    GuideStep('Tap Continue. Your bank messages get sorted into these.'),
    GuideStep('Tapped one by mistake? Use the \u00d7 beside it.'),
  ];
  static const _guideFootnote =
      'Pick three or four to start with. You can add more at any time.';

  static const _returningSteps = [
    GuideStep('These are the budgets you set last month, carried over.'),
    GuideStep('Tap any of them to change the figure.'),
    GuideStep(
      'Use the \u00d7 to stop budgeting for something. You will be '
      'asked where its transactions should go.',
    ),
    GuideStep('Tap Continue when it looks right.'),
  ];

  List<CatalogueEntry> _catalogue = [];

  /// Categories taken from what the user has actually been paying for.
  ///
  /// This screen used to open with twenty-nine abstract nouns and ask people
  /// to choose some and invent a budget for each, before showing them a
  /// single thing they had spent money on. They chose blind, and then met a
  /// sorting screen full of payments matching none of it.
  List<BudgetSuggestion> _fromSpending = [];
  String _currency = '';

  bool _loading = true;
  bool _saving = false;

  /// Name to budget, in the order chosen, so the summary at the bottom reads
  /// the way the user built it.
  final Map<String, String> _chosen = {};
  final Map<String, String> _images = {};

  /// Of the rows in [_chosen], the ones that were already tracked when the
  /// screen opened.
  ///
  /// Both kinds of row look identical, and removing them does not mean the
  /// same thing. One was picked a moment ago and exists only in [_chosen];
  /// the other has been live -- carried over from last month, or set up weeks
  /// ago and still collecting transactions. Un-picking the second would
  /// remove it from this screen and leave it in the database, because
  /// [_continue] only ever starts tracking.
  final Set<String> _tracked = {};

  /// True when this is a new month rather than a first setup, so the screen
  /// can say "here is last month's plan" instead of "pick some categories".
  bool _returning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _repo.ensureMonthInitialised();
      final catalogue = await CategoryCatalogue.load();
      final currency = await _repo.currencySymbol();
      // Anything already tracked is carried in, so re-entering this screen
      // shows the work rather than asking for it again.
      final existing = await _repo.pickerCategories();
      // With their budgets, not just their names.
      final tracked = await _repo.trackedItemsWithBudgets();

      // What they actually spend on, which is where the categories should
      // come from. Recomputed when there is nothing stored, because for a
      // new user the scan has only just finished.
      var spending = await _repo.budgetSuggestions();
      if (spending.isEmpty) {
        await _repo.refreshBudgetSuggestions();
        spending = await _repo.budgetSuggestions();
      }

      if (!mounted) return;
      setState(() {
        _fromSpending = spending;
        _catalogue = catalogue;
        _currency = currency;
        for (final c in existing) {
          _images[c.name] = c.image ?? '';
        }
        for (final e in catalogue) {
          _images.putIfAbsent(e.name, () => e.image);
        }
        // Last month's choices arrive already made. A new month is a moment
        // to review a budget, not to re-enter it -- everything is filled in
        // and the user changes only what they want to change.
        tracked.forEach((name, budget) {
          _chosen.putIfAbsent(name, () => budget);
        });
        _tracked.addAll(tracked.keys);
        _returning = tracked.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print('TRACK ITEMS: load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _total => budgetTotal(_chosen.values);

  bool get _ready => _chosen.isNotEmpty && _chosen.values.every(isRealBudget);

  /// Only ever called for a category not yet chosen -- the grid it is wired to
  /// is built from [_chosen]'s complement. It used to carry an un-picking
  /// branch for the case where the name was already chosen, which could not
  /// run for that reason, and which was the only removal code on the screen.
  /// Taking a budget back off the list is [_remove].
  Future<void> _pick(String name, String image) async {
    // Selecting and budgeting are one action. Splitting them is how the old
    // screen ended up with categories carrying a budget of "0".
    final setup = await showCategorySetupSheet(
      context,
      currency: _currency,
      fixedName: name,
      history: await _repo.historyForCategory(name),
    );
    if (setup == null) return;
    setState(() {
      _chosen[name] = setup.budget;
      _images[name] = image;
    });
  }

  Future<void> _addOwn() async {
    final setup = await showCategorySetupSheet(context, currency: _currency);
    if (setup == null) return;
    setState(() {
      _chosen[setup.name] = setup.budget;
      _images.putIfAbsent(setup.name, () => '');
    });
  }

  Future<void> _editBudget(String name) async {
    final setup = await showCategorySetupSheet(
      context,
      currency: _currency,
      fixedName: name,
      history: await _repo.historyForCategory(name),
    );
    if (setup == null) return;
    setState(() => _chosen[name] = setup.budget);
  }

  /// Takes a budget back off the list.
  ///
  /// A category picked on this screen and not yet saved is simply dropped:
  /// nothing has been written, nothing has been filed against it, and asking
  /// for confirmation of an action with no consequence is noise.
  ///
  /// One that was already being tracked is a different thing entirely. It may
  /// have weeks of transactions behind it, and removing a tracker without
  /// saying where its money goes is what left transactions pointing at a
  /// category the user could no longer see -- the reason
  /// [showRemoveCategorySheet] exists. So that is the path it takes, the same
  /// one the details screen uses.
  Future<void> _remove(String name) async {
    if (_saving) return;

    if (removalFor(_tracked, name) == Removal.unpick) {
      setState(() => _chosen.remove(name));
      return;
    }

    final categoryId = slugifyCategory(name);
    setState(() => _saving = true);

    int count;
    List<Category> others;
    try {
      count = await _repo.transactionCountFor(categoryId);
      others = (await _repo.pickerCategories())
          .where((c) => c.id != categoryId)
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('TRACK ITEMS: could not read $name: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      snack(context, 'Could not read this category.');
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);

    final outcome = await showRemoveCategorySheet(
      context,
      categoryName: name,
      transactionCount: count,
      otherCategories: others,
    );
    if (outcome == null || !mounted) return;

    setState(() => _saving = true);
    try {
      if (outcome.choice == RemoveChoice.moveThenRemove) {
        await _repo.moveCategoryTransactions(
          fromCategoryId: categoryId,
          toCategoryId: outcome.moveTo!,
          toCategoryName: outcome.moveToName!,
        );
      }
      await _repo.deleteCategory(
        categoryId: categoryId,
        categoryName: name,
        deleteTransactions: outcome.choice == RemoveChoice.removeAndDelete,
      );
      if (!mounted) return;
      setState(() {
        _chosen.remove(name);
        _tracked.remove(name);
        _saving = false;
      });
      snack(context, switch (outcome.choice) {
        RemoveChoice.moveThenRemove => '$count moved to ${outcome.moveToName}.',
        RemoveChoice.removeAndUnfile =>
          count == 0
              ? '$name removed.'
              : '$name removed. $count sent back to sorting.',
        RemoveChoice.removeAndDelete =>
          '$name removed and $count '
              'transaction${count == 1 ? "" : "s"} deleted.',
      });
    } catch (e) {
      // ignore: avoid_print
      print('TRACK ITEMS: remove $name failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      snack(context, 'Could not remove this category.');
    }
  }

  Future<void> _continue() async {
    if (!_ready || _saving) return;
    setState(() => _saving = true);
    try {
      for (final entry in _chosen.entries) {
        await _repo.startTracking(
          name: entry.key,
          budget: entry.value,
          image: _images[entry.key] ?? '',
        );
      }
      await _repo.markBudgetsConfirmed();
      if (!mounted) return;
      if (widget.returnOnDone) {
        // Back where they came from. The new category is live immediately --
        // the screens read from listeners -- so there is nothing to run.
        Navigator.pop(context);
        return;
      }
      // Onboarding, or a new month: straight into the scan, which is where
      // the categories just chosen get matched against actual spending.
      context.go('/preparing');
    } catch (e) {
      // ignore: avoid_print
      print('TRACK ITEMS: save failed: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save. Check your connection and try '
              'again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final unchosen = _catalogue
        .where((e) => !_chosen.containsKey(e.name))
        .toList();

    return PopScope(
      // Only a gate during onboarding and at the turn of a month. Trapping
      // someone who tapped "add more" would be wrong.
      canPop: widget.returnOnDone,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          automaticallyImplyLeading: widget.returnOnDone,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: Text(
            _returning
                ? 'Your budgets for this month'
                : _fromSpending.isEmpty
                // No inbox to go on, so it really is a blank list and
                // the old question is the honest one.
                ? 'What do you want to budget for?'
                : 'Here is where your money goes',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            GuideButton(
              id: _guideId,
              title: _guideTitle,
              steps: _returning ? _returningSteps : _guideSteps,
              footnote: _guideFootnote,
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              ScreenGuide(
                id: _guideId,
                title: _guideTitle,
                steps: _returning ? _returningSteps : _guideSteps,
                footnote: _guideFootnote,
              ),
              if (_chosen.isNotEmpty) ...[
                _sectionLabel('YOUR BUDGETS'),
                for (final name in _chosen.keys) _chosenRow(name),
                const SizedBox(height: 8),
              ],
              if (_unchosenFromSpending.isNotEmpty) ...[
                _sectionLabel('FROM YOUR SPENDING'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    'Tap one to start budgeting for it. The figures are what '
                    'you have been spending.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                for (final s in _unchosenFromSpending) _spendingRow(s),
                const SizedBox(height: 10),
              ],
              _sectionLabel(
                _unchosenFromSpending.isNotEmpty
                    ? 'SOMETHING ELSE'
                    : _chosen.isEmpty
                    ? 'TAP TO ADD'
                    : 'ADD SOMETHING ELSE',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    for (final e in unchosen) _catalogueChip(e),
                    _ownChip(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }

  /// Proposals not already taken.
  List<BudgetSuggestion> get _unchosenFromSpending =>
      _fromSpending.where((s) => !_chosen.containsKey(s.categoryName)).toList();

  /// One category found in their spending, with what it costs them.
  Widget _spendingRow(BudgetSuggestion s) {
    final money = NumberFormat('#,###');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _takeSuggestion(s),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.categoryName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xff1C1939),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'about $_currency${money.format(s.amount)} a month',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: brandBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  'Budget this',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: brandBlue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Takes one, with the figure already worked out.
  ///
  /// The sheet still opens, because the number is a proposal rather than a
  /// decision -- but it opens filled in, so agreeing is one tap and nothing
  /// needs typing.
  Future<void> _takeSuggestion(BudgetSuggestion s) async {
    final setup = await showCategorySetupSheet(
      context,
      currency: _currency,
      fixedName: s.categoryName,
      history: [for (final m in s.months) m.total],
      suggested: s.amount,
    );
    if (setup == null || !mounted) return;
    setState(() => _chosen[s.categoryName] = setup.budget);
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w700,
        color: Colors.black38,
      ),
    ),
  );

  Widget _chosenRow(String name) {
    final image = _images[name] ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRealBudget(_chosen[name] ?? '')
                ? brandBlue.withValues(alpha: 0.35)
                : const Color(0xffB7791F).withValues(alpha: 0.5),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _editBudget(name),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                if (image.isNotEmpty)
                  SvgPicture.asset(
                    image,
                    height: 18,
                    width: 18,
                    placeholderBuilder: (_) => const SizedBox(width: 18),
                  )
                else
                  const Icon(
                    Icons.category_outlined,
                    size: 18,
                    color: Colors.black38,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isRealBudget(_chosen[name] ?? ''))
                  Text(
                    '$_currency${_chosen[name]}',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: brandBlue,
                    ),
                  )
                else
                  const Text(
                    'Set a budget',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xffB7791F),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.grey.shade300,
                ),
                // Its own tap target, separated by a rule, because the rest of
                // the row edits the figure and these two must never be
                // mistaken for each other.
                Container(
                  width: 1,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: Colors.grey.shade200,
                ),
                Semantics(
                  button: true,
                  label: 'Remove $name',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _saving ? null : () => _remove(name),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: _saving
                            ? Colors.grey.shade300
                            : Colors.grey.shade500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _catalogueChip(CatalogueEntry e) => GestureDetector(
    onTap: () => _pick(e.name, e.image),
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
          if (e.image.isNotEmpty) ...[
            SvgPicture.asset(
              e.image,
              height: 16,
              width: 16,
              placeholderBuilder: (_) => const SizedBox(width: 16),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            e.name,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ],
      ),
    ),
  );

  Widget _ownChip() => GestureDetector(
    onTap: _addOwn,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: brandBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        '+ Something else',
        style: TextStyle(
          fontSize: 14,
          color: brandBlue,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Widget _bottomBar() {
    final money = NumberFormat('#,##0');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _chosen.isEmpty
                        ? 'Nothing chosen yet'
                        : _ready
                        ? '${_chosen.length} '
                              '${_chosen.length == 1 ? "budget" : "budgets"}'
                        : '${_chosen.values.where((b) => !isRealBudget(b)).length}'
                              ' still need a figure',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_chosen.isNotEmpty)
                    Text(
                      '$_currency${money.format(_total)} a month in total',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _ready && !_saving ? _continue : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: brandBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Continue',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
