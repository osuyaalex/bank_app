/// The order the sorting flow asks its questions in, and when it stops.
///
/// The list this replaced put twenty-two counterparties on one screen with a
/// guide panel, an intro, a budget banner and a bulk bar stacked above them.
/// Every piece of that had been added to fix something real, and together
/// they were a wall: five separate propositions before the first row a user
/// could act on. People quit the app rather than read it.
///
/// The rules here are the whole difference. One question at a time, the
/// biggest money first, and every answer that settles other rows says so out
/// loud instead of resolving them silently in the background.
///
/// The flow used to open on a card offering budgets worked out from history.
/// It was removed: the setup screen asks for exactly those budgets, with the
/// same picker and the same figures drawn from the same months, one screen
/// earlier -- so the card re-asked a question the user had just answered, and
/// showed different numbers while doing it. What it uniquely knew, that money
/// is going somewhere untracked, the question cards already say better: they
/// offer to create the category for a payment the user is looking at, at the
/// moment it comes up, rather than as a list of abstractions beforehand.
library;

import '../data/models.dart';

/// One thing to put in front of the user.
sealed class SortStep {
  const SortStep();
}

/// Where one counterparty's payments belong.
class AskStep extends SortStep {
  const AskStep(this.entry);
  final CounterpartyEntry entry;
}

/// What the last answer took care of on its own.
///
/// Answering one row teaches the matcher something that settles others --
/// naming Family files every relative behind it. In the list that happened
/// silently while the user was looking at the sheet they had just closed, so
/// the app's best trick was invisible and its only evidence was rows the user
/// never saw. Here it is a card of its own: this is what you just did.
class CascadeStep extends SortStep {
  const CascadeStep({
    required this.trigger,
    required this.categoryName,
    required this.covered,
  });

  /// The counterparty the user actually answered.
  final String trigger;

  /// Where the covered rows went.
  final String categoryName;

  /// The rows that settled themselves as a result. Never empty -- a cascade
  /// of nothing is not a thing to announce.
  final List<CounterpartyEntry> covered;
}

/// Everything, in a list, at the end.
///
/// The list was never a bad screen; it was a review screen being used as an
/// input screen. Scanning twenty answers for the two that are wrong is
/// exactly what it is good at, and exactly what a card cannot do.
class ReviewStep extends SortStep {
  const ReviewStep();
}

/// What to show next.
///
/// A cascade always jumps the queue: it is the consequence of the answer just
/// given, and showing it later would attach it to the wrong question.
/// [skipped] rows are passed over rather than answered. They stay unanswered
/// -- they turn up again in the review list, and still count against the
/// total -- but the flow does not put the same question back in front of
/// someone who has just declined to answer it.
SortStep nextStep({
  required List<CounterpartyEntry> rows,
  required Set<String> answered,
  Set<String> skipped = const {},
  CascadeStep? cascade,
}) {
  if (cascade != null) return cascade;
  for (final r in rows) {
    if (!answered.contains(r.key) && !skipped.contains(r.key)) {
      return AskStep(r);
    }
  }
  return const ReviewStep();
}

/// The rows one answer settled on its own.
///
/// [trigger] is excluded: the user answered that one themselves and being
/// told they did is not news. Rows already answered before the tap are
/// excluded too, so a re-run of the matcher cannot re-announce old work.
List<CounterpartyEntry> cascadedBy({
  required String trigger,
  required Set<String> before,
  required Set<String> after,
  required List<CounterpartyEntry> rows,
}) => [
  for (final r in rows)
    if (r.key != trigger && !before.contains(r.key) && after.contains(r.key)) r,
];

/// How far through, counted in both of the ways that matter.
///
/// Rows answered is what the user can see. Money settled is what the answers
/// were worth, and the two come apart hard: the first five rows of a
/// money-ordered list routinely carry most of the month. Saying so is what
/// makes an early exit an achievement rather than a surrender.
class SortProgress {
  const SortProgress({
    required this.answered,
    required this.total,
    required this.moneySettled,
    required this.moneyTotal,
  });

  factory SortProgress.of(List<CounterpartyEntry> rows, Set<String> answered) {
    var settled = 0.0;
    var total = 0.0;
    var done = 0;
    for (final r in rows) {
      total += r.totalDebited;
      if (answered.contains(r.key)) {
        done++;
        settled += r.totalDebited;
      }
    }
    return SortProgress(
      answered: done,
      total: rows.length,
      moneySettled: settled,
      moneyTotal: total,
    );
  }

  final int answered;
  final int total;
  final double moneySettled;
  final double moneyTotal;

  int get remaining => total - answered;

  /// 0..1. Zero when nothing is known about the amounts, which is the case
  /// for counterparties recorded before spending was tracked per name.
  double get shareOfMoney =>
      moneyTotal <= 0 ? 0 : (moneySettled / moneyTotal).clamp(0.0, 1.0);

  /// Whether the flow has covered enough to be worth offering a way out.
  ///
  /// Two conditions, and both are needed. Most of the money has to be
  /// accounted for, or the offer is a lie; and enough rows have to remain
  /// that finishing them is a real chore, or the honest thing is to let the
  /// user run out naturally rather than talk them into stopping three taps
  /// from the end.
  bool get worthOfferingAnExit =>
      remaining >= 4 && answered >= 3 && shareOfMoney >= 0.7;
}
