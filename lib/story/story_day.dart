/// Which day of the build the app should pretend it is.
///
/// The app is being shown as a story, a day at a time, and each day's screens
/// have to look the way they looked when that day's work was done. Rather than
/// unpicking features and putting them back -- which risks leaving something
/// half-removed and makes the branch impossible to keep in step with the real
/// one -- everything added after day one sits behind a flag here.
///
/// Change [day], rebuild, take the screenshots. Nothing else moves.
///
/// This file is the entire difference in behaviour between this branch and the
/// real app. Every flag below is `true` on `main`.
library;

class Story {
  const Story._();

  /// The day being shown. 1 is the app as it stood when the batch screen was
  /// first thought up; 7 is everything.
  static const day = 1;

  /// True when this build is telling the story at all. Set to false and the
  /// app behaves exactly as it does on main.
  static const enabled = day < 7;

  /// Reads a made-up inbox instead of the phone's, so no real person's name
  /// or payments can end up in a screenshot.
  static const demoData = enabled;

  // ---------------------------------------------------------------------
  // Day 2 -- the app starts recognising what things are.
  // ---------------------------------------------------------------------

  /// Ghost chips, the reasons written in words, and filing the obvious ones
  /// without being asked.
  static const suggestions = day >= 2;

  // ---------------------------------------------------------------------
  // Day 3 -- answering many at once.
  // ---------------------------------------------------------------------

  static const bulkSort = day >= 3;

  /// "14 already sorted. These are the next 22."
  static const progressCounts = day >= 3;

  // ---------------------------------------------------------------------
  // Day 4 -- a total measured against something.
  // ---------------------------------------------------------------------

  /// The budget bar under a total, and the colour it turns when it is passed.
  static const budgetLines = day >= 4;

  // ---------------------------------------------------------------------
  // Day 5 -- what a category is actually made of.
  // ---------------------------------------------------------------------

  /// Who the money went to, and moving it somewhere else.
  static const breakdown = day >= 5;

  // ---------------------------------------------------------------------
  // Day 6 -- budgets the app works out for itself.
  // ---------------------------------------------------------------------

  /// The suggestions banner, and Tight / Usual / Roomy in the budget picker.
  static const budgetsFromHistory = day >= 6;

  // ---------------------------------------------------------------------
  // Day 7 -- the things that make it survivable.
  // ---------------------------------------------------------------------

  /// Step guides, the explainer screen, the unreadable-inbox screen, and the
  /// bank charges line.
  static const guidance = day >= 7;
}
