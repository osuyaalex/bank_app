import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../parsing/bank_alert.dart';
import '../parsing/merchant_dictionary.dart';
import 'migration_plan.dart';
import 'models.dart';

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

    await _legacyMonth.set({
      'listItems': FieldValue.arrayUnion([
        {
          'image': image,
          'name': name,
          'description': '',
          'dailySpend': 0.0,
          'budgetSet': budget,
          'totalAmountSpent': 0.0,
          'currentMonth': DateFormat.MMMM().format(DateTime.now()),
          'previousDailySpends': <dynamic>[],
          'lastResetTime': Timestamp.now(),
        }
      ]),
    }, SetOptions(merge: true));

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

  /// Files a single transaction, moving both schemas.
  ///
  /// [alsoRemember] upserts the counterparty so the next transaction from them
  /// files itself. Answering from a notification always remembers; correcting
  /// a one-off might not.
  Future<void> labelTransaction({
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

    if (amount == 0) return; // already answered elsewhere

    await rebuildCurrentMonthTotals();

    if (alsoRemember && counterpartyKey != null) {
      await _counterparties.doc(counterpartyDocId(counterpartyKey)).set({
        'key': counterpartyKey,
        'categoryId': categoryId,
        'disposition': Disposition.tracked.name,
      }, SetOptions(merge: true));
      _map = null;
    }
  }

  /// How many counterparties are still worth putting in front of the user.
  Future<int> pendingTagCount({int limit = 20}) async =>
      batchTagCandidates(await loadCounterparties(), limit: limit).length;

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
    return monthTotal;
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
  Future<void> correctTransaction({
    required TransactionRecord txn,
    required String toCategoryId,
    required String toCategoryName,
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
    await _counterparties.doc(counterpartyDocId(entry.key)).set({
      'overrideCount': overrides,
      if (overrides >= CounterpartyEntry.overrideLimit)
        'disposition': Disposition.ask.name,
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
  Future<void> markBatchTagSeen() =>
      _user.set({'batchTagSeen': true}, SetOptions(merge: true));

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
    final key = alert.counterpartyKey;
    if (key == null || alert.kind != AlertKind.debit) return null;

    final name = suggestCategoryName(key, await trackedCategoryNames());
    return name == null ? null : slugifyCategory(name);
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
