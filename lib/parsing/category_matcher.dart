import 'category_lexicon.dart';
import 'merchant_dictionary.dart';

/// A suggested category, and how much the app believes it.
///
/// Confidence exists so the app can act *and* be honest about it. Filing
/// everything silently would put money in the wrong budget without saying so;
/// asking about everything is the tagging chore this feature exists to remove.
/// A scored guess does both: it files, and it marks the ones worth a glance.
class CategoryGuess {
  const CategoryGuess({
    required this.categoryName,
    required this.confidence,
    required this.reason,
    this.suggestedOptions = const [],
  });

  /// The tracked category this belongs to, or empty when the user tracks
  /// nothing that fits.
  final String categoryName;

  /// Categories worth creating for this counterparty, when none of the
  /// tracked ones fit.
  ///
  /// A list rather than one name, because certainty varies. For a merchant
  /// the app knows, there is a right answer. For somebody's name there is
  /// not -- the user themselves may not know whether a transfer to Joy was a
  /// gift, a loan or lunch. Offering two or three plausible buckets on the
  /// card lets them decide from the surface instead of opening the picker to
  /// find nothing better.
  final List<String> suggestedOptions;

  /// The first suggestion, for callers that only want one.
  String? get suggestedNew =>
      suggestedOptions.isEmpty ? null : suggestedOptions.first;

  /// 0..1.
  final double confidence;

  /// Why, in words the user can judge: "Chowdeck is a food delivery service".
  /// A number alone tells them how sure the app is but not what to check.
  final String reason;

  /// At or above this, the guess is presented as settled.
  static const certain = 0.85;

  /// Below this, no guess is offered at all -- a wrong answer nobody notices
  /// is worse than an honest question.
  static const floor = 0.5;

  bool get isCertain => confidence >= certain;

  /// True when there is a category to create rather than one to file into.
  bool get needsNewCategory =>
      categoryName.isEmpty && suggestedOptions.isNotEmpty;

  /// How to say "I am not certain" without a number.
  ///
  /// A percentage reads as precision the app does not have -- "54% sure"
  /// invites the user to trust a figure that is really a rule of thumb. Plain
  /// language sets the same expectation and tells them what to do about it.
  String? get note {
    if (isCertain) return null;
    if (confidence >= 0.65) return 'Best guess — tap if this is wrong';
    return "Not sure about this one — worth a check";
  }
}

/// A category name worth offering for [concept].
///
/// Title-cased, because it becomes a name the user sees and keeps.
String categoryNameForConcept(String concept) => concept
    .split(' ')
    .map((w) =>
        w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
    .join(' ');

/// Words too common to carry meaning on their own.
const _stopWords = {
  'ltd', 'limited', 'plc', 'nig', 'nigeria', 'nigerian', 'the', 'and', 'of',
  'for', 'int', 'intl', 'international', 'global', 'company', 'co', 'inc',
  'services', 'service', 'solutions', 'solution', 'group', 'holdings',
  'resources', 'systems', 'general', 'multi', 'concept', 'concepts',
  'from', 'to', 'via', 'transfer', 'trf', 'payment', 'pymt', 'pay',
};

/// Reduces a word to something comparable.
///
/// Deliberately shallow. An aggressive stemmer turns unrelated words into the
/// same root and starts inventing matches; the lexicon carries plural and
/// derived forms explicitly, and this only closes the remaining gap.
String stemWord(String word) {
  var w = word.toLowerCase();
  if (w.length <= 4) return w;
  for (final suffix in const ['ies', 'ing', 'ers', 'es', 's']) {
    if (w.length > suffix.length + 3 && w.endsWith(suffix)) {
      w = w.substring(0, w.length - suffix.length);
      if (suffix == 'ies') w = '${w}y';
      break;
    }
  }
  return w;
}

List<String> _tokens(String key) => key
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.length > 1 && !_stopWords.contains(t))
    .toList();

/// Concepts implied by the words in a counterparty name.
///
/// `JULIANA CONFECTIONARIES` yields `snacks` -- nobody has heard of Juliana,
/// but the second word says exactly what was bought.
List<String> conceptsFromWords(String key) {
  final tokens = _tokens(key);
  final stems = tokens.map(stemWord).toSet();

  // concept -> the strongest evidence found for it.
  final best = <String, _Evidence>{};

  conceptKeywords.forEach((concept, words) {
    for (final w in words) {
      if (tokens.contains(w)) {
        best[concept] = _Evidence(w.length, exact: true);
        return;
      }
    }
    for (final w in words) {
      if (stems.contains(stemWord(w))) {
        best[concept] = _Evidence(w.length, exact: false);
        return;
      }
    }
    // Truncation. Banks cut narrations mid-word -- `DE PROVENCE SUPERMARK`
    // is a supermarket the alert had no room to finish spelling. Requiring
    // five characters keeps "car" out of "carpenter" while letting
    // "supermark" reach "supermarket".
    for (final w in words) {
      if (w.length < 6) continue;
      for (final t in tokens) {
        if (t.length >= 5 && t.length < w.length && w.startsWith(t)) {
          best[concept] = _Evidence(t.length, exact: false);
          return;
        }
      }
    }
  });

  // Most specific first. `MAMA BAKERY` matches both `food` (on "mama") and
  // `snacks` (on "bakery"); the longer word is the one that actually says
  // what the business is, and taking whichever concept happened to be
  // declared first filed a bakery under Food.
  final ordered = best.keys.toList()
    ..sort((a, b) {
      final ea = best[a]!, eb = best[b]!;
      if (ea.exact != eb.exact) return ea.exact ? -1 : 1;
      return eb.length.compareTo(ea.length);
    });
  return ordered;
}

class _Evidence {
  const _Evidence(this.length, {required this.exact});
  final int length;
  final bool exact;
}

/// Matches a concept against the categories the user actually tracks.
///
/// Whole words only. `car` sits inside `healthcare`, which once filed a fuel
/// station as a medical expense -- a plausible wrong answer nobody checks.
String? _categoryFor(String concept, Iterable<String> tracked) {
  final byLower = {for (final t in tracked) t.toLowerCase(): t};
  final exact = byLower[concept];
  if (exact != null) return exact;

  for (final entry in byLower.entries) {
    final words = entry.key.split(RegExp(r'[^a-z0-9]+'));
    if (words.contains(concept)) return entry.value;
    // "Food" should match a tracked "Food & Drinks"; also the reverse, so a
    // tracked "Snacks" catches the "snacks" concept regardless of phrasing.
    for (final w in words) {
      if (w.length > 3 && stemWord(w) == stemWord(concept)) return entry.value;
    }
  }
  return null;
}

/// Whether every part of the owner's name appears in [keyParts].
///
/// Subset rather than equality, because the two rarely match exactly: a bank
/// prints the full legal name including middle names, while a profile holds
/// whatever the user typed at signup. Prefixes count in both directions, so a
/// profile saying "Alex" still recognises a narration saying "ALEXANDER".
bool isOwnName(List<String> ownerParts, Set<String> keyParts) {
  // A single name is too weak: half an address book shares a first name.
  if (ownerParts.length < 2) return false;
  for (final part in ownerParts) {
    final found = keyParts.any((k) =>
        k == part ||
        (part.length >= 4 && k.startsWith(part)) ||
        (k.length >= 4 && part.startsWith(k)));
    if (!found) return false;
  }
  return true;
}

/// The surname shared with the account holder, if any.
///
/// A transfer to someone with your surname is usually family. It is a strong
/// signal and a cheap one, but it needs a guard: the account holder's *own*
/// name matches too, and that is a transfer between your own accounts rather
/// than money sent to a relative.
String? sharedSurname(String key, String? ownerName) {
  if (ownerName == null) return null;
  final ownerParts = ownerName
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((p) => p.length > 2)
      .toList();
  if (ownerParts.isEmpty) return null;

  final keyParts = key
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((p) => p.length > 2)
      .toSet();
  if (keyParts.isEmpty) return null;

  // Every part of the owner's name present means this is the user, not a
  // relative. Counting exact matches was not enough: bank narrations carry
  // middle names the profile does not, so `ALEXANDER ADENIYI OSUYA` matched
  // only two of three parts and the account holder was offered as family.
  if (isOwnName(ownerParts, keyParts)) return null;

  // A surname is conventionally the last part; check the first too, since
  // Nigerian bank narrations order names inconsistently.
  for (final candidate in {ownerParts.last, ownerParts.first}) {
    if (keyParts.contains(candidate)) return candidate;
  }
  return null;
}

/// The app's best guess at where a counterparty belongs.
///
/// Layered, most trustworthy first, and each layer carries its own confidence
/// rather than a single flat verdict. A known merchant matching a tracked
/// category by name is near-certain; a shared word in an unknown trader's name
/// is a fair guess worth showing but worth checking too.
CategoryGuess? guessCategory(
  String counterpartyKey,
  Iterable<String> trackedCategories, {
  String? ownerName,
  String? channelHint,
  bool twoWayMoney = false,
  bool mostlyRoundAmounts = false,
}) {
  final tracked = trackedCategories.toList();
  if (tracked.isEmpty || counterpartyKey.trim().isEmpty) return null;

  // 1. Airtime and data.
  //
  // Recognised from the key as well as the rail: the parser collapses every
  // top-up to `AIRTIME MTN`, so the key alone is proof even when the channel
  // was not carried through.
  //
  // The preference order matters. The merchant list maps airtime to
  // `[airtime, data, internet, utilities]`, and taking the first tracked one
  // filed a phone top-up as Internet while the user had a Mobile Phone
  // budget sitting right there.
  final looksLikeAirtime = channelHint == 'airtime' ||
      RegExp(r'^AIRTIME\b|^DATA\s*BUNDLE\b|^BUNDLE\b', caseSensitive: false)
          .hasMatch(counterpartyKey);
  if (looksLikeAirtime) {
    const strong = ['mobile phone', 'airtime', 'data', 'phone', 'recharge'];
    final c = _firstCategory(strong, tracked);
    if (c != null) {
      return CategoryGuess(
        categoryName: c,
        confidence: 0.94,
        reason: 'This is an airtime or data purchase.',
      );
    }
    // Nothing that names the phone directly. Utilities or Internet is the
    // nearest thing, but it is a stand-in rather than the right answer, so
    // it is offered with the doubt showing.
    final near = _firstCategory(['internet', 'utilities', 'bills'], tracked);
    if (near != null) {
      return CategoryGuess(
        categoryName: near,
        confidence: 0.7,
        reason: 'Airtime or data. Filed under $near for now.',
      );
    }
    return const CategoryGuess(
      categoryName: '',
      suggestedOptions: ['Mobile Phone', 'Utilities'],
      confidence: 0.9,
      reason: 'This is an airtime or data purchase.',
    );
  }

  // 2. A merchant the app knows by name.
  final merchantConcepts = conceptsFor(counterpartyKey);
  if (merchantConcepts.isNotEmpty) {
    final c = _firstCategory(merchantConcepts, tracked);
    if (c != null) {
      return CategoryGuess(
        categoryName: c,
        confidence: 0.93,
        reason: '${_titleCase(counterpartyKey)} is a known '
            '${merchantConcepts.first} merchant.',
      );
    }
    return CategoryGuess(
      categoryName: '',
      suggestedOptions: _optionsFrom(merchantConcepts),
      confidence: 0.9,
      reason: '${_titleCase(counterpartyKey)} is a '
          '${merchantConcepts.first} merchant.',
    );
  }

  // 3. A surname shared with the account holder.
  final surname = sharedSurname(counterpartyKey, ownerName);
  if (surname != null) {
    final c = _firstCategory(['family'], tracked);
    if (c != null) {
      return CategoryGuess(
        categoryName: c,
        confidence: 0.8,
        reason: 'Shares your surname, so probably family.',
      );
    }
    // No Family category to file into. Rather than leaving the user to work
    // that out, offer the name and ask only for the budget.
    return const CategoryGuess(
      categoryName: '',
      suggestedOptions: ['Family', 'Friends', 'Gifts'],
      confidence: 0.8,
      reason: 'Shares your surname, so probably family.',
    );
  }

  // 4. Words in the name that say what was bought.
  //
  final wordConcepts = conceptsFromWords(counterpartyKey);
  for (final concept in wordConcepts) {
    final exactWord =
        _tokens(counterpartyKey).any(conceptKeywords[concept]!.contains);
    final c = _categoryFor(concept, tracked);
    if (c != null) {
      return CategoryGuess(
        categoryName: c,
        confidence: exactWord ? 0.72 : 0.62,
        reason: exactWord
            ? '"${_titleCase(concept)}" in the name suggests $c.'
            : 'The name reads like $c.',
      );
    }
  }

  // Nothing tracked fits, but the name still said what it was. Offer the
  // category rather than making the user name it themselves.
  for (final concept in wordConcepts) {
    if (nonSpendingConcepts.contains(concept)) continue;
    return CategoryGuess(
      categoryName: '',
      suggestedOptions: _optionsFrom([concept]),
      confidence: 0.7,
      reason: 'The name suggests ${categoryNameForConcept(concept)}, '
          'which you are not tracking yet.',
    );
  }

  // 5. A bare personal name.
  //
  // No keyword can place it, and picking one category would file a friend's
  // rent contribution under Groceries. But leaving it blank is the outcome
  // that costs the user the most work, so instead the app offers the buckets
  // people actually use for other people and lets them pick from the card.
  if (looksLikePersonName(counterpartyKey)) {
    // Money that has moved both ways is the strongest thing the app knows
    // about a bare name. A shop takes money and never sends it back, so a
    // counterparty who has also paid the user is somebody they have a
    // relationship with -- a friend, a relative, someone they split bills
    // with. It costs nothing to collect and beats every other signal here.
    if (twoWayMoney) {
      final c = _firstCategory(['friends', 'family', 'others'], tracked);
      if (c != null) {
        return CategoryGuess(
          categoryName: c,
          confidence: 0.68,
          reason: 'Money moves both ways with them, so someone you know '
              'rather than a shop.',
        );
      }
      return const CategoryGuess(
        categoryName: '',
        suggestedOptions: ['Friends', 'Family', 'Others'],
        confidence: 0.68,
        reason: 'Money moves both ways with them, so someone you know rather '
            'than a shop.',
      );
    }

    // Family is deliberately absent below. It is reserved for a surname match
    // or two-way money, both already tried -- reaching here means nothing
    // suggests a relative, and filing a stranger under Family because Family
    // happens to be the only bucket tracked is a worse answer than none.
    const neutral = ['others', 'miscellaneous', 'friends', 'gifts'];
    final trackedBucket = _firstCategory(neutral, tracked);
    if (trackedBucket != null) {
      return CategoryGuess(
        categoryName: trackedBucket,
        confidence: mostlyRoundAmounts ? 0.56 : 0.52,
        reason: mostlyRoundAmounts
            ? 'Round amounts sent to a person. Parked in $trackedBucket — '
                'move it if it belongs somewhere else.'
            : 'Money sent to a person. Parked in $trackedBucket — '
                'move it if it belongs somewhere else.',
      );
    }
    return const CategoryGuess(
      categoryName: '',
      suggestedOptions: ['Others', 'Friends', 'Gifts'],
      confidence: 0.5,
      reason: 'Money sent to a person, not a purchase. Pick where it belongs.',
    );
  }

  // 6. Nothing at all. Rather than an empty row, offer the catch-alls, which
  // is what a user does with an unplaceable payment anyway.
  return CategoryGuess(
    categoryName: _firstCategory(['others', 'miscellaneous'], tracked) ?? '',
    suggestedOptions: _firstCategory(['others', 'miscellaneous'], tracked) == null
        ? const ['Others', 'Miscellaneous']
        : const [],
    confidence: 0.4,
    reason: 'Could not work this one out.',
  );
}

/// Whether a counterparty reads as somebody's name.
///
/// Two to four alphabetic words, none of which mean anything commercial. Kept
/// strict: the point is to say "this is a person" only when that is genuinely
/// all the app can tell.
bool looksLikePersonName(String key) {
  final words = key
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((w) => w.length > 1)
      .toList();
  if (words.length < 2 || words.length > 4) return false;
  if (RegExp(r'\d').hasMatch(key)) return false;

  // Any commercial word at all and this is a business, not a person.
  for (final words0 in conceptKeywords.values) {
    for (final w in words) {
      if (words0.contains(w)) return false;
    }
  }
  return !words.any(_stopWords.contains);
}

/// Up to three category names worth offering for [concepts].
///
/// More than three turns a card into a menu; fewer than two implies a
/// certainty the app does not have for the vaguer cases.
List<String> _optionsFrom(Iterable<String> concepts) {
  final out = <String>[];
  for (final c in concepts) {
    if (nonSpendingConcepts.contains(c)) continue;
    final name = categoryNameForConcept(c);
    if (!out.contains(name)) out.add(name);
    if (out.length == 3) break;
  }
  return out;
}

String? _firstCategory(Iterable<String> concepts, List<String> tracked) {
  for (final concept in concepts) {
    final c = _categoryFor(concept, tracked);
    if (c != null) return c;
  }
  return null;
}

String _titleCase(String s) {
  if (s.isEmpty) return s;
  return s
      .split(' ')
      .map((w) => w.isEmpty
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}
