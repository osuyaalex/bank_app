import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/category_catalogue.dart';
import '../data/spend_repository.dart';
import '../story/story_day.dart';
import 'widget/category_picker.dart' show brandBlue;
import 'widget/category_setup_sheet.dart';
import 'widget/screen_guide.dart';

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
    GuideStep('Give each one a budget \u2014 what you plan to spend, not what '
        'you have spent.'),
    GuideStep('Tap Continue. Your bank messages get sorted into these.'),
    GuideStep('To remove a budget later, open it from the home screen.'),
  ];
  static const _guideFootnote =
      'Pick three or four to start with. You can add more at any time.';

  static const _returningSteps = [
    GuideStep('These are the budgets you set last month, carried over.'),
    GuideStep('Tap any of them to change the figure.'),
    GuideStep('Tap Continue when it looks right.'),
  ];

  List<CatalogueEntry> _catalogue = [];
  String _currency = '';

  bool _loading = true;
  bool _saving = false;

  /// Name to budget, in the order chosen, so the summary at the bottom reads
  /// the way the user built it.
  final Map<String, String> _chosen = {};
  final Map<String, String> _images = {};

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
      // From month two onward these exist, so returning users pick a budget
      // from their own spending instead of retyping last month's.
  
      if (!mounted) return;
      setState(() {
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
        _returning = tracked.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print('TRACK ITEMS: load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _total => _chosen.values.fold(0.0, (sum, b) {
        final digits = b.replaceAll(RegExp(r'[^0-9]'), '');
        return sum + (double.tryParse(digits) ?? 0);
      });

  /// A budget of zero is not a budget.
  ///
  /// Checking only that the field was non-empty let a "0" through, and a
  /// carried-forward category whose figure was never set arrives as exactly
  /// that -- so a month could be confirmed with a category that measures
  /// against nothing.
  static bool _isRealBudget(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return (int.tryParse(digits) ?? 0) > 0;
  }

  bool get _ready =>
      _chosen.isNotEmpty && _chosen.values.every(_isRealBudget);

  Future<void> _toggle(String name, String image) async {
    if (_chosen.containsKey(name)) {
      setState(() => _chosen.remove(name));
      return;
    }
    // Selecting and budgeting are one action. Splitting them is how the old
    // screen ended up with categories carrying a budget of "0".
    final setup = await showCategorySetupSheet(context,
        currency: _currency,
        fixedName: name,
        history: await _repo.historyForCategory(name));
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
    final setup = await showCategorySetupSheet(context,
        currency: _currency,
        fixedName: name,
        history: await _repo.historyForCategory(name));
    if (setup == null) return;
    setState(() => _chosen[name] = setup.budget);
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save. Check your connection and try '
                'again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final unchosen =
        _catalogue.where((e) => !_chosen.containsKey(e.name)).toList();

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
              _returning ? 'Your budgets for this month' : 'What do you want to budget for?',
              style: const TextStyle(
                  color: Colors.black, fontSize: 16, fontWeight: FontWeight.w600)),
          actions: [
            GuideButton(
                id: _guideId,
                title: _guideTitle,
                steps: _returning ? _returningSteps : _guideSteps,
                footnote: _guideFootnote),
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
                  footnote: _guideFootnote),
              if (_chosen.isNotEmpty) ...[
                _sectionLabel('YOUR BUDGETS'),
                for (final name in _chosen.keys) _chosenRow(name),
                const SizedBox(height: 8),
              ],
              _sectionLabel(
                  _chosen.isEmpty ? 'TAP TO ADD' : 'ADD SOMETHING ELSE'),
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

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w700,
                color: Colors.black38)),
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
              color: _isRealBudget(_chosen[name] ?? '')
                  ? brandBlue.withValues(alpha: 0.35)
                  : const Color(0xffB7791F).withValues(alpha: 0.5)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _editBudget(name),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                if (image.isNotEmpty)
                  SvgPicture.asset(image,
                      height: 18,
                      width: 18,
                      placeholderBuilder: (_) => const SizedBox(width: 18))
                else
                  const Icon(Icons.category_outlined,
                      size: 18, color: Colors.black38),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
                if (_isRealBudget(_chosen[name] ?? ''))
                  Text('$_currency${_chosen[name]}',
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: brandBlue))
                else
                  const Text('Set a budget',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xffB7791F))),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade300),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _catalogueChip(CatalogueEntry e) => GestureDetector(
        onTap: () => _toggle(e.name, e.image),
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
                SvgPicture.asset(e.image,
                    height: 16,
                    width: 16,
                    placeholderBuilder: (_) => const SizedBox(width: 16)),
                const SizedBox(width: 8),
              ],
              Text(e.name,
                  style: const TextStyle(fontSize: 14, color: Colors.black87)),
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
          child: const Text('+ Something else',
              style: TextStyle(
                  fontSize: 14, color: brandBlue, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _bottomBar() {
    final money = NumberFormat('#,##0');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                            : '${_chosen.values.where((b) => !_isRealBudget(b)).length}'
                                ' still need a figure',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  if (_chosen.isNotEmpty)
                    Text('$_currency${money.format(_total)} a month in total',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Continue',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
