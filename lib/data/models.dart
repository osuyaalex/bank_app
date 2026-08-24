import '../parsing/bank_alert.dart';

/// How a counterparty should be treated when its transactions arrive.
enum Disposition {
  /// Auto-assign to [CounterpartyEntry.categoryId].
  tracked,

  /// The user's own account. Recorded, never counted as spending, never asked.
  notSpending,

  /// Always prompt. Set for keys that cannot identify a counterparty (see
  /// [isInstitutionOnlyKey]) and for keys the user keeps correcting.
  ask,
}

enum TxnStatus {
  /// Has a category and counts toward the month.
  labeled,

  /// Waiting for the user to say what it was.
  pending,

  /// Deliberately outside the totals: self-transfers and bank charges.
  excluded,
}

/// How a transaction got its category, for diagnostics and for deciding
/// whether the map may be updated from it.
enum LabelSource { map, user, dictionary, suggested, migration }

String slugifyCategory(String name) {
  final s = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'cat_${s.isEmpty ? 'unnamed' : s}';
}

/// A category definition. Lives at the user level and outlives any month, so
/// the counterparty map still resolves after the totals reset.
class Category {
  const Category({
    required this.id,
    required this.name,
    this.image,
    this.active = true,
  });

  final String id;
  final String name;
  final String? image;
  final bool active;

  factory Category.fromName(String name, {String? image}) =>
      Category(id: slugifyCategory(name), name: name, image: image);

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'image': image, 'active': active};
}

/// One counterparty and what to do with it.
class CounterpartyEntry {
  const CounterpartyEntry({
    required this.key,
    this.categoryId,
    this.disposition = Disposition.ask,
    this.overrideCount = 0,
    this.txCount = 0,
    this.lastSeen,
    this.aliases = const [],
  });

  final String key;
  final String? categoryId;
  final Disposition disposition;

  /// How many times the user has corrected an auto-assignment. At
  /// [overrideLimit] the entry falls back to [Disposition.ask]: repeated
  /// corrections mean the mapping is not reliable, and silently guessing wrong
  /// is worse than asking.
  final int overrideCount;

  final int txCount;
  final DateTime? lastSeen;

  /// Shorter spellings of [key] produced by SMS truncation. The same person
  /// arrives as `ALEXANDER ADENIYI O` and `ALEXANDER ADENI` depending on how
  /// much of the narration survived, and all of them must resolve here.
  final List<String> aliases;

  static const overrideLimit = 3;

  bool get autoAssigns =>
      disposition == Disposition.tracked &&
      categoryId != null &&
      overrideCount < overrideLimit;

  CounterpartyEntry copyWith({
    String? categoryId,
    Disposition? disposition,
    int? overrideCount,
    int? txCount,
    DateTime? lastSeen,
    List<String>? aliases,
  }) =>
      CounterpartyEntry(
        key: key,
        categoryId: categoryId ?? this.categoryId,
        disposition: disposition ?? this.disposition,
        overrideCount: overrideCount ?? this.overrideCount,
        txCount: txCount ?? this.txCount,
        lastSeen: lastSeen ?? this.lastSeen,
        aliases: aliases ?? this.aliases,
      );

  Map<String, dynamic> toMap() => {
        'key': key,
        'categoryId': categoryId,
        'disposition': disposition.name,
        'overrideCount': overrideCount,
        'txCount': txCount,
        'lastSeen': lastSeen?.toIso8601String(),
        'aliases': aliases,
      };
}

/// A single transaction. The unit the switch feature operates on -- without
/// these, a category total cannot be unwound.
class TransactionRecord {
  const TransactionRecord({
    required this.smsId,
    required this.bank,
    required this.kind,
    required this.channel,
    required this.status,
    this.amount,
    this.balanceAfter,
    this.occurredAt,
    this.account,
    this.narration = '',
    this.counterpartyKey,
    this.categoryId,
    this.source,
  });

  final String smsId;
  final String bank;
  final AlertKind kind;
  final TxnChannel channel;
  final TxnStatus status;
  final double? amount;
  final double? balanceAfter;
  final DateTime? occurredAt;
  final String? account;
  final String narration;
  final String? counterpartyKey;
  final String? categoryId;
  final LabelSource? source;

  /// Does this move a tracked category's total?
  bool get countsAsSpending =>
      kind == AlertKind.debit && status == TxnStatus.labeled;

  Map<String, dynamic> toMap() => {
        'smsId': smsId,
        'bank': bank,
        'kind': kind.name,
        'channel': channel.name,
        'status': status.name,
        'amount': amount,
        'balanceAfter': balanceAfter,
        'occurredAt': occurredAt?.toIso8601String(),
        'account': account,
        'narration': narration,
        'counterpartyKey': counterpartyKey,
        'categoryId': categoryId,
        'source': source?.name,
      };
}

/// The per-month ledger. Resets on the 1st; definitions and the map do not.
class MonthLedger {
  const MonthLedger({
    required this.month,
    this.budgets = const {},
    this.spend = const {},
    this.charges = 0,
    this.excluded = 0,
    this.closed = false,
  });

  /// `2026-08`.
  final String month;
  final Map<String, double> budgets;
  final Map<String, double> spend;

  /// Bank fees. Visible to the user, but outside every category budget --
  /// a fee is not a spending decision, so it must not consume a budget the
  /// user set for actual spending.
  final double charges;

  /// Money moved between the user's own accounts. Shown so it is not a silent
  /// omission, but never counted: it gets spent once it reaches the other
  /// account, and counting both legs double-counts it.
  final double excluded;

  final bool closed;

  Map<String, dynamic> toMap() => {
        'month': month,
        'budgets': budgets,
        'spend': spend,
        'charges': charges,
        'excluded': excluded,
        'closed': closed,
      };
}
