import 'widget/scanning_view.dart';
import 'package:banking_app/data/background_scan.dart';
import 'package:banking_app/data/budget_status.dart';
import 'package:banking_app/data/pending_notifications.dart';
import 'package:banking_app/data/spend_repository.dart';
import 'package:banking_app/data/migration_gate.dart';
import 'package:go_router/go_router.dart';
import 'package:banking_app/firebase%20network/daily_resets.dart';
import 'package:banking_app/login%20pages/sign_in_page.dart';
import 'package:banking_app/main_page/select_track_items.dart';
import 'package:banking_app/main_page/item_details.dart';
import 'package:banking_app/main_page/widget/progress_bar.dart';
import 'package:banking_app/data/models.dart' show slugifyCategory;
import 'package:banking_app/data/sms_inbox.dart';
import 'package:banking_app/main_page/widget/share_format_sheet.dart';
import 'package:banking_app/data/unseen_activity.dart';
import 'package:flutter/services.dart';
import 'package:banking_app/main_page/widget/stream_builder.dart';
import 'package:banking_app/utilities/snackbar.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// A month's total budget, from the categories it carries.
double _monthBudget(dynamic listItems) {
  if (listItems is! List) return 0;
  var total = 0.0;
  for (final item in listItems) {
    if (item is! Map) continue;
    total +=
        double.tryParse(
          '${item['budgetSet']}'.replaceAll(RegExp(r'[^0-9.]'), ''),
        ) ??
        0;
  }
  return total;
}

/// Amber warns, red states a fact. Neither shouts: the card still has to
/// look like part of the app rather than an error state.
Color _statusColour(BudgetLevel level) {
  switch (level) {
    case BudgetLevel.over:
      return const Color(0xffC0392B);
    case BudgetLevel.nearing:
      return const Color(0xffB7791F);
    case BudgetLevel.ok:
      return Colors.transparent;
  }
}

class _HomePageState extends State<HomePage> {
  int _needsSorting = 0;
  int _untagged = 0;

  /// What has been filed since the user last opened each budget.
  UnseenTally _unseen = const UnseenTally();
  String _currentMonth = '';
  Map<String, dynamic> _data = {};
  List<String> _currentMonthDocs = [];
  Map<String, dynamic> _monthData = {};
  ValueNotifier<String> _currentMonthDataNotifier = ValueNotifier<String>('');
  ValueNotifier<bool> _updateDailySpend = ValueNotifier<bool>(false);
  int _lastPage = 0;

  /// Held true until the first scan finishes, so the page renders once with
  /// settled figures instead of drawing, then jumping when the scan lands.
  bool _preparing = true;

  Future<void> _getAllCurrentMonthDocs() async {
    try {
      // Fetch all months
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection("track_items")
          .get();
      String currentUserId = FirebaseAuth.instance.currentUser!.uid;

      // Clear the list to avoid duplicates
      _currentMonthDocs.clear();

      // Loop through each document to check if the user's data exists for the month
      List<Future<void>> checks = snapshot.docs.map((doc) async {
        DocumentReference userDocRef = FirebaseFirestore.instance
            .collection("track_items")
            .doc(doc.id)
            .collection("monthUsers")
            .doc(currentUserId);

        DocumentSnapshot userDocSnapshot = await userDocRef.get();
        if (userDocSnapshot.exists) {
          _currentMonthDocs.add(doc.id); // Only add if the user document exists
        }
      }).toList();

      // Wait for all checks to complete
      await Future.wait(checks);
      // Sort the months
      _currentMonthDocs.sort();

      // Get the current month
      String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
      currentMonth = currentMonth.replaceAll(' ', '');
      // Compare and navigate if not equal
      if (!_currentMonthDocs.contains(currentMonth)) {
        // A new month has rolled over. The old flow pushed the track-items
        // screen and made the user re-enter every category and budget; the
        // month is now created from last month's, and only a user with
        // nothing to carry forward is sent to pick categories.
        await SpendRepository().ensureMonthInitialised();
        if ((await SpendRepository().trackedCategoryNames()).isEmpty &&
            context.mounted) {
          final next = await MigrationGate.initialRoute(SpendRepository().uid);
          if (context.mounted) context.go(next);
          return;
        }
      }
      setState(() {
        _lastPage = _currentMonthDocs.length - 1;
      });
    } catch (e) {
      print('Error retrieving documents: $e');
    }
  }

  Stream<List<DocumentSnapshot>> _combineStreams() {
    List<Stream<DocumentSnapshot>> streams = _currentMonthDocs.map((month) {
      return FirebaseFirestore.instance
          .collection("track_items")
          .doc(month)
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .snapshots();
    }).toList();

    return Rx.combineLatestList(streams);
  }

  // Future<void> _getTrackItems() async {
  //   try {
  //     for (String currentMonth in _currentMonthDocs) {
  //       FirebaseFirestore.instance
  //           .collection("track_items")
  //           .doc(currentMonth)
  //           .collection("monthUsers")
  //           .doc(FirebaseAuth.instance.currentUser!.uid)
  //           .snapshots()
  //           .listen((userDoc) {
  //         if (userDoc.exists && userDoc.data() != null) {
  //           setState(() {
  //             _data[currentMonth] = userDoc.data() as Map<String, dynamic>;
  //           });
  //         } else {
  //           setState(() {
  //             _data[currentMonth] = {};
  //           });
  //         }
  //       });
  //     }
  //   } catch (e) {
  //     print('Error retrieving user track items: $e');
  //   }
  // }

  String _formatNumber(double number) {
    final formatter = NumberFormat('#,###.##');
    return formatter.format(number);
  }

  void _initializeCurrentMonth() {
    String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    _currentMonth = currentMonth.replaceAll(' ', '');
  }

  int _getMonthIndex(String monthYear) {
    const List<String> monthOrder = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    String month = monthYear.substring(0, monthYear.length - 4);
    return monthOrder.indexOf(month);
  }

  int _getYear(String monthYear) {
    return int.parse(monthYear.substring(monthYear.length - 4));
  }

  void _sortMonthYear(List<String> monthYearList) {
    monthYearList.sort((a, b) {
      int yearA = _getYear(a);
      int yearB = _getYear(b);
      int monthIndexA = _getMonthIndex(a);
      int monthIndexB = _getMonthIndex(b);

      if (yearA == yearB) {
        return monthIndexA.compareTo(monthIndexB);
      }
      return yearA.compareTo(yearB);
    });
  }

  Future<TimeOfDay?> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    return picked;
  }

  String formatTimeOfDay(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    final format = DateFormat.jm(); // 'jm' is a format for 'hh:mm a'
    return format.format(dt);
  }

  Future<void> _scheduleUserNotification(BuildContext context) async {
    // Prompt user to pick a time
    TimeOfDay? selectedTime = await _selectTime(context);
    if (selectedTime != null) {
      // A daily digest with the month's real figures, replacing the fixed-text
      // reminder that used to say "This is your scheduled notification".
      await PendingNotifications.scheduleDigest(selectedTime);
      String formattedTime = formatTimeOfDay(selectedTime);
      snack(context, 'Daily summary set for $formattedTime');
    }
  }

  _scheduleNotificationAlert() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Schedule Notification'),
          titleTextStyle: TextStyle(
            color: Colors.black54,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          content: SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            width: double.infinity,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    "Your SMS is now connected and"
                    " your spending is tracked automatically,"
                    " so you can enjoy a more relaxed experience.",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  "  To keep everything up to date, "
                  "it's important to regularly check the app to review your spending."
                  " We recommend setting a daily notification to remind you to open the"
                  " app and ensure your spending is accurately tracked."
                  " This way, you can stay on top of any unexpected charges or deductions"
                  " and keep your budget on track.",
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _scheduleUserNotification(context).then((v) {
                  Navigator.pop(context);
                });
                prefs.setBool('setNotify', true);
              },
              child: Text('Okay!'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                prefs.setBool('setNotify', true);
              },
              child: Text('Later'),
            ),
          ],
        );
      },
    );
  }

  _manuallyUpdateDailySpend() async {
    try {
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
          .collection("track_items")
          .doc(
            _currentMonthDataNotifier.value,
          ) // Replace with actual month identifier
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .get();

      if (documentSnapshot.exists) {
        Map<String, dynamic> data =
            documentSnapshot.data() as Map<String, dynamic>;
        List<dynamic> listItems = data['listItems'];

        bool foundSpend = false;
        for (var item in listItems) {
          if (item['dailySpend'] != null && item['dailySpend'] > 0) {
            foundSpend = true;
            break;
          } else {
            foundSpend = false;
          }
        }
        _updateDailySpend.value = foundSpend; // Update ValueNotifier
      }
    } catch (e) {
      print('Error: $e');
    }
  }
  // _removeListItem(int index)async{
  //   List listItems;
  //   try{
  //     String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
  //     currentMonth = currentMonth.replaceAll(' ', '');
  //     DocumentSnapshot documentSnapshot = await
  //     FirebaseFirestore.instance
  //         .collection("track_items")
  //         .doc(currentMonth)
  //         .collection("monthUsers")
  //         .doc(FirebaseAuth.instance.currentUser!.uid).get();
  //     listItems = documentSnapshot.get('listItems');
  //     listItems.removeAt(index);
  //     await FirebaseFirestore.instance
  //         .collection("track_items")
  //         .doc(currentMonth)
  //         .collection("monthUsers")
  //         .doc(FirebaseAuth.instance.currentUser!.uid)
  //         .update({
  //       'listItems': listItems,  // Set the updated list
  //     });
  //   }catch(e){
  //     print(e.toString());
  //   }
  // }

  /// Offers to send the shape of alerts the parser could not read.
  ///
  /// Reachable from inside the app, not only from the screen that blocks the
  /// way in. Somebody whose bank half works -- most alerts read, one format
  /// not -- never sees that screen at all, and they are exactly the person
  /// whose missing format is worth having.
  Future<void> _offerToShareFormat() async {
    final found = await SmsInbox.unreadableAlerts();
    if (!mounted) return;
    if (found.bodies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Every bank message here is already being read.'),
        ),
      );
      return;
    }
    await showShareFormatSheet(
      context,
      bodies: found.bodies,
      senders: found.senders,
    );
  }

  /// Signing out, behind a name and a confirmation.
  ///
  /// It used to be an unlabelled arrow glyph sitting beside the inbox icon --
  /// the most destructive control on the screen, one tap from the most used
  /// one, with nothing on it to say which was which.
  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text(
          'Are you sure you want to sign out of this account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const SignInPage()),
              );
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadNeedsSorting() async {
    try {
      final repo = SpendRepository();
      final count = await repo.pendingCount();
      final untagged = await repo.pendingTagCount();
      final unseen = await UnseenActivity.load();
      if (mounted) {
        setState(() {
          _needsSorting = count;
          _untagged = untagged;
          _unseen = unseen;
        });
        await _deliverNudge(unseen);
      }
    } catch (_) {
      // An extra; never let it break the screen.
    }
  }

  /// Says something once, when a budget the user has already walked past
  /// collects more spending.
  ///
  /// Delivered here rather than where the transaction is recorded, because
  /// the app is usually not open when money moves and a message nobody is
  /// there to read is not a message. Once per budget per run of unseen
  /// spending: the marker itself carries the news after that, and a reminder
  /// that repeats is a reminder people learn to ignore.
  Future<void> _deliverNudge(UnseenTally tally) async {
    if (tally.pendingNudge.isEmpty) return;
    final names = tally.pendingNudge.toList();
    await UnseenActivity.clearNudges();
    if (!mounted) return;
    setState(() => _unseen = tally.nudged());

    HapticFeedback.mediumImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          names.length == 1
              ? 'More spending went into one of your budgets. Worth a look.'
              : 'More spending went into ${names.length} of your budgets. '
                    'Worth a look.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// One line, for when marking each budget would light the whole screen.
  Widget _unseenSummary() {
    if (_unseen.total == 0 || _unseen.markIndividually) {
      return const SizedBox.shrink();
    }
    final n = _unseen.total;
    final where = _unseen.marked.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xff5AA5E2).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: Color(0xff5AA5E2),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                '$n new payment${n == 1 ? '' : 's'} across $where budgets '
                'since you last looked',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The same banner the summary carries, saying the same thing.
  ///
  /// This screen used to report it as a numeral on an unlabelled white glyph
  /// sitting between a bell and a sign-out button. One fact, two designs, and
  /// the one the user meets first was the one that looked like nothing.
  Widget _sortBanner() {
    if (_needsSorting == 0 && _untagged == 0) return const SizedBox.shrink();
    final needsSorting = _needsSorting > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xff5AA5E2).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await context.push(needsSorting ? '/pending' : '/batchTag');
            await _loadNeedsSorting();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  color: Color(0xff5AA5E2),
                  size: 19,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    needsSorting
                        ? '$_needsSorting payment'
                              '${_needsSorting == 1 ? '' : 's'} need sorting'
                        : '$_untagged more places to sort',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    // TODO: implement initState
    _initializeCurrentMonth();
    _prepare();
    super.initState();
  }

  /// Everything that has to settle before the page is worth showing.
  ///
  /// The scan rewrites this month's totals, so drawing first and scanning
  /// afterwards meant the figures changed under the user a second or two in.
  /// The two-second delay that used to sit in front of it is gone -- it was
  /// pure waiting.
  Future<void> _prepare() async {
    // The scan is started at launch and nothing here waits on it. It used to
    // be awaited before this screen would render, which made the screen the
    // only thing that scanned -- so an account that opens to the summary was
    // never scanned at all.
    BackgroundScan.startOnce();

    await _getAllCurrentMonthDocs();
    await _loadNeedsSorting();

    if (!mounted) return;
    setState(() {
      _preparing = false;
    });

    // Asked separately, because the scan is no longer the thing that reports
    // it. Cheap, and it is the one outcome the user has to act on.
    if (!await Permission.sms.isGranted && mounted) {
      snack(
        context,
        'Your SMS is required for the tracking process. Please enable SMS permissions in the app settings.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_preparing) return const ScanningView();

    _sortMonthYear(_currentMonthDocs);
    if (_currentMonthDocs.isNotEmpty) {
      setState(() {
        _currentMonthDataNotifier.value = _currentMonthDocs.last;
      });
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: _currentMonthDocs.isNotEmpty
          ? Stack(
              children: [
                Container(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height * 0.4,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(32),
                      bottomRight: Radius.circular(32),
                    ),
                    color: Color(0xff5AA5E2),
                  ),
                  child: StreamBuilder<List<DocumentSnapshot>>(
                    stream: _combineStreams(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text('No data available'));
                      }
                      List<DocumentSnapshot> documents = snapshot.data!;
                      return ValueListenableBuilder<String>(
                        valueListenable: _currentMonthDataNotifier,
                        builder: (context, currentMonthData, child) {
                          return CarouselSlider.builder(
                            options: CarouselOptions(
                              // This month, not this month and slivers of two
                              // others. At 0.7 the neighbours were wide enough to
                              // compete with the figure the screen exists to show.
                              viewportFraction: 0.86,
                              aspectRatio: 16 / 9,
                              height: MediaQuery.of(context).size.width * 0.43,
                              autoPlay: false,
                              initialPage: _lastPage,
                              enableInfiniteScroll: false,
                              enlargeCenterPage: true,
                              onPageChanged: (index, reason) {
                                _currentMonthDataNotifier.value =
                                    _currentMonthDocs[index];
                                _manuallyUpdateDailySpend();
                                _monthData =
                                    documents[index].data()
                                        as Map<String, dynamic>;
                              },
                            ),
                            itemCount: documents.length,
                            itemBuilder: (BuildContext context, int index, int realIndex) {
                              String month = _currentMonthDocs[index];

                              //Map<String, dynamic> monthData = _data[month] ?? {};
                              DocumentSnapshot document = documents[index];
                              Map<String, dynamic> monthData =
                                  document.data() as Map<String, dynamic>;

                              return Center(
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height:
                                          MediaQuery.of(context).size.width *
                                          0.12,
                                    ),
                                    Text(
                                      '${monthData['currency']} ${_formatNumber(monthData['monthlySpend'])}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 17,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.only(top: 10.0),
                                      child: Text(
                                        month == _currentMonth
                                            ? 'spent this month'
                                            : monthData['currentMonthName'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    // What it is measured against. A figure on its
                                    // own says what was spent, never whether that
                                    // was too much.
                                    Builder(
                                      builder: (_) {
                                        final budget = _monthBudget(
                                          monthData['listItems'],
                                        );
                                        if (budget <= 0)
                                          return const SizedBox.shrink();
                                        final spent =
                                            (monthData['monthlySpend'] as num?)
                                                ?.toDouble() ??
                                            0;
                                        final status = BudgetStatus.of(
                                          spent: spent,
                                          budget: budget,
                                        );
                                        return Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            26,
                                            9,
                                            26,
                                            0,
                                          ),
                                          child: Column(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: LinearProgressIndicator(
                                                  value: status.fraction.clamp(
                                                    0.0,
                                                    1.0,
                                                  ),
                                                  minHeight: 5,
                                                  backgroundColor: Colors.white
                                                      .withValues(alpha: 0.28),
                                                  valueColor:
                                                      AlwaysStoppedAnimation(
                                                        status.isOver
                                                            ? const Color(
                                                                0xffFFC9C2,
                                                              )
                                                            : Colors.white,
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                'of ${monthData['currency']} '
                                                '${_formatNumber(budget)} budgeted',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.88),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 35,
                  left: 10,
                  child: IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
                // One control, not three unlabelled white glyphs in a row with
                // sign-out at the end of them. The inbox that used to sit here is
                // gone: it carried the needs-sorting count as a numeral on an icon,
                // and the banner over the list says the same thing in words.
                Positioned(
                  top: 35,
                  right: 10,
                  child: PopupMenuButton<String>(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onSelected: (value) {
                      if (value == 'reminders') {
                        _scheduleNotificationAlert();
                        return;
                      }
                      if (value == 'format') {
                        _offerToShareFormat();
                        return;
                      }
                      _confirmSignOut();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'reminders',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_notifications_outlined,
                              size: 19,
                              color: Colors.black54,
                            ),
                            SizedBox(width: 12),
                            Text('Reminders'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'format',
                        child: Row(
                          children: [
                            Icon(
                              Icons.sms_failed_outlined,
                              size: 19,
                              color: Colors.black54,
                            ),
                            SizedBox(width: 12),
                            Text('Bank not showing up?'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'signout',
                        child: Row(
                          children: [
                            Icon(
                              Icons.exit_to_app,
                              size: 19,
                              color: Colors.black54,
                            ),
                            SizedBox(width: 12),
                            Text('Sign out'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: _updateDailySpend,
                  builder: (context, value, child) {
                    return value == true
                        ? Positioned(
                            bottom: MediaQuery.of(context).size.height * 0.65,
                            right: 30,
                            // A chip, not bare white text floating over the header. It
                            // read as something left in by mistake, which is a poor look
                            // for a control that rewrites the month's total.
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  DailyResets().resetDailySpend(
                                    _currentMonthDataNotifier.value,
                                  );
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.refresh_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Update monthly spend',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Container(); // You can replace Container with any other widget if needed.
                  },
                ),
                Center(
                  child: Column(
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.3,
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.7,
                        width: MediaQuery.of(context).size.width * 0.85,
                        child: ValueListenableBuilder<String>(
                          valueListenable: _currentMonthDataNotifier,
                          builder: (context, docId, child) {
                            if (docId == '') {
                              return StreamWidget(
                                streamValue: _combineStreams(),
                                actualMonthValue: docId,
                              );
                            }
                            return StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection("track_items")
                                  .doc(docId)
                                  .collection("monthUsers")
                                  .doc(FirebaseAuth.instance.currentUser!.uid)
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                if (!snapshot.hasData ||
                                    !snapshot.data!.exists) {
                                  return const Center(
                                    child: Text('No data available'),
                                  );
                                }

                                Map<String, dynamic> monthData =
                                    snapshot.data!.data()
                                        as Map<String, dynamic>;

                                return Column(
                                  children: [
                                    _sortBanner(),
                                    _unseenSummary(),
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount:
                                            monthData['listItems'].length + 1,
                                        itemBuilder: (context, index) {
                                          if (index ==
                                              monthData['listItems'].length) {
                                            return Center(
                                              child: TextButton(
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) {
                                                        // The rebuilt setup screen,
                                                        // not the old one it replaced.
                                                        // `returnOnDone` hands the user
                                                        // back here rather than into
                                                        // the scan and batch screen.
                                                        return const SelectTrackItems(
                                                          returnOnDone: true,
                                                        );
                                                      },
                                                    ),
                                                  );
                                                },
                                                child: const Text(
                                                  'Tap to add more items',
                                                ),
                                              ),
                                            );
                                          }

                                          var listedItems =
                                              monthData['listItems'][index];
                                          double progress = 0;
                                          double maxValue = double.parse(
                                            listedItems['budgetSet'].replaceAll(
                                              ',',
                                              '',
                                            ),
                                          );
                                          // The whole month, today included: totals are
                                          // now derived from the transaction records
                                          // rather than rolled up nightly, so this no
                                          // longer needs dailySpend added to it.
                                          double currentValue =
                                              (listedItems['totalAmountSpent']
                                                      as num?)
                                                  ?.toDouble() ??
                                              0;
                                          progress = (maxValue > 0)
                                              ? (currentValue / maxValue)
                                              : 0.0;
                                          progress = progress.isFinite
                                              ? progress
                                              : 0.0;
                                          // One rule for the colour and the wording,
                                          // shared with the notification, so the card
                                          // and the alert can never disagree.
                                          final status = BudgetStatus.of(
                                            spent: currentValue,
                                            budget: maxValue,
                                          );

                                          // Filed here since the user last
                                          // opened it. Marked only while a
                                          // few budgets carry anything: past
                                          // that the summary line above says
                                          // it once instead.
                                          final categoryId = slugifyCategory(
                                            '${listedItems['name']}',
                                          );
                                          final unseenHere = _unseen.countIn(
                                            categoryId,
                                          );
                                          final marked =
                                              unseenHere > 0 &&
                                              _unseen.markIndividually;

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8.0,
                                            ),
                                            child: Stack(
                                              children: [
                                                GestureDetector(
                                                  onTap: () async {
                                                    // The breakdown clears the
                                                    // marker, not this. It has to
                                                    // read which transactions
                                                    // were unseen *before* they
                                                    // stop being unseen, or the
                                                    // rows it is meant to point
                                                    // at arrive already cleared.
                                                    await Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) {
                                                          return ItemDetails(
                                                            itemDetails:
                                                                listedItems,
                                                            monthDetails:
                                                                monthData,
                                                            actualMonth: docId,
                                                            index: index,
                                                            edit: true,
                                                          );
                                                        },
                                                      ),
                                                    );
                                                    await _loadNeedsSorting();
                                                  },
                                                  child: AnimatedContainer(
                                                    duration: const Duration(
                                                      milliseconds: 260,
                                                    ),
                                                    padding:
                                                        const EdgeInsets.all(
                                                          12,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            18,
                                                          ),
                                                      color: Colors.white,
                                                      // A quiet outline rather
                                                      // than a filled alarm: it
                                                      // has to read at a glance
                                                      // without making the whole
                                                      // screen look broken.
                                                      //
                                                      // Uniform, and it has to
                                                      // stay uniform. A rounded
                                                      // corner on a border that
                                                      // differs side to side is
                                                      // rejected outright, and
                                                      // the card paints as an
                                                      // empty white box -- which
                                                      // is exactly what a rail
                                                      // drawn as a left border
                                                      // did. The rail is a
                                                      // separate widget below.
                                                      border: Border.all(
                                                        color:
                                                            _statusColour(
                                                              status.level,
                                                            ).withValues(
                                                              alpha:
                                                                  status.level ==
                                                                      BudgetLevel
                                                                          .ok
                                                                  ? 0
                                                                  : 0.55,
                                                            ),
                                                        width: 1.4,
                                                      ),
                                                    ),
                                                    child: Column(
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                listedItems['image'] !=
                                                                        ""
                                                                    ? SvgPicture.asset(
                                                                        listedItems['image'],
                                                                        height:
                                                                            20,
                                                                      )
                                                                    : Text(
                                                                        listedItems['name'][0],
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              20,
                                                                          color:
                                                                              Colors.black54,
                                                                          fontWeight:
                                                                              FontWeight.w600,
                                                                        ),
                                                                      ),
                                                                const SizedBox(
                                                                  width: 30,
                                                                ),
                                                                Text(
                                                                  listedItems['name'],
                                                                ),
                                                                // How many, not
                                                                // merely that
                                                                // there are some.
                                                                // "Something
                                                                // happened here"
                                                                // is a reason to
                                                                // look; "three
                                                                // payments" is a
                                                                // reason to look
                                                                // now.
                                                                if (marked) ...[
                                                                  const SizedBox(
                                                                    width: 9,
                                                                  ),
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          3,
                                                                    ),
                                                                    decoration: BoxDecoration(
                                                                      color: const Color(
                                                                        0xff2E5BFF,
                                                                      ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            20,
                                                                          ),
                                                                    ),
                                                                    child: Text(
                                                                      unseenHere ==
                                                                              1
                                                                          ? '1 new'
                                                                          : '$unseenHere new',
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            10.5,
                                                                        height:
                                                                            1.1,
                                                                        fontWeight:
                                                                            FontWeight.w800,
                                                                        color: Colors
                                                                            .white,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 10,
                                                        ),
                                                        ProgressIndicatorWidget(
                                                          currentValue:
                                                              currentValue,
                                                          maxValue: maxValue,
                                                          progress: progress,
                                                          currency:
                                                              monthData['currency'],
                                                        ),
                                                        if (status.level !=
                                                            BudgetLevel.ok) ...[
                                                          const SizedBox(
                                                            height: 10,
                                                          ),
                                                          Row(
                                                            children: [
                                                              Icon(
                                                                status.isOver
                                                                    ? Icons
                                                                          .error_outline
                                                                    : Icons
                                                                          .info_outline_rounded,
                                                                size: 15,
                                                                color:
                                                                    _statusColour(
                                                                      status
                                                                          .level,
                                                                    ),
                                                              ),
                                                              const SizedBox(
                                                                width: 6,
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  // The figures, not just
                                                                  // the fact: "over
                                                                  // budget" alone says
                                                                  // there is a problem
                                                                  // without saying how
                                                                  // big it is.
                                                                  status.describe(
                                                                    '${monthData['currency'] ?? ''}',
                                                                  ),
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        12.5,
                                                                    height:
                                                                        1.35,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: _statusColour(
                                                                      status
                                                                          .level,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                        const SizedBox(
                                                          height: 15,
                                                        ),
                                                        const Divider(),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                // The rail. Its own widget,
                                                // over the card rather than
                                                // part of its border, so the
                                                // card keeps its rounded
                                                // corners and its status
                                                // outline and the two markers
                                                // never fight over one
                                                // border.
                                                if (marked)
                                                  Positioned(
                                                    left: 0,
                                                    top: 14,
                                                    bottom: 22,
                                                    child: Container(
                                                      width: 4,
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xff2E5BFF,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              3,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: CircularProgressIndicator(),
                  ),
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.9,
                    child: Text(
                      'Make sure you have stable internet connection',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
