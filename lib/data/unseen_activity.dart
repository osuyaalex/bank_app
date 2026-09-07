/// What has landed since the user last looked.
///
/// The app files money on its own, which is the point of it, and until now it
/// did that silently: a transaction arrived, went into a budget, and nothing
/// anywhere said which one. The only way to find out was to open every
/// category in turn and try to remember what had been there before.
///
/// Marking is deliberately local and deliberately capped. Local, because
/// "unseen" means unseen *by this person on this phone*, and because storing
/// a flag per transaction would mean a database write for a hint on a card.
/// Capped, because a marker on everything is a marker on nothing -- with six
/// budgets and daily spending, marking every affected category leaves the
/// whole screen lit by the second day, which is the state an unread count
/// reaches just before people stop reading it.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The most transactions kept per category.
///
/// Only the count and the row-marking need these, and nobody is going to pick
/// a hundred new rows out of a list. Past the cap the oldest are dropped and
/// the count keeps rising, which is the honest way round: the number stays
/// true even when the detail is trimmed.
const unseenPerCategoryCap = 50;

/// How many categories may be marked one by one before the screen collapses
/// to a single line instead.
const markIndividuallyUpTo = 3;

/// Whether to mark each category, or say it once and say it properly.
///
/// Above the cap the individual markers stop meaning anything, and one line
/// carrying a real figure -- "N48,200 across 5 budgets since you last
/// looked" -- is both quieter and more use than five blue edges.
bool markCategoriesIndividually(int categoriesWithUnseen) =>
    categoriesWithUnseen > 0 && categoriesWithUnseen <= markIndividuallyUpTo;

/// What is unseen, and which categories have earned a nudge.
///
/// A plain value so the rules can be tested without a plugin behind them.
class UnseenTally {
  const UnseenTally({
    this.ids = const {},
    this.lastSeen = const {},
    this.pendingNudge = const {},
    this.alreadyNudged = const {},
  });

  /// Category id to the transactions under it the user has not looked at.
  final Map<String, Set<String>> ids;

  /// Category id to when the user last opened it.
  final Map<String, DateTime> lastSeen;

  /// Categories that have collected something new *while already unseen*, and
  /// have not yet been nudged about it.
  final Set<String> pendingNudge;

  /// Categories already nudged about during the current unseen run.
  ///
  /// Kept apart from [pendingNudge], which empties as soon as the nudge is
  /// delivered. Without this the fourth transaction, and the fifth, would
  /// each look like the first one after a delivery and earn another buzz --
  /// which is precisely the nagging the single nudge exists to avoid. It
  /// clears when the category is opened, and only then.
  final Set<String> alreadyNudged;

  Set<String> unseenIn(String categoryId) => ids[categoryId] ?? const {};
  int countIn(String categoryId) => unseenIn(categoryId).length;
  bool isUnseen(String categoryId, String smsId) =>
      unseenIn(categoryId).contains(smsId);

  /// Categories carrying anything at all.
  Iterable<String> get marked =>
      ids.entries.where((e) => e.value.isNotEmpty).map((e) => e.key);

  int get total => ids.values.fold(0, (n, s) => n + s.length);

  /// True while each category is still worth marking on its own.
  bool get markIndividually => markCategoriesIndividually(marked.length);

  /// Records one newly filed transaction.
  ///
  /// A category that was *already* unseen and gets another one has earned a
  /// nudge: the user has been shown the marker and carried on past it, so the
  /// app says something once. Once, and not again until they open it -- a
  /// reminder that repeats is a reminder people learn to ignore, which is the
  /// opposite of what this is for.
  UnseenTally record(String categoryId, String smsId) {
    final existing = ids[categoryId] ?? const <String>{};
    if (existing.contains(smsId)) return this; // a re-scan, not news

    final wasAlreadyUnseen = existing.isNotEmpty;
    final next = [...existing, smsId];
    // Oldest first out. The count below is taken before trimming, so it stays
    // true even once the detail has been dropped.
    final trimmed = next.length > unseenPerCategoryCap
        ? next.sublist(next.length - unseenPerCategoryCap)
        : next;

    final earnsNudge =
        wasAlreadyUnseen &&
        !pendingNudge.contains(categoryId) &&
        !alreadyNudged.contains(categoryId);

    return UnseenTally(
      ids: {...ids, categoryId: trimmed.toSet()},
      lastSeen: lastSeen,
      pendingNudge: earnsNudge ? {...pendingNudge, categoryId} : pendingNudge,
      alreadyNudged: alreadyNudged,
    );
  }

  /// The user opened this category. Everything under it has been seen.
  UnseenTally markSeen(String categoryId, {DateTime? at}) => UnseenTally(
    ids: {...ids}..remove(categoryId),
    lastSeen: {...lastSeen, categoryId: at ?? DateTime.now()},
    pendingNudge: {...pendingNudge}..remove(categoryId),
  );

  /// The nudge has been delivered. It is not delivered twice.
  UnseenTally nudged() => UnseenTally(
    ids: ids,
    lastSeen: lastSeen,
    pendingNudge: const {},
    alreadyNudged: {...alreadyNudged, ...pendingNudge},
  );

  Map<String, dynamic> toJson() => {
    'ids': ids.map((k, v) => MapEntry(k, v.toList())),
    'lastSeen': lastSeen.map((k, v) => MapEntry(k, v.millisecondsSinceEpoch)),
    'nudge': pendingNudge.toList(),
  };

  static UnseenTally fromJson(Map<String, dynamic> m) => UnseenTally(
    ids: {
      for (final e in (m['ids'] as Map? ?? {}).entries)
        e.key.toString(): Set<String>.from(
          (e.value as List? ?? const []).map((x) => x.toString()),
        ),
    },
    lastSeen: {
      for (final e in (m['lastSeen'] as Map? ?? {}).entries)
        e.key.toString(): DateTime.fromMillisecondsSinceEpoch(
          (e.value as num).toInt(),
        ),
    },
    pendingNudge: Set<String>.from(
      (m['nudge'] as List? ?? const []).map((x) => x.toString()),
    ),
  );
}

/// The stored tally.
///
/// Every call is guarded: a marker that cannot be read is a missing hint, and
/// a missing hint must never be allowed to take a screen down with it.
class UnseenActivity {
  const UnseenActivity._();

  static const _key = 'unseen_activity_v1';

  static Future<UnseenTally> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null || raw.isEmpty) return const UnseenTally();
      return UnseenTally.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const UnseenTally();
    }
  }

  static Future<void> save(UnseenTally tally) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode(tally.toJson()),
      );
    } catch (_) {
      /* a hint that will not persist is survivable */
    }
  }

  /// Records one newly filed transaction and stores the result.
  static Future<void> record(String categoryId, String smsId) async =>
      save((await load()).record(categoryId, smsId));

  static Future<void> markSeen(String categoryId) async =>
      save((await load()).markSeen(categoryId));

  static Future<void> clearNudges() async => save((await load()).nudged());
}
