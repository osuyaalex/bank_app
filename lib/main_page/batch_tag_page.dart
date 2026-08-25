import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/category_catalogue.dart';
import '../data/migration_plan.dart';
import '../data/models.dart';
import '../data/spend_repository.dart';
import 'widget/category_picker.dart';
import 'widget/category_setup_sheet.dart';

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

  /// Whether the app can read the SMS inbox. Without it there is nothing to
  /// tag and no amount of waiting will change that, so the screen says so
  /// rather than letting the user assume they simply have no spending.
  bool _smsGranted = true;

  bool _loading = true;
  bool _saving = false;

  /// True when this screen is standing in for the old track-items screen:
  /// no counterparties worth asking about and no categories yet. The rules
  /// differ -- there is nothing to skip, and leaving without a budget would
  /// drop the user onto an empty home screen.
  bool get _isSetup => _rows.isEmpty && _tracked.isEmpty;

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

    final categories = await _repo.loadCategories();
    final tracked = await _repo.trackedCategoryNames();
    final currency = await _repo.currencySymbol();
    final map = await _repo.loadCounterparties();
    final catalogue = await CategoryCatalogue.load();
    final smsGranted = await _readSmsPermission();

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
      _rows = [
        ...proposed,
        ...batchTagCandidates(map,
            limit: widget.limit, trackedCategories: tracked),
      ];
      _loading = false;
    });
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

  Future<void> _save() async {
    setState(() => _saving = true);
    // Answers were saved as they were made; this only closes the screen.
    final settled = _choices.length;
    final wasSetup = _isSetup;
    await _repo.markBatchTagSeen();
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
          if (!_smsGranted) _smsBanner(),
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
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
              'Without it there is nothing to sort and you will have to enter '
              'everything by hand.',
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
                      await _repo.markBatchTagSeen();
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
