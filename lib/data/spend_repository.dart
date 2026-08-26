import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../parsing/bank_alert.dart';
import '../parsing/category_matcher.dart';
import 'budget_status.dart';
import 'currency_setup.dart';
import 'migration_plan.dart';
import 'onboarding_gate.dart';
import 'models.dart';
import 'pending_notifications.dart';

/// Reads and writes the per-user schema under `Users/{uid}`.
class SpendRepository {
  SpendRepository({FirebaseFirestore? db, String? uid})
      : db = db ?? FirebaseFirestore.instance,
        uid = uid ?? FirebaseAuth.instance.currentUser!.uid;

  final FirebaseFirestore db;
  final String uid;

  Map<String, CounterpartyEntry>? _map;

  /// The counterparty map, loaded once per repository instance.
  ///
  /// A scan processes many messages, and re-reading the map for each one would
  /// turn one read into dozens.
  Future<Map<String, CounterpartyEntry>> counterparties() async =>
      _map ??= await loadCounterparties();

  DocumentReference<Map<String, dynamic>> get _user =>
      db.collection('Users').doc(uid);

  CollectionReference<Map<String, dynamic>> get _counterparties =>
      _user.collection('counterparties');

  DocumentReference<Map<String, dynamic>> monthRef(String monthKey) =>
      _user.collection('months').doc(monthKey);

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  Future<List<Category>> loadCategories() async {
    final snap = await _user.collection('categories').get();
    return snap.docs
        .map((d) => Category(
              id: d.data()['id'] ?? d.id,
              name: d.data()['name'] ?? d.id,
              image: d.data()['image'],
              active: d.data()['active'] ?? true,
            ))
        .toList();
  }

  /// Every category the picker should offer.
  ///
  /// Unions the two places a category can live: the `categories` collection,
  /// and the legacy month document's `listItems` that the home screen renders
  /// from. They are written together by [startTracking], but nothing enforces
  /// that they stay in step -- a month carried forward writes `listItems`
  /// only, and a migration that half-completed leaves `categories` empty.
  ///
  /// When they disagreed the picker showed nothing but "My own account" and
  /// "New category", so a user with six tracked categories could not file a
  /// transaction into any of them. Deriving from both means the list is empty
  /// only when the user genuinely tracks nothing.
  Future<List<Category>> pickerCategories() async {
    final byId = <String, Category>{};

    for (final c in await loadCategories()) {
      if (c.active) byId[c.id] = c;
    }

    final items = (await _legacyMonth.get()).data()?['listItems'];
    if (items is List) {
      for (final raw in items) {
        if (raw is! Map || raw['name'] == null) continue;
        final name = raw['name'].toString();
        final id = slugifyCategory(name);
        // The collection wins on name and image where it has an entry; this
        // only fills in what is missing from it.
        byId.putIfAbsent(
            id,
            () => Category(
                  id: id,
                  name: name,
                  image: (raw['image'] ?? '').toString(),
                ));
      }
    }

    final out = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<Map<String, CounterpartyEntry>> loadCounterparties() async {
    final snap = await _counterparties.get();
    final out = <String, CounterpartyEntry>{};
    for (final d in snap.docs) {
      final m = d.data();
      final key = (m['key'] ?? d.id).toString();
      out[key] = CounterpartyEntry(
        key: key,
        categoryId: m['categoryId'],
        disposition: Disposition.values.firstWhere(
          (v) => v.name == m['disposition'],
          orElse: () => Disposition.ask,
        ),
        overrideCount: (m['overrideCount'] ?? 0) as int,
        txCount: (m['txCount'] ?? 0) as int,
        creditCount: (m['creditCount'] ?? 0) as int,
        roundAmounts: (m['roundAmounts'] ?? 0) as int,
        aliases: List<String>.from(m['aliases'] ?? const []),
      );
    }
    return out;
  }

  /// The legacy month document, which is still what the app displays.
  DocumentReference<Map<String, dynamic>> get _legacyMonth {
    final key = DateFormat('MMMM yyyy').format(DateTime.now()).replaceAll(' ', '');
    return db
        .collection('track_items')
        .doc(key)
        .collection('monthUsers')
        .doc(uid);
  }

  /// This month's categories with the budgets already set against them.
  ///
  /// Needed because carrying a category into a new month without its figure
  /// is only half the job: the setup screen listed last month's categories
  /// with empty budgets, so the user had to retype every one before the
  /// button would enable. That is the work carrying them forward was meant
  /// to remove.
  Future<Map<String, String>> trackedItemsWithBudgets() async {
    final items = (await _legacyMonth.get()).data()?['listItems'];
    if (items is! List) return {};
    return {
      for (final raw in items)
        if (raw is Map && raw['name'] != null)
          raw['name'].toString(): (raw['budgetSet'] ?? '').toString(),
    };
  }

  /// This month's total budget, across every category.
  Future<double> totalBudget() async {
    var total = 0.0;
    for (final b in (await trackedItemsWithBudgets()).values) {
      total += double.tryParse(b.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    }
    return total;
  }

  /// Names of the categories being tracked *this month*.
  ///
  /// Read from the legacy document rather than the new schema: the category
  /// screens still write only to `track_items`, so it is the one place
  /// guaranteed to be current.
  Future<Set<String>> trackedCategoryNames() async {
    final items = (await _legacyMonth.get()).data()?['listItems'];
    if (items is! List) return {};
    return {
      for (final raw in items)
        if (raw is Map && raw['name'] != null) raw['name'].toString(),
    };
  }

  /// Creates this month's document if it is not there yet.
  ///
  /// The track-items screen used to be the only thing that wrote it, so
  /// deleting that screen would have left new users -- and anyone rolling into
  /// a new month -- with no document for the app to render from.
  ///
  /// Two things it must get right:
  ///  * The parent `track_items/{month}` doc. A subcollection document does
  ///    not make its parent appear in a collection listing, and the home
  ///    screen finds the current month by listing that collection -- so
  ///    without this the month is invisible and the user gets bounced.
  ///  * Existing data. Called on every launch, so it writes only when the
  ///    document is absent; a blind merge would reset `monthlySpend` and drop
  ///    the month's `messageId` list each time.
  ///
  /// Returns true when a month was created, false when one already existed.
  Future<bool> ensureMonthInitialised({List<Map<String, dynamic>>? carryOver}) async {
    final existing = await _legacyMonth.get();
    if (existing.exists && existing.data()?['listItems'] != null) return false;

    final now = DateTime.now();
    final monthKey = DateFormat('MMMM yyyy').format(now).replaceAll(' ', '');

    // Rules allow this document to carry nothing but `dummy`; it exists purely
    // so the month shows up when the collection is listed.
    await db.collection('track_items').doc(monthKey).set({'dummy': null});

    // A new month inherits last month's categories and budgets. Making the
    // user re-enter all of them every month was the old screen's job and the
    // main reason it felt redundant.
    final items = carryOver ?? await _previousMonthItems(now);

    await _legacyMonth.set({
      'listItems': items,
      'monthlySpend': 0.0,
      'currency': await _currencyForNewMonth(),
      'currentMonthName': DateFormat.MMMM().format(now),
      'messageId': <dynamic>[],
    }, SetOptions(merge: true));

    // Mirror the carried-over budgets into the new schema so the derived
    // totals have something to measure against from the first transaction.
    if (items.isNotEmpty) {
      await monthRef(monthKeyOf(now)).set({
        'budgets': {
          for (final item in items)
            slugifyCategory(item['name'].toString()):
                double.tryParse(
                        item['budgetSet'].toString().replaceAll(RegExp(r'[^0-9.]'), '')) ??
                    0,
        }
      }, SetOptions(merge: true));
    }
    return true;
  }

  /// Last month's categories, with their budgets kept and their spending
  /// zeroed. Empty for a brand-new user, who picks from the catalogue instead.
  Future<List<Map<String, dynamic>>> _previousMonthItems(DateTime now) async {
    try {
      final prev = DateTime(now.year, now.month - 1);
      final key = DateFormat('MMMM yyyy').format(prev).replaceAll(' ', '');
      final snap = await db
          .collection('track_items')
          .doc(key)
          .collection('monthUsers')
          .doc(uid)
          .get();
      final items = snap.data()?['listItems'];
      if (items is! List) return [];
      return [
        for (final raw in items)
          if (raw is Map && raw['name'] != null)
            {
              'image': raw['image'] ?? '',
              'name': raw['name'],
              'description': '',
              'dailySpend': 0.0,
              'budgetSet': raw['budgetSet'] ?? '0',
              'totalAmountSpent': 0.0,
              'currentMonth': DateFormat.MMMM().format(now),
              'previousDailySpends': <dynamic>[],
              'lastResetTime': Timestamp.now(),
            },
      ];
    } catch (_) {
      return [];
    }
  }

  /// The symbol for a month being created: whatever a previous month used, or
  /// a fresh lookup for a user who has never had one.
  Future<String> _currencyForNewMonth() async {
    try {
      final months = await db.collection('track_items').get();
      for (final m in months.docs) {
        final snap =
            await m.reference.collection('monthUsers').doc(uid).get();
        final symbol = snap.data()?['currency']?.toString();
        if (symbol != null && symbol.isNotEmpty) return symbol;
      }
    } catch (_) {
      // Fall through to detection.
    }
    return CurrencySetup.detectSymbol();
  }

  /// Starts tracking [name] for the current month.
  ///
  /// Writes to both schemas: the legacy list the app renders from, and the
  /// new categories plus this month's budget. Without the legacy write the
  /// category would be invisible until the cutover.
  Future<Category> startTracking({
    required String name,
    // Required, with no default. A category without a budget cannot be
    // measured against anything, and the details screen renders it as unset.
    // Defaulting this to '0' is how budgetless categories got created before.
    required String budget,
    String image = '',
  }) async {
    final category = Category.fromName(name, image: image);

    // Guarantees the month document and its parent exist before the category
    // is appended to them.
    await ensureMonthInitialised();

    // Written by hand rather than with arrayUnion.
    //
    // arrayUnion only skips a value it already holds *identically*, and these
    // are maps carrying a budget: tracking "Family" at ₦10,000 and again at
    // ₦5,000 produced two different maps and therefore two Family rows, both
    // pointing at the same category id. The home screen showed the category
    // twice while only one of them counted.
    await db.runTransaction((tx) async {
      final snap = await tx.get(_legacyMonth);
      final items = List<dynamic>.from(snap.data()?['listItems'] ?? const []);

      final at = items.indexWhere((i) =>
          i is Map &&
          i['name'] != null &&
          slugifyCategory(i['name'].toString()) == category.id);

      final entry = {
        'image': image,
        'name': name,
        'description': '',
        'dailySpend': 0.0,
        'budgetSet': budget,
        'totalAmountSpent': 0.0,
        'currentMonth': DateFormat.MMMM().format(DateTime.now()),
        'previousDailySpends': <dynamic>[],
        'lastResetTime': Timestamp.now(),
      };

      if (at >= 0) {
        // Already tracked: this is a change of budget, not a second category.
        // Spending is preserved -- the money is real whatever the plan says.
        final existing = Map<String, dynamic>.from(items[at] as Map);
        existing['budgetSet'] = budget;
        if (image.isNotEmpty) existing['image'] = image;
        items[at] = existing;
      } else {
        items.add(entry);
      }

      tx.set(_legacyMonth, {'listItems': items}, SetOptions(merge: true));
    });

    await _user
        .collection('categories')
        .doc(category.id)
        .set(category.toMap(), SetOptions(merge: true));

    await monthRef(monthKeyOf(DateTime.now())).set({
      'budgets': {
        category.id: double.tryParse(budget.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0
      }
    }, SetOptions(merge: true));

    return category;
  }

  /// The currency symbol the user's month was set up with.
  Future<String> currencySymbol() async =>
      (await _legacyMonth.get()).data()?['currency']?.toString() ?? '';

  /// Transactions in [monthKey] still waiting for the user to say what they
  /// were, newest first.
  Future<List<TransactionRecord>> pendingTransactions({String? monthKey}) async {
    final snap = await monthRef(monthKey ?? monthKeyOf(DateTime.now()))
        .collection('transactions')
        .where('status', isEqualTo: TxnStatus.pending.name)
        .get();

    final rows = snap.docs.map((d) {
      final m = d.data();
      return TransactionRecord(
        smsId: d.id,
        bank: m['bank'] ?? '',
        kind: AlertKind.debit,
        channel: TxnChannel.values.firstWhere(
            (v) => v.name == m['channel'], orElse: () => TxnChannel.unknown),
        status: TxnStatus.pending,
        amount: (m['amount'] as num?)?.toDouble(),
        occurredAt: DateTime.tryParse(m['occurredAt'] ?? ''),
        narration: m['narration'] ?? '',
        counterpartyKey: m['counterpartyKey'],
      );
    }).toList();

    rows.sort((a, b) => (b.occurredAt ?? DateTime(0))
        .compareTo(a.occurredAt ?? DateTime(0)));
    return rows;
  }

  Future<int> pendingCount({String? monthKey}) async =>
      (await pendingTransactions(monthKey: monthKey)).length;

  /// Live count of transactions still awaiting an answer.
  ///
  /// A read-once count goes stale the moment one is sorted on another screen,
  /// which is how the summary ended up showing figures the home screen had
  /// already moved past.
  Stream<int> watchPendingCount({String? monthKey}) =>
      monthRef(monthKey ?? monthKeyOf(DateTime.now()))
          .collection('transactions')
          .where('status', isEqualTo: TxnStatus.pending.name)
          .snapshots()
          .map((s) => s.docs.length);

  /// The categories to offer as one-tap answers on a notification.
  ///
  /// Android allows three action buttons, so this returns the three the user
  /// spends most through -- the likeliest answers, and they adapt as habits
  /// change. Only categories actually tracked this month are offered: a button
  /// that files money somewhere invisible would be worse than no button.
  Future<List<Category>> quickPickCategories({int limit = 3}) async {
    final items = (await _legacyMonth.get()).data()?['listItems'];
    if (items is! List) return const [];

    final ranked = <MapEntry<String, double>>[];
    for (final raw in items) {
      if (raw is! Map || raw['name'] == null) continue;
      final spent = (raw['totalAmountSpent'] as num?)?.toDouble() ?? 0;
      final daily = (raw['dailySpend'] as num?)?.toDouble() ?? 0;
      ranked.add(MapEntry(raw['name'].toString(), spent + daily));
    }
    ranked.sort((a, b) => b.value.compareTo(a.value));

    return [
      for (final e in ranked.take(limit)) Category.fromName(e.key),
    ];
  }

  /// Files a single transaction, and everything else waiting on the same name.
  ///
  /// [alsoRemember] upserts the counterparty so the next transaction from them
  /// files itself. Answering from a notification always remembers; correcting
  /// a one-off might not.
  ///
  /// Returns how many *other* transactions were settled alongside this one.
  Future<int> labelTransaction({
    required String smsId,
    required String categoryId,
    required String categoryName,
    String? counterpartyKey,
    bool alsoRemember = true,
    String? monthKey,
  }) async {
    final key = monthKey ?? monthKeyOf(DateTime.now());
    final month = monthRef(key);
    final txRef = month.collection('transactions').doc(smsId);

    final amount = await db.runTransaction<double>((tx) async {
      final snap = await tx.get(txRef);
      if (!snap.exists) return 0;
      if (snap.data()?['status'] != TxnStatus.pending.name) return 0;
      final value = (snap.data()?['amount'] as num?)?.toDouble() ?? 0;
      tx.update(txRef, {
        'status': TxnStatus.labeled.name,
        'categoryId': categoryId,
        'source': LabelSource.user.name,
      });
      tx.set(month, {'spend': {categoryId: FieldValue.increment(value)}},
          SetOptions(merge: true));
      return value;
    });

    if (amount == 0) return 0; // already answered elsewhere

    await rebuildCurrentMonthTotals();

    // Teaching the map from a single transaction is right when the key
    // identifies one place, and wrong when it identifies a rail.
    //
    // `PAYSTACK CHECKOUT` is the case that matters: it is a payment
    // processor, and a dozen unrelated merchants hide behind it. Filing one
    // ₦21,400 purchase as Transfers and remembering it would send every
    // future Paystack payment to Transfers, whatever it was actually for --
    // silently, and across every merchant that happens to use them.
    //
    // The batch screen never faces this because `batchTagCandidates` filters
    // these keys out. This screen shows individual transactions, so they
    // reach it.
    final ambiguousKey =
        counterpartyKey != null && isInstitutionOnlyKey(counterpartyKey);

    if (alsoRemember && counterpartyKey != null && !ambiguousKey) {
      await _counterparties.doc(counterpartyDocId(counterpartyKey)).set({
        'key': counterpartyKey,
        'categoryId': categoryId,
        'disposition': Disposition.tracked.name,
      }, SetOptions(merge: true));
      _map = null;

      // And everything else already waiting on that same name.
      //
      // Remembering the answer but leaving the other four transfers to the
      // same person sitting in the list is the rule written down and not
      // applied: the user is told the next payment files itself, then made
      // to answer for four that are already here.
      final also = await _settlePending(
        key: counterpartyKey,
        disposition: Disposition.tracked,
        categoryId: categoryId,
        monthKey: key,
      );
      if (also > 0) await rebuildCurrentMonthTotals();
      return also;
    }
    return 0;
  }

  /// How many counterparties are still worth putting in front of the user.
  Future<int> pendingTagCount({int limit = 20}) async => batchTagCandidates(
        await loadCounterparties(),
        limit: limit,
        trackedCategories: await trackedCategoryNames(),
      ).length;

  /// Recomputes this month's totals from the transaction records.
  ///
  /// This is the cutover. Totals are **derived**, never accumulated: the
  /// records are the single source of truth and the legacy document becomes a
  /// projection of them. Double-counting stops being a bug that can happen --
  /// running this twice produces the same answer, because it is a sum rather
  /// than an increment.
  ///
  /// It also retires the daily reset. `dailySpend` was maintained by a nightly
  /// job that zeroed it and rolled it into `totalAmountSpent`; both are now
  /// filtered out of the same records, so a missed or repeated run cannot skew
  /// anything.
  ///
  /// Deliberately current-month only. Closed months hold totals copied at
  /// migration and have no transaction records, so rebuilding them from an
  /// empty set would erase history the user has already seen.
  Future<double> rebuildCurrentMonthTotals() async {
    final key = monthKeyOf(DateTime.now());
    final snap =
        await monthRef(key).collection('transactions').get();

    final now = DateTime.now();
    final byCategory = <String, double>{};
    final todayByCategory = <String, double>{};
    var monthTotal = 0.0;

    for (final d in snap.docs) {
      final m = d.data();
      if (m['status'] != TxnStatus.labeled.name) continue;
      final categoryId = m['categoryId'] as String?;
      if (categoryId == null) continue;

      final amount = (m['amount'] as num?)?.toDouble() ?? 0;
      byCategory[categoryId] = (byCategory[categoryId] ?? 0) + amount;
      monthTotal += amount;

      final when = DateTime.tryParse(m['occurredAt'] ?? '');
      if (when != null &&
          when.year == now.year &&
          when.month == now.month &&
          when.day == now.day) {
        todayByCategory[categoryId] =
            (todayByCategory[categoryId] ?? 0) + amount;
      }
    }

    await db.runTransaction((tx) async {
      final legacy = await tx.get(_legacyMonth);
      if (!legacy.exists) return;
      final items = List<dynamic>.from(legacy.data()?['listItems'] ?? const []);
      for (final item in items) {
        if (item is! Map || item['name'] == null) continue;
        final id = slugifyCategory(item['name'].toString());
        // totalAmountSpent is now the whole month, today included -- it is no
        // longer "what the reset has rolled up so far".
        item['totalAmountSpent'] = byCategory[id] ?? 0.0;
        item['dailySpend'] = todayByCategory[id] ?? 0.0;
      }
      tx.update(_legacyMonth,
          {'listItems': items, 'monthlySpend': monthTotal});
    });

    await monthRef(key).set({'spend': byCategory}, SetOptions(merge: true));
    await _warnOnNewlyOverBudget(key, byCategory);
    return monthTotal;
  }

  /// Notifies about categories that have just gone past their budget.
  ///
  /// Runs off the totals rebuild because that is the one place every path
  /// converges -- a tag, a scan, a correction. Fires once per category per
  /// month: the month document remembers which have already been announced,
  /// so a user who keeps spending in an over-budget category is told once
  /// rather than on every transaction.
  ///
  /// Never throws into the caller. A failed notification must not take a
  /// totals rebuild down with it.
  Future<void> _warnOnNewlyOverBudget(
      String monthKey, Map<String, double> byCategory) async {
    try {
      final month = await monthRef(monthKey).get();
      final data = month.data() ?? const <String, dynamic>{};
      final budgets = Map<String, dynamic>.from(data['budgets'] ?? const {});
      if (budgets.isEmpty) return;

      final announced =
          Set<String>.from(data['overBudgetNotified'] ?? const <String>[]);

      final names = {
        for (final c in await pickerCategories()) c.id: c.name,
      };
      final currency = await currencySymbol();

      final freshlyOver = <String>[];
      for (final entry in budgets.entries) {
        final budget = (entry.value as num?)?.toDouble() ?? 0;
        if (budget <= 0) continue;
        final spent = byCategory[entry.key] ?? 0;
        final status = BudgetStatus.of(spent: spent, budget: budget);

        if (!status.isOver) {
          // Dropping back under -- an correction, a re-tag -- clears the mark
          // so crossing again is announced again.
          announced.remove(entry.key);
          continue;
        }
        if (announced.contains(entry.key)) continue;

        announced.add(entry.key);
        freshlyOver.add(entry.key);
        await PendingNotifications.showOverBudget(
          categoryId: entry.key,
          categoryName: names[entry.key] ?? 'A category',
          spent: spent,
          budget: budget,
          currency: currency,
        );
      }

      final stored =
          Set<String>.from(data['overBudgetNotified'] ?? const <String>[]);
      if (freshlyOver.isNotEmpty || announced.length != stored.length) {
        await monthRef(monthKey)
            .set({'overBudgetNotified': announced.toList()},
                SetOptions(merge: true));
      }
    } catch (e) {
      // ignore: avoid_print
      print('Budget warning failed: $e');
    }
  }

  /// Labelled transactions filed under [categoryId] this month, newest first.
  ///
  /// Queried on `categoryId` alone and filtered in memory: adding `status`
  /// would require a composite index, which is a console step this avoids.
  Future<List<TransactionRecord>> transactionsForCategory(
    String categoryId, {
    String? monthKey,
  }) async {
    final snap = await monthRef(monthKey ?? monthKeyOf(DateTime.now()))
        .collection('transactions')
        .where('categoryId', isEqualTo: categoryId)
        .get();

    final rows = <TransactionRecord>[];
    for (final d in snap.docs) {
      final m = d.data();
      if (m['status'] != TxnStatus.labeled.name) continue;
      rows.add(TransactionRecord(
        smsId: d.id,
        bank: m['bank'] ?? '',
        kind: AlertKind.debit,
        channel: TxnChannel.values.firstWhere((v) => v.name == m['channel'],
            orElse: () => TxnChannel.unknown),
        status: TxnStatus.labeled,
        amount: (m['amount'] as num?)?.toDouble(),
        occurredAt: DateTime.tryParse(m['occurredAt'] ?? ''),
        narration: m['narration'] ?? '',
        counterpartyKey: m['counterpartyKey'],
        categoryId: categoryId,
      ));
    }
    rows.sort((a, b) =>
        (b.occurredAt ?? DateTime(0)).compareTo(a.occurredAt ?? DateTime(0)));
    return rows;
  }

  /// Who fed a category this month, and how much each accounted for.
  Future<List<({String key, int count, double total})>> contributorsTo(
    String categoryId, {
    String? monthKey,
  }) async {
    final txns = await transactionsForCategory(categoryId, monthKey: monthKey);
    final count = <String, int>{}, total = <String, double>{};
    for (final t in txns) {
      final k = t.counterpartyKey ?? t.narration;
      count[k] = (count[k] ?? 0) + 1;
      total[k] = (total[k] ?? 0) + (t.amount ?? 0);
    }
    final rows = [
      for (final k in count.keys)
        (key: k, count: count[k]!, total: total[k]!),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return rows;
  }

  /// Moves a counterparty from one category to another.
  ///
  /// [moveHistory] distinguishes the two things a user can mean. False means
  /// "from now on it's X": only the map changes, and spending already recorded
  /// stays where it was. True means "this was always X": the current month's
  /// transactions move across too. Closed months are never rewritten -- those
  /// are numbers the user has already seen.
  Future<int> switchCounterparty({
    required String key,
    required String toCategoryId,
    required String toCategoryName,
    required bool moveHistory,
    String? monthKey,
  }) async {
    await _counterparties.doc(counterpartyDocId(key)).set({
      'key': key,
      'categoryId': toCategoryId,
      'disposition': Disposition.tracked.name,
      // A deliberate switch is a fresh decision, so the correction counter
      // starts again rather than counting toward the give-up threshold.
      'overrideCount': 0,
    }, SetOptions(merge: true));
    _map = null;

    if (!moveHistory) return 0;

    final mKey = monthKey ?? monthKeyOf(DateTime.now());
    final month = monthRef(mKey);
    final entry = (await counterparties())[key];
    final keys = <String>{key, ...?entry?.aliases}.take(30).toList();

    final snap = await month
        .collection('transactions')
        .where('counterpartyKey', whereIn: keys)
        .get();

    final moving = snap.docs
        .where((d) => d.data()['status'] == TxnStatus.labeled.name)
        .where((d) => d.data()['categoryId'] != toCategoryId)
        .toList();
    if (moving.isEmpty) return 0;

    final batch = db.batch();
    final out = <String, double>{};
    var movedTotal = 0.0;

    for (final d in moving) {
      final amount = (d.data()['amount'] as num?)?.toDouble() ?? 0;
      final from = d.data()['categoryId'] as String?;
      if (from != null) out[from] = (out[from] ?? 0) + amount;
      movedTotal += amount;
      batch.update(d.reference, {'categoryId': toCategoryId});
    }

    batch.set(
        month,
        {
          'spend': {
            for (final e in out.entries) e.key: FieldValue.increment(-e.value),
            toCategoryId: FieldValue.increment(movedTotal),
          }
        },
        SetOptions(merge: true));

    await batch.commit();

    await rebuildCurrentMonthTotals();
    return moving.length;
  }

  /// Refiles one transaction, and remembers that the map got it wrong.
  ///
  /// Repeated corrections for the same counterparty push it back to
  /// [Disposition.ask]: if the user keeps overruling a mapping, guessing
  /// silently is worse than asking.
  /// Moves one transaction.
  ///
  /// [remember] decides whether this is a rule or an exception, and they are
  /// genuinely different things. Moving *Chowdeck* to Snacks says where that
  /// place belongs; moving one ₦50,000 payment to a person you usually buy
  /// lunch from says that payment was rent, and says nothing about the next
  /// one.
  ///
  /// Defaults to an exception, because that is what a per-transaction move
  /// means. Rules are set from the counterparty view, which asks the question
  /// properly.
  Future<void> correctTransaction({
    required TransactionRecord txn,
    required String toCategoryId,
    required String toCategoryName,
    bool remember = false,
    String? monthKey,
  }) async {
    if (txn.categoryId == toCategoryId) return;
    final month = monthRef(monthKey ?? monthKeyOf(DateTime.now()));
    final amount = txn.amount ?? 0;

    final batch = db.batch();
    batch.update(month.collection('transactions').doc(txn.smsId), {
      'categoryId': toCategoryId,
      'source': LabelSource.user.name,
    });
    batch.set(
        month,
        {
          'spend': {
            if (txn.categoryId != null)
              txn.categoryId!: FieldValue.increment(-amount),
            toCategoryId: FieldValue.increment(amount),
          }
        },
        SetOptions(merge: true));
    await batch.commit();

    await rebuildCurrentMonthTotals();

    final key = txn.counterpartyKey;
    if (key == null) return;
    final entry = resolveKey(await counterparties(), key);
    if (entry == null) return;

    final overrides = entry.overrideCount + 1;
    final givingUp = overrides >= CounterpartyEntry.overrideLimit;

    if (!remember) {
      // An exception, so where future payments go is left alone.
      //
      // The count still rises. Marking a third exception for the same
      // counterparty is the user saying, three times, that the rule does not
      // fit -- at which point continuing to file it automatically is the app
      // insisting on an answer it has been told is wrong.
      await _counterparties.doc(counterpartyDocId(entry.key)).set({
        'overrideCount': overrides,
        if (givingUp) ...{
          'disposition': Disposition.ask.name,
          'categoryId': null,
        },
      }, SetOptions(merge: true));
      _map = null;
      return;
    }

    // A correction teaches, it does not merely register a complaint.
    //
    // This used to count the override and stop, so moving a payment from
    // Family to Food changed that one row and left the app still convinced
    // the counterparty was Family -- and the next payment went back there.
    // Meanwhile moving a whole category *did* repoint them, so the same
    // gesture at two scales did two different things.
    //
    // The counter still matters, but for the case it was written for:
    // somebody who keeps changing their mind about a counterparty does not
    // have a stable answer, and after enough goes the app stops guessing and
    // asks instead.
    await _counterparties.doc(counterpartyDocId(entry.key)).set({
      'overrideCount': overrides,
      if (givingUp) ...{
        'disposition': Disposition.ask.name,
        'categoryId': null,
      } else ...{
        'disposition': Disposition.tracked.name,
        'categoryId': toCategoryId,
      },
    }, SetOptions(merge: true));
    _map = null;
  }

  /// The figures behind the daily digest.
  ///
  /// Read at the moment the notification fires rather than when it was
  /// scheduled, so it reports the day it is actually sent.
  Future<({double spent, double budget, int pending, double unsorted})>
      dailyDigest() async {
    final legacy = (await _legacyMonth.get()).data();
    final items = legacy?['listItems'];

    var budget = 0.0;
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        budget += double.tryParse(item['budgetSet']
                    ?.toString()
                    .replaceAll(RegExp(r'[^0-9.]'), '') ??
                '') ??
            0;
      }
    }

    final pending = await pendingTransactions();
    return (
      spent: (legacy?['monthlySpend'] as num?)?.toDouble() ?? 0,
      budget: budget,
      pending: pending.length,
      unsorted: pending.fold<double>(0, (s, t) => s + (t.amount ?? 0)),
    );
  }

  /// Gives a budget to any tracked category that has none.
  ///
  /// One-off cleanup for categories created before a budget was required.
  /// `budgetSet: "0"` leaves them half-configured -- the details screen shows
  /// "No budget set for this item" and refuses to open its sections.
  ///
  /// The figure is derived from what has actually been spent rather than
  /// picked at random, so it starts somewhere plausible; the user can edit it
  /// in the normal place.
  Future<String> backfillMissingBudgets() async {
    final snap = await _legacyMonth.get();
    if (!snap.exists) return 'no month document';

    final items = List<dynamic>.from(snap.data()?['listItems'] ?? const []);
    final fixed = <String>[];

    for (final item in items) {
      if (item is! Map) continue;
      final current = item['budgetSet']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
      if (current.isNotEmpty && (int.tryParse(current) ?? 0) > 0) continue;

      final spent = (item['totalAmountSpent'] as num?)?.toDouble() ?? 0;
      // Round up to the next 5,000, with a 10,000 floor, so a category that
      // has already been spent against does not start over budget.
      final target = spent <= 0
          ? 20000
          : ((spent * 1.2) / 5000).ceil() * 5000;
      final budget = target < 10000 ? 10000 : target;

      item['budgetSet'] = NumberFormat('#,###').format(budget);
      fixed.add('${item['name']}=${item['budgetSet']}');
    }

    if (fixed.isEmpty) return 'all categories already have budgets';
    await _legacyMonth.update({'listItems': items});

    // Keep the new schema's copy in step.
    final budgets = <String, double>{};
    for (final item in items) {
      if (item is! Map || item['name'] == null) continue;
      budgets[slugifyCategory(item['name'].toString())] = double.tryParse(
              item['budgetSet'].toString().replaceAll(RegExp(r'[^0-9.]'), '')) ??
          0;
    }
    await monthRef(monthKeyOf(DateTime.now()))
        .set({'budgets': budgets}, SetOptions(merge: true));

    return 'set budgets: ${fixed.join(', ')}';
  }

  /// Undoes labels that point at a category which is not being tracked.
  ///
  /// Backing out of the budget sheet used to label the transaction anyway, so
  /// it left the sorting list and was credited to a category with no entry in
  /// the month -- the amount then appeared nowhere at all. This finds those,
  /// puts them back to pending, and takes the amount off the category total.
  ///
  /// Counterparties pointing at the same category are reset to
  /// [Disposition.ask] as well; otherwise the next transaction from them would
  /// silently repeat the whole thing.
  ///
  /// Returns a short summary for logging.
  Future<String> repairOrphanedLabels({String? monthKey}) async {
    final key = monthKey ?? monthKeyOf(DateTime.now());
    final month = monthRef(key);

    final trackedNames = (await trackedCategoryNames())
        .map((n) => n.toLowerCase())
        .toSet();
    final trackedIds = {
      for (final c in await loadCategories())
        if (trackedNames.contains(c.name.toLowerCase())) c.id,
    };

    final snap = await month
        .collection('transactions')
        .where('status', isEqualTo: TxnStatus.labeled.name)
        .get();

    final orphaned = snap.docs.where((d) {
      final id = d.data()['categoryId'];
      return id != null && !trackedIds.contains(id);
    }).toList();

    if (orphaned.isEmpty) return 'nothing to repair';

    final batch = db.batch();
    final refunds = <String, double>{};
    final keysToReset = <String>{};

    for (final d in orphaned) {
      final data = d.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      final categoryId = data['categoryId'] as String;
      refunds[categoryId] = (refunds[categoryId] ?? 0) + amount;
      if (data['counterpartyKey'] != null) {
        keysToReset.add(data['counterpartyKey'] as String);
      }
      batch.update(d.reference, {
        'status': TxnStatus.pending.name,
        'categoryId': null,
        'source': null,
      });
    }

    batch.set(
        month,
        {
          'spend': refunds
              .map((k, v) => MapEntry(k, FieldValue.increment(-v))),
        },
        SetOptions(merge: true));

    for (final k in keysToReset) {
      batch.set(_counterparties.doc(counterpartyDocId(k)), {
        'categoryId': null,
        'disposition': Disposition.ask.name,
      }, SetOptions(merge: true));
    }

    await batch.commit();
    _map = null;
    return 'restored ${orphaned.length} transactions, '
        'reset ${keysToReset.length} counterparties';
  }

  /// Records that the user has saved or skipped the batch-tag screen, so it
  /// is not shown again on every launch.
  /// The account holder's name.
  ///
  /// Prefers the auth profile, falls back to the Firestore record. The
  /// fallback is what makes this work for accounts created before the profile
  /// was being set: every one of them already has `firstName` and `lastName`,
  /// so nothing has to be migrated for surname matching to start working.
  ///
  /// Cached per repository instance; it cannot change mid-session.
  String? _ownerName;
  bool _ownerNameLoaded = false;

  Future<String?> ownerName() async {
    if (_ownerNameLoaded) return _ownerName;
    _ownerNameLoaded = true;
    try {
      final profile = FirebaseAuth.instance.currentUser?.displayName;
      if (profile != null && profile.trim().isNotEmpty) {
        return _ownerName = profile.trim();
      }
      final doc = (await _user.get()).data();
      final parts = [doc?['firstName'], doc?['lastName']]
          .whereType<String>()
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.isEmpty) return _ownerName = null;

      final name = parts.join(' ');
      // Written back so the auth profile is right from here on, and anything
      // reading `displayName` directly stops coming up empty.
      try {
        await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
      } catch (_) {/* the value is already in hand */}
      return _ownerName = name;
    } catch (_) {
      return _ownerName = null;
    }
  }

  /// Whether the user has confirmed their budgets for the current month.
  ///
  /// A new month carries last month's categories and figures forward, which
  /// is the right default and the wrong place to stop: budgets are the one
  /// thing worth a second look when the month turns, and silently reusing
  /// August's plan for September means nobody ever revisits it.
  ///
  /// So the setup screen is shown once per month, arriving fully filled in.
  /// Confirming is one tap; changing anything is as easy as it was the first
  /// time.
  Future<bool> budgetsConfirmedThisMonth() async {
    try {
      final key = DateFormat('MMMM yyyy').format(DateTime.now())
          .replaceAll(' ', '');
      return (await _user.get()).data()?['budgetsConfirmedFor'] == key;
    } catch (_) {
      // Never trap the user on a setup screen because a read failed.
      return true;
    }
  }

  Future<void> markBudgetsConfirmed() async {
    final key =
        DateFormat('MMMM yyyy').format(DateTime.now()).replaceAll(' ', '');
    await _user.set({'budgetsConfirmedFor': key}, SetOptions(merge: true));
  }

  /// Records that the how-it-works screen has been read.
  Future<void> markIntroSeen() =>
      _user.set({'introSeen': true}, SetOptions(merge: true));

  /// Records that the user has closed the batch screen.
  ///
  /// Called by both buttons. Done and Skip mean the same thing here -- the
  /// screen has been dealt with and should stop being volunteered -- and the
  /// summary's "more places to sort" banner keeps it reachable for anyone who
  /// wants another round.
  ///
  /// The cache is updated first so the decision holds even if the write is
  /// still in flight when the screen closes.
  Future<void> markBatchTagDismissed() async {
    OnboardingGate.markDismissed(uid);
    await _user.set({
      'batchTagDismissed': true,
      // Kept for the record; nothing routes on it any more.
      'batchTagSeen': true,
    }, SetOptions(merge: true));
  }

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  /// Records one parsed alert and moves the month's totals.
  ///
  /// Idempotent by construction: the transaction document is keyed by the SMS
  /// id, and the totals are only advanced when that document did not already
  /// exist. Re-scanning the inbox therefore cannot double-count, which matters
  /// because the periodic task re-reads the same messages every two hours.
  /// Returns the record written, or null if this SMS was already counted.
  Future<TransactionRecord?> recordTransaction({
    required String smsId,
    required BankAlert alert,
    required Map<String, CounterpartyEntry> map,
  }) async {
    final record = recordFor(
      smsId,
      alert,
      map,
      source: LabelSource.map,
      suggestedCategoryId: await _dictionarySuggestion(alert),
    );
    final month = monthRef(monthKeyOf(alert.occurredAt ?? DateTime.now()));
    final txRef = month.collection('transactions').doc(smsId);
    final amount = record.amount ?? 0;

    final written = await db.runTransaction<bool>((tx) async {
      final existing = await tx.get(txRef);
      if (existing.exists) return false; // already counted
      tx.set(txRef, record.toMap());

      if (record.countsAsSpending && record.categoryId != null) {
        tx.set(
            month,
            {
              'spend': {record.categoryId!: FieldValue.increment(amount)}
            },
            SetOptions(merge: true));
      } else if (alert.kind == AlertKind.charge) {
        // Visible to the user, deliberately outside every budget.
        tx.set(month, {'charges': FieldValue.increment(amount)},
            SetOptions(merge: true));
      } else if (alert.kind == AlertKind.debit &&
          record.status == TxnStatus.excluded) {
        // Money moved between the user's own accounts.
        tx.set(month, {'excluded': FieldValue.increment(amount)},
            SetOptions(merge: true));
      }
      return true;
    });

    return written ? record : null;
  }

  /// A category id for a recognised merchant, or null.
  ///
  /// Restricted to categories the user actually tracks this month: guessing a
  /// category they do not have would file the money somewhere with nothing on
  /// screen to show it.
  Future<String?> _dictionarySuggestion(BankAlert alert) async {
    if (alert.kind != AlertKind.debit) return null;
    // The canonical spelling where one is known, since truncated variants all
    // resolve to it; the raw key otherwise.
    final key = resolveKey(await counterparties(), alert.counterpartyKey)?.key ??
        alert.counterpartyKey;
    if (key == null) return null;

    // The full matcher, not the merchant list alone. A transaction arriving
    // from a bank alert was being matched only against known brand names,
    // while the batch screen had the lexicon, the surname rule and the
    // truncation handling -- so the same counterparty was placed on one
    // screen and left pending on the other.
    final guess = guessCategory(
      key,
      await trackedCategoryNames(),
      ownerName: await ownerName(),
      channelHint: alert.channel == TxnChannel.airtime ? 'airtime' : null,
    );
    // Only a category that exists. A suggestion to create one is a decision
    // for the user, not something to apply while they are not looking.
    if (guess == null || guess.categoryName.isEmpty) return null;
    if (guess.confidence < CategoryGuess.floor) return null;
    return slugifyCategory(guess.categoryName);
  }

  /// How many transactions are filed under [categoryId], across every month.
  Future<int> transactionCountFor(String categoryId) async {
    var n = 0;
    final months = await _user.collection('months').get();
    for (final m in months.docs) {
      final snap = await m.reference
          .collection('transactions')
          .where('categoryId', isEqualTo: categoryId)
          .get();
      n += snap.docs.length;
    }
    return n;
  }

  /// Moves every transaction from one category to another.
  ///
  /// The alternative to opening each one and re-filing it. A user who decides
  /// that "Others" was the wrong home for forty payments should not have to
  /// say so forty times.
  ///
  /// Counterparties pointing at the old category are repointed too, so the
  /// next payment to the same place follows the transactions rather than
  /// going back to a category the user has abandoned.
  Future<int> moveCategoryTransactions({
    required String fromCategoryId,
    required String toCategoryId,
    required String toCategoryName,
  }) async {
    var moved = 0;
    final months = await _user.collection('months').get();
    for (final m in months.docs) {
      final snap = await m.reference
          .collection('transactions')
          .where('categoryId', isEqualTo: fromCategoryId)
          .get();
      if (snap.docs.isEmpty) continue;

      final batch = db.batch();
      for (final d in snap.docs) {
        batch.update(d.reference, {
          'categoryId': toCategoryId,
          'categoryName': toCategoryName,
        });
      }
      await batch.commit();
      moved += snap.docs.length;
    }

    final counterparties = await _counterparties.get();
    final batch = db.batch();
    for (final d in counterparties.docs) {
      if (d.data()['categoryId'] != fromCategoryId) continue;
      batch.update(d.reference, {'categoryId': toCategoryId});
    }
    await batch.commit();
    _map = null;

    await rebuildCurrentMonthTotals();
    return moved;
  }

  /// Removes a category.
  ///
  /// The old delete edited the legacy list and stopped there, which left the
  /// transactions still pointing at it. The money disappeared from view while
  /// staying in the totals -- a category the user cannot see and cannot
  /// correct, quietly counted.
  ///
  /// [deleteTransactions] is destructive and irreversible: the records are
  /// gone and the only way back is for the bank alert to be read again, which
  /// will not happen for messages already scanned. Without it the
  /// transactions return to the pending list, where the user can re-file them.
  Future<void> deleteCategory({
    required String categoryId,
    required String categoryName,
    required bool deleteTransactions,
  }) async {
    final months = await _user.collection('months').get();
    for (final m in months.docs) {
      final snap = await m.reference
          .collection('transactions')
          .where('categoryId', isEqualTo: categoryId)
          .get();
      if (snap.docs.isEmpty) continue;

      final batch = db.batch();
      for (final d in snap.docs) {
        if (deleteTransactions) {
          batch.delete(d.reference);
        } else {
          // Back to the pending list rather than orphaned: the money is real
          // and still needs a home.
          batch.update(d.reference, {
            'status': TxnStatus.pending.name,
            'categoryId': null,
            'categoryName': null,
            'source': null,
          });
        }
      }
      await batch.commit();
      await m.reference.set({
        'budgets': {categoryId: FieldValue.delete()},
        'spend': {categoryId: FieldValue.delete()},
      }, SetOptions(merge: true));
    }

    // Counterparties must forget it too, or the next payment refiles into a
    // category that no longer exists.
    final counterparties = await _counterparties.get();
    final batch = db.batch();
    for (final d in counterparties.docs) {
      if (d.data()['categoryId'] != categoryId) continue;
      batch.update(d.reference,
          {'categoryId': null, 'disposition': Disposition.ask.name});
    }
    await batch.commit();
    _map = null;

    await _user.collection('categories').doc(categoryId).delete();

    // The legacy list the home screen renders from.
    final legacy = await _legacyMonth.get();
    final items = List<dynamic>.from(legacy.data()?['listItems'] ?? const []);
    items.removeWhere((i) =>
        i is Map &&
        i['name'] != null &&
        slugifyCategory(i['name'].toString()) == categoryId);
    await _legacyMonth.set({'listItems': items}, SetOptions(merge: true));

    await rebuildCurrentMonthTotals();
  }

  /// Merges categories that were tracked twice.
  ///
  /// `arrayUnion` let the same category in more than once when the budget
  /// differed, so the home screen listed it twice while only one counted.
  /// Fixing the write stops it recurring; this clears what is already there,
  /// keeping the largest budget on the assumption that the later, higher
  /// figure was the intended one.
  ///
  /// Returns how many duplicates were removed.
  Future<int> mergeDuplicateCategories() async {
    final snap = await _legacyMonth.get();
    final items = List<dynamic>.from(snap.data()?['listItems'] ?? const []);
    if (items.length < 2) return 0;

    final byId = <String, Map<String, dynamic>>{};
    var removed = 0;

    for (final raw in items) {
      if (raw is! Map || raw['name'] == null) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = slugifyCategory(item['name'].toString());
      final existing = byId[id];
      if (existing == null) {
        byId[id] = item;
        continue;
      }

      removed++;
      double budgetOf(Map<String, dynamic> m) =>
          double.tryParse(
              '${m['budgetSet']}'.replaceAll(RegExp(r'[^0-9.]'), '')) ??
          0;
      if (budgetOf(item) > budgetOf(existing)) {
        existing['budgetSet'] = item['budgetSet'];
      }
      if ('${existing['image'] ?? ''}'.isEmpty) {
        existing['image'] = item['image'] ?? '';
      }
    }

    if (removed == 0) return 0;
    await _legacyMonth
        .set({'listItems': byId.values.toList()}, SetOptions(merge: true));
    await rebuildCurrentMonthTotals();
    return removed;
  }

  /// Un-files transfers the user made between their own accounts.
  ///
  /// Moving money from your own current account to your own savings is not
  /// spending, but a bug let the account holder's own name through as a
  /// relative -- the guard demanded an exact match on every name part, and
  /// banks print middle names that a signup form does not. Sixty-nine
  /// transfers to himself were counted against a Family budget.
  ///
  /// Fixing the guard stops it recurring; it does not undo what is already
  /// filed. This does, and it has to reach *labelled* rows, which the normal
  /// settle path deliberately leaves alone.
  ///
  /// Returns how many transactions were released.
  Future<int> repairSelfTransfers() async {
    final owner = await ownerName();
    if (owner == null || owner.trim().isEmpty) return 0;

    final map = await loadCounterparties();
    final mine = map.values
        .where((e) => looksLikeOwnAccount(e.key, owner))
        .toList();
    if (mine.isEmpty) return 0;

    // Every spelling, including the truncated ones merged into each entry --
    // records written before canonicalisation carry the short form.
    final keys = <String>{
      for (final e in mine) ...[e.key, ...e.aliases],
    };

    for (final e in mine) {
      await _counterparties.doc(counterpartyDocId(e.key)).set({
        'key': e.key,
        'categoryId': null,
        'disposition': Disposition.notSpending.name,
      }, SetOptions(merge: true));
    }
    _map = null;

    var released = 0;
    final months = await _user.collection('months').get();
    for (final month in months.docs) {
      // `whereIn` caps at 30, so the keys are queried in chunks.
      final chunks = <List<String>>[];
      final all = keys.toList();
      for (var i = 0; i < all.length; i += 30) {
        chunks.add(all.sublist(i, i + 30 > all.length ? all.length : i + 30));
      }

      for (final chunk in chunks) {
        final snap = await month.reference
            .collection('transactions')
            .where('counterpartyKey', whereIn: chunk)
            .get();
        final stale = snap.docs
            .where((d) => d.data()['status'] != TxnStatus.excluded.name)
            .toList();
        if (stale.isEmpty) continue;

        final batch = db.batch();
        for (final d in stale) {
          batch.update(d.reference, {
            'status': TxnStatus.excluded.name,
            'categoryId': null,
            'source': null,
          });
        }
        await batch.commit();
        released += stale.length;
      }
    }

    // Totals are derived from the records, so this is what makes the money
    // actually leave the category on screen.
    if (released > 0) await rebuildCurrentMonthTotals();
    return released;
  }

  /// Applies a decision about a counterparty and settles the transactions
  /// already waiting on it.
  ///
  /// Used by the batch-tag screen and, later, by the per-transaction prompt.
  Future<int> tagCounterparty({
    required String key,
    required Disposition disposition,
    String? categoryId,
    String? monthKey,
  }) async {
    await _counterparties.doc(counterpartyDocId(key)).set({
      'key': key,
      'categoryId': categoryId,
      'disposition': disposition.name,
      'lastSeen': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    _map = null; // later writes must see this decision
    return _settlePending(
      key: key,
      disposition: disposition,
      categoryId: categoryId,
      monthKey: monthKey ?? monthKeyOf(DateTime.now()),
    );
  }

  /// Labels the pending transactions for [key] in one month.
  ///
  /// Queried on `counterpartyKey` alone and filtered in memory: a second
  /// equality clause on `status` would require a composite index, which is a
  /// console step this does not need.
  Future<int> _settlePending({
    required String key,
    required Disposition disposition,
    required String? categoryId,
    required String monthKey,
  }) async {
    final month = monthRef(monthKey);

    // Records written before keys were canonicalised carry a truncated
    // spelling, so match the aliases as well or those stay pending forever.
    final entry = (await counterparties())[key];
    final keys = <String>{key, ...?entry?.aliases}.take(30).toList();

    final snap = await month
        .collection('transactions')
        .where('counterpartyKey', whereIn: keys)
        .get();

    final pending = snap.docs
        .where((d) => d.data()['status'] == TxnStatus.pending.name)
        .toList();
    if (pending.isEmpty) return 0;

    final batch = db.batch();
    final increments = <String, double>{};
    var excluded = 0.0;

    for (final d in pending) {
      final amount = (d.data()['amount'] as num?)?.toDouble() ?? 0;
      if (disposition == Disposition.tracked && categoryId != null) {
        batch.update(d.reference, {
          'status': TxnStatus.labeled.name,
          'categoryId': categoryId,
          'source': LabelSource.user.name,
        });
        increments[categoryId] = (increments[categoryId] ?? 0) + amount;
      } else if (disposition == Disposition.notSpending) {
        batch.update(d.reference, {'status': TxnStatus.excluded.name});
        excluded += amount;
      }
    }

    if (increments.isNotEmpty || excluded > 0) {
      batch.set(
          month,
          {
            if (increments.isNotEmpty)
              'spend': increments
                  .map((k, v) => MapEntry(k, FieldValue.increment(v))),
            if (excluded > 0) 'excluded': FieldValue.increment(excluded),
          },
          SetOptions(merge: true));
    }

    await batch.commit();

    // Totals are derived from the records, so the screens pick this up
    // without anything being nudged by hand.
    await rebuildCurrentMonthTotals();

    return pending.length;
  }

  /// Mirrors a legacy write into the new schema.
  ///
  /// Called alongside the existing `track_items` write for one release, so the
  /// old collection stays correct and current and remains a working rollback
  /// path while the new schema is proven in production.
  Future<TransactionRecord?> mirrorLegacyWrite({
    required String smsId,
    required BankAlert? alert,
  }) async {
    if (alert == null) return null;
    try {
      return await recordTransaction(
          smsId: smsId, alert: alert, map: await counterparties());
    } catch (e) {
      // The legacy write is still the source of truth this release, so a
      // failure here must never break the user's tracking.
      // ignore: avoid_print
      print('mirror write failed for $smsId: $e');
      return null;
    }
  }
}
