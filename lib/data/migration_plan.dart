import '../parsing/bank_alert.dart';
import '../parsing/category_matcher.dart';
import 'models.dart';

/// Pure transformations that compute what the migration will write.
///
/// Kept free of Firestore so the logic can be exercised against a real SMS
/// corpus before it is ever pointed at live user data.

const _monthNames = [
  'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december',
];

/// Converts the legacy document id (`August2026`) to the new key (`2026-08`).
///
/// Returns null for ids that do not follow the old format, so the migration
/// can skip them rather than invent a month.
String? legacyMonthKey(String legacyId) {
  final m = RegExp(r'^([A-Za-z]+)\s*(\d{4})$').firstMatch(legacyId.trim());
  if (m == null) return null;
  final idx = _monthNames.indexOf(m.group(1)!.toLowerCase());
  if (idx < 0) return null;
  return '${m.group(2)}-${(idx + 1).toString().padLeft(2, '0')}';
}

/// `2026-08` for a given date.
String monthKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  // Legacy budgets were stored as display strings, e.g. "20,000".
  return double.tryParse(v.toString().replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
}

/// Merges `listItems` from every legacy month into one set of definitions.
///
/// Categories are identified by name, since that is all the old schema had.
/// The most recent icon wins, so a category the user re-styled keeps its
/// latest look.
List<Category> categoriesFromLegacy(Iterable<List<dynamic>> monthlyListItems) {
  final byId = <String, Category>{};
  for (final items in monthlyListItems) {
    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw as Map);
      final name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final c = Category.fromName(name, image: item['image']?.toString());
      byId[c.id] = c; // later months overwrite earlier ones
    }
  }
  return byId.values.toList();
}

/// Copies one legacy month across verbatim.
///
/// Totals are preserved exactly as recorded, never recomputed: these are
/// numbers the user has already seen, and correcting history silently would
/// be worse than carrying a small inaccuracy forward.
MonthLedger ledgerFromLegacy(String monthKey, List<dynamic> listItems,
    {required bool closed}) {
  final budgets = <String, double>{}, spend = <String, double>{};
  for (final raw in listItems) {
    final item = Map<String, dynamic>.from(raw as Map);
    final name = (item['name'] ?? '').toString().trim();
    if (name.isEmpty) continue;
    final id = slugifyCategory(name);
    budgets[id] = _toDouble(item['budgetSet']);
    spend[id] = _toDouble(item['totalAmountSpent']);
  }
  return MonthLedger(
      month: monthKey, budgets: budgets, spend: spend, closed: closed);
}

/// Builds the initial counterparty map from parsed history.
///
/// Every entry starts at [Disposition.ask]; nothing is auto-categorised on the
/// strength of a guess. Keys that name an institution stay at `ask` for good,
/// and keys that look like the user's own account are proposed as
/// [Disposition.notSpending] for them to confirm.
Map<String, CounterpartyEntry> seedCounterparties(
  Iterable<BankAlert> alerts, {
  String? ownerName,
}) {
  final out = <String, CounterpartyEntry>{};
  for (final a in alerts) {
    final key = a.counterpartyKey;
    // Debits only. Money arriving does not belong in a map whose purpose is
    // categorising spending, and seeding from credits fills the batch screen
    // with people who send the user money.
    if (key == null || a.kind != AlertKind.debit) continue;

    final existing = out[key];
    final seen = a.occurredAt;
    final proposed = looksLikeOwnAccount(key, ownerName)
        ? Disposition.notSpending
        : Disposition.ask;

    out[key] = CounterpartyEntry(
      key: key,
      isMerchant: (existing?.isMerchant ?? false) ||
          a.channel == TxnChannel.pos ||
          a.channel == TxnChannel.web,
      disposition: existing?.disposition ?? proposed,
      txCount: (existing?.txCount ?? 0) + 1,
      creditCount: existing?.creditCount ?? 0,
      roundAmounts:
          (existing?.roundAmounts ?? 0) + (_isRoundAmount(a.amount) ? 1 : 0),
      totalDebited: (existing?.totalDebited ?? 0) + (a.amount ?? 0),
      lastSeen: (existing?.lastSeen == null ||
              (seen != null && seen.isAfter(existing!.lastSeen!)))
          ? (seen ?? existing?.lastSeen)
          : existing?.lastSeen,
    );
  }

  // A second pass for money coming the other way.
  //
  // Credits deliberately do not *create* entries -- that would fill the batch
  // screen with people who pay the user. They only annotate counterparties
  // already there, because the useful fact is not "this person sent money",
  // it is "money moved both ways with this person", which a shop never does.
  for (final a in alerts) {
    final key = a.counterpartyKey;
    if (key == null || a.kind != AlertKind.credit) continue;
    final existing = out[key];
    if (existing == null) continue;
    out[key] = existing.copyWith(creditCount: existing.creditCount + 1);
  }
  return out;
}

/// Whether an amount is a round figure.
///
/// People send each other round numbers; shops charge what the goods cost.
bool _isRoundAmount(double? amount) {
  if (amount == null || amount <= 0) return false;
  return amount % 500 == 0;
}

/// Ranks counterparties for the sorting flow: biggest spend first, so the
/// smallest number of answers covers the largest share of the user's money.
///
/// It used to rank by transaction count, which is a proxy for the same thing
/// and a bad one. Twelve ₦100 airtime top-ups outrank one ₦400,000 rent
/// payment, so the user answered the trivia first and met the question that
/// actually shapes their month somewhere near the bottom, if they got there.
///
/// Counts remain the tie-break, and remain the whole ordering for anyone
/// whose entries were written before spending was recorded per counterparty:
/// those carry a total of zero, and falling back leaves them exactly as they
/// were rather than shuffling them arbitrarily.
List<CounterpartyEntry> batchTagCandidates(
  Map<String, CounterpartyEntry> map, {
  int limit = 20,
  Iterable<String> trackedCategories = const [],
}) {
  final list = map.values
      // `tracked` is already answered; `notSpending` is proposed separately as
      // a confirmation, not as a category choice.
      .where((e) => e.disposition == Disposition.ask)
      .where((e) => !isInstitutionOnlyKey(e.key))
      // Recognised merchants are deliberately *kept*.
      //
      // They used to be filtered out, on the reasoning that asking about
      // Netflix when the app already knows what Netflix is wastes the user's
      // time. That was right while the only options were "ask" or "hide" --
      // but the screen now arrives with them already filed and ticked, and
      // seeing the work done is worth more than a shorter list. Hiding them
      // meant the user's evidence that anything happened was an absence.
      .toList()
    ..sort((a, b) {
      final byMoney = b.totalDebited.compareTo(a.totalDebited);
      if (byMoney != 0) return byMoney;
      return b.txCount.compareTo(a.txCount);
    });
  return list.take(limit).toList();
}

/// Merges truncated spellings of one counterparty.
///
/// SMS truncation yields `ALEXANDER ADENIYI OSUYA`, `ALEXANDER ADENIYI O` and
/// `ALEXANDER ADENI` for a single person. The longest spelling becomes the
/// key and the shorter ones become aliases, so one answer from the user
/// covers every variant.
///
/// Only prefix relationships are merged, and only from [minPrefix] characters,
/// which keeps distinct names such as ABUBAKAR ALIYU and ABUBAKAR ALH UMMAR
/// apart.
Map<String, CounterpartyEntry> canonicaliseKeys(
  Map<String, CounterpartyEntry> map, {
  int minPrefix = 10,
  int merchantMinPrefix = 6,
}) {
  final keys = map.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length)); // longest first

  final canonical = <String, CounterpartyEntry>{};
  final claimed = <String, String>{}; // alias -> canonical key

  for (final k in keys) {
    if (claimed.containsKey(k)) continue;
    final entry = map[k]!;
    final aliases = <String>[];
    var count = entry.txCount;
    var credits = entry.creditCount;
    var round = entry.roundAmounts;
    var spent = entry.totalDebited;
    var disposition = entry.disposition;

    for (final other in keys) {
      if (other == k || claimed.containsKey(other)) continue;
      // Merchant stems are safe to merge on a shorter prefix: `CHOWDE` is
      // only ever `CHOWDECK`, whereas `MOHAMMED` could be any number of
      // different people.
      final floor = (entry.isMerchant && map[other]!.isMerchant)
          ? merchantMinPrefix
          : minPrefix;
      if (other.length < floor) continue;
      if (!k.startsWith(other)) continue;
      aliases.add(other);
      claimed[other] = k;
      count += map[other]!.txCount;
      credits += map[other]!.creditCount;
      round += map[other]!.roundAmounts;
      spent += map[other]!.totalDebited;
      // A self-transfer detected under any spelling applies to all of them.
      if (map[other]!.disposition == Disposition.notSpending) {
        disposition = Disposition.notSpending;
      }
    }

    canonical[k] = entry.copyWith(
      txCount: count,
      // Merged along with the count: a truncated spelling of the same person
      // carries the same evidence about them.
      creditCount: credits,
      roundAmounts: round,
      // Merged for the same reason as the count: three truncations of one
      // name are one person, and their spending is one figure.
      totalDebited: spent,
      aliases: aliases,
      disposition: disposition,
      isMerchant: entry.isMerchant ||
          aliases.any((a) => map[a]?.isMerchant ?? false),
    );
  }
  return canonical;
}

/// Resolves a freshly parsed key against the map, falling back to aliases so
/// a differently truncated spelling still finds its entry.
CounterpartyEntry? resolveKey(Map<String, CounterpartyEntry> map, String? key) {
  if (key == null) return null;
  final direct = map[key];
  if (direct != null) return direct;
  for (final e in map.values) {
    if (e.aliases.contains(key)) return e;
  }
  return null;
}

/// What each tracked category cost, month by month, across the whole inbox.
///
/// The batch screen is the first moment the app holds a real spending history,
/// and it is also the moment it is about to ask for budgets. This is what lets
/// it stop asking and start proposing.
///
/// Only debits count, and only where the counterparty resolves to a category
/// the user actually tracks: an unfiled transaction says nothing about what a
/// budget should be. Self-transfers and charges are already excluded by the
/// same rules the ledger uses, so the totals here match what the user will see.
///
/// [partialMonths] names the months the figures must not be drawn from -- the
/// month in progress, and the oldest month present, which is only as complete
/// as the phone's SMS retention happened to leave it.
({Map<String, Map<String, double>> byMonth, Set<String> partialMonths})
    monthlyCategoryTotals(
  Iterable<BankAlert> alerts,
  Map<String, CounterpartyEntry> map,
  Set<String> trackedNames,
  DateTime now, {
  String? ownerName,
  Set<String> alsoConsider = const {},
}) {
  final byMonth = <String, Map<String, double>>{};

  for (final a in alerts) {
    if (a.kind != AlertKind.debit) continue;
    if (a.occurredAt == null) continue;
    if (a.amount == null || a.amount! <= 0) continue;
    if (a.isReversal) continue;

    final entry = resolveKey(map, a.counterpartyKey);
    if (entry?.disposition == Disposition.notSpending) continue;

    String? categoryId;
    if (entry?.autoAssigns ?? false) {
      categoryId = entry!.categoryId;
    } else if (a.counterpartyKey != null) {
      // The user's own categories first, and only then the wider set of names
      // the app is able to offer.
      //
      // The order is not cosmetic. The app files transactions by matching
      // against the tracked list alone, so a wider list consulted first would
      // put this money somewhere the app never would -- lunch filed under
      // Food because Food happened to come first among the concepts -- and
      // the history would then disagree with the totals on the home screen.
      //
      // The full matcher, not the merchant list alone: relatives are found by
      // surname and appear in no dictionary of brands, which left Family out
      // of the figures entirely.
      String? name;
      for (final universe in [trackedNames, alsoConsider]) {
        if (universe.isEmpty) continue;
        final guess = guessCategory(
          a.counterpartyKey!,
          universe,
          ownerName: ownerName,
          channelHint: a.channel == TxnChannel.airtime ? 'airtime' : null,
          hourOfDay: a.occurredAt?.hour,
        );
        if (guess != null &&
            guess.categoryName.isNotEmpty &&
            guess.confidence >= CategoryGuess.floor) {
          name = guess.categoryName;
          break;
        }
      }
      if (name != null) categoryId = slugifyCategory(name);
    }
    if (categoryId == null) continue;

    final m = monthKeyOf(a.occurredAt!);
    (byMonth[m] ??= <String, double>{}).update(
        categoryId, (v) => v + a.amount!,
        ifAbsent: () => a.amount!);
  }

  final partial = <String>{monthKeyOf(now)};
  if (byMonth.isNotEmpty) {
    final oldest = byMonth.keys.reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    partial.add(oldest);
  }
  return (byMonth: byMonth, partialMonths: partial);
}

/// Turns a parsed alert into a transaction record.
///
/// [map] decides the outcome: a tracked counterparty labels the row outright,
/// a self-transfer is excluded from the totals, and anything else lands as
/// pending for the user to resolve.
TransactionRecord recordFor(
  String smsId,
  BankAlert alert,
  Map<String, CounterpartyEntry> map, {
  LabelSource source = LabelSource.migration,
  String? suggestedCategoryId,
}) {
  final entry = resolveKey(map, alert.counterpartyKey);

  // Store the canonical key, not the raw one. Truncation means the same person
  // arrives under several spellings; recording the spelling that happened to
  // appear would leave the transaction unreachable when the user later tags
  // the merged counterparty.
  final key = entry?.key ?? alert.counterpartyKey;

  if (alert.kind == AlertKind.charge) {
    return _record(smsId, alert, TxnStatus.excluded, null, source, key);
  }
  if (entry?.disposition == Disposition.notSpending) {
    return _record(smsId, alert, TxnStatus.excluded, null, source, key);
  }
  if (alert.kind == AlertKind.debit && (entry?.autoAssigns ?? false)) {
    return _record(smsId, alert, TxnStatus.labeled, entry!.categoryId, source, key);
  }
  // Nothing decided about this counterparty, but the merchant is one anybody
  // would recognise and the user tracks a category for it.
  //
  // Keyed on the absence of an *answer*, not of an entry. Seeding gives every
  // counterparty an entry at [Disposition.ask], and the backfill runs after
  // it, so requiring `entry == null` meant this never fired during a
  // migration -- the dictionary only ever worked on counterparties the app
  // had never seen, which is nearly none of them.
  if (alert.kind == AlertKind.debit &&
      (entry == null || entry.disposition == Disposition.ask) &&
      suggestedCategoryId != null) {
    return _record(smsId, alert, TxnStatus.labeled, suggestedCategoryId,
        LabelSource.dictionary, key);
  }
  // Credits are stored so the balance chain stays continuous, but they are
  // never pending: the user is not asked to categorise money arriving.
  final status = alert.kind == AlertKind.credit
      ? TxnStatus.excluded
      : TxnStatus.pending;
  return _record(smsId, alert, status, null, source, key);
}

TransactionRecord _record(String smsId, BankAlert a, TxnStatus status,
        String? categoryId, LabelSource source, String? counterpartyKey) =>
    TransactionRecord(
      smsId: smsId,
      bank: a.bank,
      kind: a.kind,
      channel: a.channel,
      status: status,
      amount: a.amount,
      balanceAfter: a.balanceAfter,
      occurredAt: a.occurredAt,
      account: a.account,
      narration: a.narration,
      counterpartyKey: counterpartyKey,
      categoryId: categoryId,
      source: status == TxnStatus.labeled ? source : null,
      isReversal: a.isReversal,
    );

/// Firestore forbids `/`, `.`, `#`, `[` and `]` in document ids, and bank
/// narrations contain slashes routinely.
String counterpartyDocId(String key) =>
    key.replaceAll(RegExp(r'[/\\.#\[\]]'), '_');

/// Counterparties worth a document of their own.
///
/// Most of what history turns up is one-off transfers the user will never
/// tag -- across a year of real data, only about a third of counterparties
/// were seen more than once. Persisting the rest triples the write volume
/// for no benefit. Singletons are simply created on demand: an unrecognised
/// counterparty already lands as pending and gets its entry the moment the
/// user answers.
///
/// Entries the migration has an opinion about -- a proposed self-transfer,
/// say -- are kept regardless of how often they appear.
Map<String, CounterpartyEntry> worthPersisting(
  Map<String, CounterpartyEntry> map) =>
  {
      for (final e in map.entries)
        if (e.value.txCount > 1 || e.value.disposition != Disposition.ask)
          e.key: e.value,
    };
