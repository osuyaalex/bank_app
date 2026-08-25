import '../parsing/bank_alert.dart';
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
      lastSeen: (existing?.lastSeen == null ||
              (seen != null && seen.isAfter(existing!.lastSeen!)))
          ? (seen ?? existing?.lastSeen)
          : existing?.lastSeen,
    );
  }
  return out;
}

/// Ranks counterparties for the batch-tag screen: most frequent first, so the
/// smallest number of taps covers the largest share of transactions.
List<CounterpartyEntry> batchTagCandidates(
  Map<String, CounterpartyEntry> map, {
  int limit = 20,
}) {
  final list = map.values
      // `tracked` is already answered; `notSpending` is proposed separately as
      // a confirmation, not as a category choice.
      .where((e) => e.disposition == Disposition.ask)
      .where((e) => !isInstitutionOnlyKey(e.key))
      .toList()
    ..sort((a, b) => b.txCount.compareTo(a.txCount));
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
      // A self-transfer detected under any spelling applies to all of them.
      if (map[other]!.disposition == Disposition.notSpending) {
        disposition = Disposition.notSpending;
      }
    }

    canonical[k] = entry.copyWith(
      txCount: count,
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
  // Nothing learned about this counterparty, but the merchant is one anybody
  // would recognise and the user tracks a category for it.
  if (alert.kind == AlertKind.debit &&
      entry == null &&
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
