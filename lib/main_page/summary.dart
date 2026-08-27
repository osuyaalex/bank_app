import 'dart:async';
import 'package:banking_app/main_page/home_page.dart';
import 'package:banking_app/main_page/item_details.dart';
import 'package:banking_app/main_page/widget/generate_dots.dart';
import 'package:banking_app/main_page/widget/skeleton.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../data/budget_status.dart';
import 'widget/category_picker.dart' show brandBlue;
import '../data/pending_notifications.dart';
import '../data/spend_repository.dart';
import 'widget/bank_charges_sheet.dart';
import '../data/migration_gate.dart';
import '../elevated_button.dart';



class Summary extends StatefulWidget {
  const Summary({super.key});

  @override
  State<Summary> createState() => _SummaryState();
}

class _SummaryState extends State<Summary> with WidgetsBindingObserver {
  Map<String, dynamic> _data ={};
  int _pendingCount = 0;
  int _untaggedCount = 0;
  String _message = '';
  List _itemsByDescendOrder = [];
  String _currentMonth = '';


  /// Live subscription to this month's document.
  ///
  /// Read once, this screen kept whatever it loaded in initState: tagging on
  /// the home screen rewrote the totals, but popping back here re-showed the
  /// old ones because nothing re-read. Listening means any write -- a scan, a
  /// tag, a correction, the totals rebuild -- lands here on its own.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _monthSub;
  StreamSubscription<int>? _pendingSub;

  void _watchTrackItems() {
    String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    _currentMonth = currentMonth.replaceAll(' ', '');
    _monthSub?.cancel();
    _monthSub = FirebaseFirestore.instance
        .collection("track_items")
        .doc(_currentMonth)
        .collection("monthUsers")
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .snapshots()
        .listen(_applyTrackItems, onError: (e) {
      // ignore: avoid_print
      print('Summary: month listener failed: $e');
    });
  }

  /// Creates the month document when the listener finds none.
  ///
  /// Guarded: the listener fires again the moment the document appears, and
  /// without this flag that would start a second bootstrap mid-write.
  bool _bootstrapping = false;

  Future<void> _bootstrapMonth() async {
    if (_bootstrapping) return;
    _bootstrapping = true;
    try {
      final repo = SpendRepository();
      await repo.ensureMonthInitialised();
      // Nothing carried over means a user who has never set a budget, and the
      // batch screen is where categories are chosen now.
      if ((await repo.trackedCategoryNames()).isEmpty && mounted) {
        context.go('/batchTag');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Summary: could not create this month: $e');
    }
  }

  void _watchCharges() {
    try {
      _chargesSub?.cancel();
      _chargesSub = SpendRepository().watchCharges().listen((v) {
        if (mounted) setState(() => _charges = v);
      }, onError: (_) {/* an extra line; never break the screen */});
    } catch (_) {/* not signed in yet */}
  }

  Future<void> _openCharges() async {
    final rows = await SpendRepository().chargeTransactions();
    if (!mounted) return;
    await showBankChargesSheet(context,
        charges: rows, currency: '${_data['currency'] ?? ''}');
  }

  /// The fees, said quietly and kept clear of the budget bar above it.
  Widget _chargesLine(String currency) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextButton(
          onPressed: _openCharges,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: Colors.grey.shade700,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                'Plus $currency${_formatNumber(_charges)} in bank charges',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
              const SizedBox(width: 3),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: Colors.grey.shade500),
            ],
          ),
        ),
      );

  void _watchPending() {
    try {
      _pendingSub?.cancel();
      _pendingSub = SpendRepository().watchPendingCount().listen((count) {
        if (mounted) setState(() => _pendingCount = count);
      }, onError: (_) {/* the banner is an extra; never break the screen */});
    } catch (_) {/* not signed in yet */}
  }

  void _applyTrackItems(DocumentSnapshot userDoc) {
    if (!mounted) return;
    setState(() {
      if (userDoc.exists && userDoc.data() != null) {
        _data = userDoc.data() as Map<String, dynamic>;
        _itemsByDescendOrder =  _data['listItems'];
        _itemsByDescendOrder.sort((a, b) => (b['totalAmountSpent'] as num).compareTo(a['totalAmountSpent'] as num));
        _data['listItems'] = _itemsByDescendOrder;
        // Calculate the sum of budgetSet values
        double totalBudgetSet = 0.0;
        if (_data['listItems'] != null) {
          for (var item in _data['listItems']) {
            String budgetString = item['budgetSet'].replaceAll(RegExp(r'[^\d.]'), '');
            double budgetSet = double.tryParse(budgetString) ?? 0.0;
            totalBudgetSet += budgetSet;
          }

        }

        if(_data['monthlySpend'] < totalBudgetSet/2){
          _message = 'Great job! Your spending is well within your budget. Keep up the good work!';
        }else if(_data['monthlySpend'] == totalBudgetSet/2){
          _message = "Attention! You've reached 50% of your budget. Take a look at your expenses to stay on track.";
        }else if(_data['monthlySpend'] > totalBudgetSet/2){
          _message = "Warning! You've spent more than half of your budget. Be careful to avoid overspending.";
        }

        _totalBudget = totalBudgetSet;
      } else {
        // No document for this month yet. It used to mean "send them to the
        // track-items screen"; it now means "create it", carrying last
        // month's budgets over. The listener above picks the result up.
        _bootstrapMonth();
      }
    });
  }

  /// This month's budget across every category.
  ///
  /// It was already being worked out and used only to pick a warning
  /// sentence. Showing the figure is the point of a budgeting app: a number
  /// on its own says what was spent, not whether that was too much.
  double _totalBudget = 0;

  /// Bank fees this month. Outside every budget, but not outside the screen:
  /// money left the account and until now nothing anywhere said so.
  double _charges = 0;
  StreamSubscription<double>? _chargesSub;

  /// "of ₦450,000 budgeted", with a bar showing how much of it is gone.
  Widget _budgetLine({
    required String currency,
    required double spent,
    required double budget,
  }) {
    final status = BudgetStatus.of(spent: spent, budget: budget);
    final colour = switch (status.level) {
      BudgetLevel.over => const Color(0xffC0392B),
      BudgetLevel.nearing => const Color(0xffB7791F),
      BudgetLevel.ok => brandBlue,
    };
    final fraction = status.fraction.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          Text('of $currency${_formatNumber(budget)} budgeted',
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
          const SizedBox(height: 7),
          Text(status.describe(currency),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: status.level == BudgetLevel.ok
                      ? Colors.grey.shade600
                      : colour)),
        ],
      ),
    );
  }

  String _formatNumber(double? number) {
    if(number != null){
      final formatter = NumberFormat('#,###.##');
      return formatter.format(number);
    }
    return '';
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _watchTrackItems();
    _watchPending();
    _watchCharges();

    WidgetsBinding.instance.addObserver(this);
    // After the first frame, so the migration never delays this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await MigrationGate.maybeRun(context);
      // Maintenance rewrites this month's totals, and the figures on screen
      // were read before it ran. Without this, Summary keeps showing the
      // pre-rebuild number while Home -- which loads later -- shows the new
      // one, and the two disagree.
      if (mounted) await _loadSortCounts();
      // A notification tap cannot navigate on its own -- the UI may not exist
      // yet when it fires -- so it leaves a flag for the first screen to act on.
      if (PendingNotifications.openPendingList && mounted) {
        PendingNotifications.openPendingList = false;
        if (context.mounted) await context.push('/pending');
        if (mounted) await _loadSortCounts();
      }
    });
  }
  @override
  void dispose() {
    _monthSub?.cancel();
    _pendingSub?.cancel();
    _chargesSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Transactions can be answered from a notification while the app is in
    // the background, so the count is refreshed on return.
    if (state == AppLifecycleState.resumed) _loadSortCounts();
  }

  Future<void> _loadSortCounts() async {
    try {
      // _pendingCount arrives from its own listener; only the untagged
      // counterparty count is read here.
      final untagged = await SpendRepository().pendingTagCount();
      if (!mounted) return;
      setState(() => _untaggedCount = untagged);
    } catch (_) {
      // The banner is an extra; never let it break the screen.
    }
  }

  Widget _sortBanner() {
    if (_pendingCount == 0 && _untaggedCount == 0) return const SizedBox.shrink();
    final needsSorting = _pendingCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await context.push(needsSorting ? '/pending' : '/batchTag');
          await _loadSortCounts();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xff5AA5E2).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.help_outline, color: Color(0xff5AA5E2), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  needsSorting
                      ? '$_pendingCount transaction${_pendingCount == 1 ? '' : 's'} need sorting'
                      : '$_untaggedCount more places to sort',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title:  Text('Summary',
          style: TextStyle(
            fontSize: 18,
            color: Colors.black54
          ),
          ),
        ),
        body: SingleChildScrollView(
          child: Center(
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0),
                    child: Column(
                      children: [
                        SvgPicture.asset('assets/Illustration.svg'),
                        const SizedBox(height: 22,),
                        const Text('This month spending',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.black54
                        ),
                        ),
                        _data['monthlySpend'] != null?
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10.0),
                              child:
                              Text('${_data['currency']} ${_formatNumber(_data['monthlySpend'])}',
                                style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w500
                                ),
                              ),
                            ),
                            // The figure it is measured against, directly
                            // beneath it. A total on its own says what was
                            // spent, never whether that was too much.
                            if (_totalBudget > 0)
                              _budgetLine(
                                currency: '${_data['currency'] ?? ''}',
                                spent:
                                    (_data['monthlySpend'] as num?)?.toDouble() ??
                                        0,
                                budget: _totalBudget,
                              ),
                            if (_charges > 0)
                              _chargesLine('${_data['currency'] ?? ''}'),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: MediaQuery.of(context).size.width*0.7,
                              child: Text(_message,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    height: 1.4,
                                    color: Colors.black54,
                                    fontSize: 12
                                ),
                              ),
                            ),
                          ],
                        ):SummarySkeleton(),

                        const SizedBox(height: 17,),
                        Button(
                            buttonColor: const Color(0xff5AA5E2),
                            text: 'Let\'s Go!',
                            onPressed: (){
                              Navigator.push(context, MaterialPageRoute(builder: (context){
                                return const HomePage();
                              }));
                            },
                            textColor: Colors.white,
                            width: MediaQuery.of(context).size.width,
                            height: MediaQuery.of(context).size.width*0.14,
                            minSize: false,
                            textOrIndicator: false
                        ),
                        const SizedBox(height: 22,),

                      ],
                    ),
                  ),
                ),
                _sortBanner(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0,vertical: 19),
                  child: SizedBox(
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text('Top Spends',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 15,),
                        _data['monthlySpend'] != null?
                        SizedBox(
                          height: MediaQuery.of(context).size.height*0.27,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _itemsByDescendOrder.length,
                              itemBuilder: (context, index){
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  width: MediaQuery.of(context).size.width*0.4,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    children: [
                                      DottedImage(listItems: _itemsByDescendOrder[index]),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                                        child: Text(_itemsByDescendOrder[index]['name'],
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w600
                                        ),
                                        ),
                                      ),
                                      Text('${_data['currency']} ${_formatNumber(_itemsByDescendOrder[index]['totalAmountSpent'])}',
                                        style: const TextStyle(
                                            color: Colors.black54,
                                            fontWeight: FontWeight.w600,
                                          fontSize: 12
                                        ),
                                      ),
                                      Expanded(child: Container()),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(24),
                                          color: const Color(0xff5AA5E2).withOpacity(0.1)
                                        ),
                                        child: GestureDetector(
                                            onTap: (){
                                              Navigator.push(context, MaterialPageRoute(builder: (context){
                                                return ItemDetails(
                                                    itemDetails: _itemsByDescendOrder[index],
                                                    monthDetails: _data,
                                                    actualMonth: _currentMonth,
                                                    index: index,
                                                  edit: false,
                                                );
                                              }));
                                            },
                                            child: const Text('view details',
                                            style: TextStyle(
                                              color: Color(0xff5AA5E2),
                                              fontSize: 8
                                            ),
                                            )
                                        ),
                                      )
                                      ],
                                  ),
                                ),
                              );
                              }
                          ),
                        ):SummaryListSkeleton()
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
